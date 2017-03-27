#-
# Copyright (c) 2014-2015 Khilan Gudka
# Copyright (c) 2015 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#

import Queue
import nose
import os
import signal
import subprocess
import sys
import time
from nose.tools import timed
from nose.plugins.skip import Skip, SkipTest
from Queue import Queue, Empty
from re import search, IGNORECASE
from subprocess import Popen
from threading import Thread
import xml.etree.ElementTree as ET

#
# Environment variables that influence the behaviour of/are required by this
# script:
#   SLEEP_AFTER_TEST:   sleep for 1 second after each test run by cheritest
#   CHERITEST_LIST_XML: name of XML file containing list of cheritest tests to
#                       be run
#   CPU:                cpu being tested, valid values: BERI1, CHERI1, BERI2,
#                       CHERI2, CHERI2-MT)
#   OS:                 os being tested, valid values: FreeBSD, CheriBSD
#
# Configurable parameters:
#   boot_timeout:       hard time limit on boot test
#   hw_timeout:         hard time limit on hello world test
#   cheritest_timeout:  hard time limit on entire cheritest test
#   post_error_timeout: hard time limit on execution after having detected an
#                       error (allows bounded time for collecting additional
#                       error context such as register dumps)
#   error_regex:        regex describing when an error has been detected
#
# This script should be run as follows from the cheribsd/trunk/simboot 
# directory:
#   simboot> nosetests -s tests/test_boot.py
#

class TimeExpired(AssertionError):
  pass

global sim # simulator process, forked by setup_module()
global boot_succeeded # if booting fails, then all subsequent tests should not run
global hw_succeeded
global debug_xml
global timeout_exceeded

boot_succeeded = False
hw_succeeded = False

boot_timeout = 8*3600 # hard timeout for boot test
hw_timeout = 2*3600 # hard timeout for hello world test
cheritest_timeout = 24*3600 # hard timeout for entire cheritest test
post_error_timeout = 5*60 # how long to wait (after an error has been
                          # detected) before failing the test

error_regex = "error|panic|not found|abnormally|stopped at|register dump"

# allow double time for multi-core or multi-threaded CPU 
if os.getenv("CPU") == "CHERI2-MT" or os.getenv("CPU") == "CHERI1-MULTI2" or os.getenv("CPU") == "BERI1-MULTI2":
  boot_timeout = boot_timeout*2
  hw_timeout = hw_timeout*2
  cheritest_timeout = cheritest_timeout*2
  print "Allowing extra time for simulating multithreaded CPU"

# debugging
debug_xml = True

# hard timeouts are achieved by setting an alarm and then raising an exception
def set_timeout(timeout, post_error = False):
  print "Setting %s timeout of %d seconds" % ("post-error" if post_error else "test", timeout)
  global timeout_exceeded
  timeout_exceeded = False
  signal.alarm(timeout)

def timeout_handler(signum, frame):
  global timeout_exceeded
  timeout_exceeded = True
  raise TimeExpired()

def write_unbuffered(string):
  sys.stdout.write(string)
  sys.stdout.flush()

# Setup function that starts running the simulator before any test begins
def setup_module():
  print "Running setup_module"
  global sim
  if os.getenv("CHERI_TRACE_LOG"):
    target = "trace"
  else:
    target = "run"
  sim = subprocess.Popen(["make",target], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  signal.signal(signal.SIGALRM, timeout_handler)

# Teardown function that kills the simulator (if it is still running) after
# all tests have finished
def teardown_module():
  print "Running teardown_module"
  if sim.returncode == None:
    sim.kill()

# Test whether the simulation has successfully booted FreeBSD/CheriBSD.  This
# relies on the string "Done booting" being output upon successful boot, as is
# done by the smoketest configurations.
#@timed(boot_timeout) # timeout of 3 hours
def test_boot():

  print "Running test_boot"

  if os.getenv("OS") == "CheriBSD" and os.getenv("CPU").upper().startswith("BERI"):
    raise SkipTest("Skipping CheriBSD/BERI boot test")
  
  # scan output of simulation looking for signs that an error has occurred
  # or that everything is fine
  booted_regex = "Done booting"
  success = False
  error_detected = False

  set_timeout(boot_timeout)

  start = time.time()

  while True: 
    line = sim.stdout.readline()
    if line == '':
      break
    # echo to our stdout
    write_unbuffered(line)
    if not error_detected:
      if search(error_regex, line, IGNORECASE) != None:
        error_detected = True
        set_timeout(post_error_timeout, True)
      elif search(booted_regex, line) != None:
        success = True
        break
  
  elapsed_secs = time.time()-start
  write_unbuffered("Boot test finished - took %.2f secs\n" % elapsed_secs)

  global boot_succeeded
  boot_succeeded = success and sim.returncode == None # sim should still be running
  assert boot_succeeded 

# Run cheri_helloworld. Looks for three occurrences of the string "hello world"
#@timed(hw_timeout) # timeout of 2 hours
def test_helloworld():

  print "Running cheri_helloworld"
  
  if not (os.getenv("OS") == "CheriBSD" and os.getenv("CPU").upper().startswith("CHERI")) or not boot_succeeded:
    raise SkipTest("Skipping cheri_helloworld test")
  
  if sim.returncode != None:
    raise AssertionError("Simulator is not running")

  helloworld_str = "hello world"
  helloworld_cnt = 0
  
  # Invoke cheri_helloworld with an absolute pathname. This is a work-around
  # for a bug in cheri_helloworld where it uses argv[0] to find the pathname
  # of its own executable.
  sim.stdin.write('/bin/cheri_helloworld\n')
  success = False
  error_detected = False
  
  set_timeout(hw_timeout)
  
  start = time.time()

  while True:
    line = sim.stdout.readline()
    if line == '': 
      break
    # echo to our stdout
    write_unbuffered(line)
    # process output of cheri_helloworld
    # declare success if we see "hello world" output
    # 3 times
    if not error_detected:
      if search(error_regex, line, IGNORECASE) != None:
        error_detected = True
        set_timeout(post_error_timeout, True)
      elif search(helloworld_str, line) != None:
        helloworld_cnt += 1
        if helloworld_cnt == 3:
          success = True
          break
  
  elapsed_secs = time.time()-start
  write_unbuffered("Hello world test finished - took %.2f secs\n" % elapsed_secs)
  global hw_succeeded
  hw_succeeded = success and sim.returncode == None
  assert hw_succeeded


global parser_error

parser_error = False

# Run cheritest tests. The list of tests is found in the xml file specified
# by the environment variable CHERITEST_LIST_XML
#@timed(cheritest_timeout) # timeout of 3 hours
def test_cheritest():
  
  write_unbuffered("Running cheritest -a -f\n")

  if not (os.getenv("OS") == "CheriBSD" and os.getenv("CPU").upper().startswith("CHERI")) \
     or not boot_succeeded or not hw_succeeded:
    raise SkipTest("Skipping cheritest test")

  set_timeout(cheritest_timeout)

  # minimise kernel output
  sim.stdin.write("/sbin/sysctl machdep.log_cheri_exceptions=0\n")
  sim.stdin.write("/sbin/sysctl machdep.log_bad_page_faults=0\n");
  sim.stdin.write("/sbin/sysctl machdep.unaligned_log_pps_limit=0\n");
  sim.stdin.write("/sbin/sysctl kern.log_cheri_unwind=0\n");

  # if SLEEP_AFTER_TEST is set, sleep for 1 second after each test
  # to prevent output being lost by the UART
  if (os.getenv("SLEEP_AFTER_TEST") != None):
    sim.stdin.write('/bin/cheritest -a -f -s --libxo xml,pretty\n')
  else:
    sim.stdin.write('/bin/cheritest -a -f --libxo xml,pretty\n')
  
  start = time.time()

  # gobble up all output until we see xml
  while True:
    line = sim.stdout.readline() 
    if search("<testsuite>", line) != None:
      break
    else:
      write_unbuffered(line)
  
  tree = ET.parse(os.getenv("CHERITEST_LIST_XML"))
  root = tree.getroot()
  for test in root.iter('test'):
    if timeout_exceeded:
      return
    name = test.find('name').text
    timeout = test.find('timeout')
    if timeout == None or timeout.text != "LONG":
      # hack to prevent test's name and description
      # being overwritten by subsequent iterations
      test_fn = lambda x: parse_single(x)
      test_fn.name = name
      test_fn.description = name
      yield test_fn, name
      #yield parse_single, name # nose
      #parse_single(name) # testing

  elapsed_secs = time.time()-start
  write_unbuffered("cheritest tests finished - took %.2f secs\n" % elapsed_secs)

  if sim.returncode != None:
    raise AssertionError("Simulator is not running")
  
  if not parser_error:
    line = sim.stdout.readline()
    if debug_xml:
      write_unbuffered(line)
    assert search("</testsuite>", line) != None

# Method that parses a single cheritest test's output
#@timed(1800) # timeout of 30 mins
def parse_single(name):
  
  write_unbuffered("\n%s: " % name)

  if sim.returncode != None:
    raise AssertionError("Simulator is not running")
    
  global parser_error

  if parser_error:
    raise AssertionError("Reached end of XML without finding test result")


  testXML = ""
  collecting = False
  success = False
  while True:
    line = sim.stdout.readline()

    if debug_xml:
      write_unbuffered(line)

    if search("</testsuite>", line) != None:
      parser_error = True
      raise AssertionError("Reached the end of the XML unexpectedly")

    if search("<test>", line) != None:
      testXML = line
      collecting = True
      start = time.time()
    
    elif search ("</test>", line) != None:
      testXML += line
      collecting = False
      
      elapsed_secs = time.time()-start

      # parse XML
      root = ET.fromstring(testXML)
      found_name = root.find('name')
      if debug_xml:
        write_unbuffered("XML file contained results for %s\n" % found_name.text)
      if name != found_name.text:
        raise AssertionError("Found results for %s, expected %s" % (found_name.text, name))
      
      # output test result
      status = root.find('status')
      if status.text == 'PASS':
        if status.get('expected') == "false":
          expected_failure_reason = root.find('expected-failure-reason').text
          failure_reason = "Test passed but was expected to fail due to: %s" % expected_failure_reason
          write_unbuffered("FAIL (%s) - took %.2f secs\n" % (failure_reason, elapsed_secs))
          raise AssertionError(failure_reason)
        else:
          success = True
          write_unbuffered("PASS - took %.2f secs\n" % elapsed_secs)
      
      elif status.text == 'FAIL':
        failure_reason = root.find('failure-reason').text
        if status.get('expected') == "true":
          success = True
          write_unbuffered(
            "XFAIL (failure reason: %s, expected due to: %s) - took %.2f secs\n"
            % (failure_reason, root.find('expected-failure-reason').text, elapsed_secs)
          )
        else:
          write_unbuffered("FAIL (%s) - took %.2f secs\n" % (failure_reason, elapsed_secs))
          raise AssertionError(failure_reason)
      
      break
    
    elif collecting:
      testXML += line

  assert success and sim.returncode == None # sim should still be running
