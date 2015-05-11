#!/usr/bin/env python
#
# Copyright (c) 2014 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
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


import xml.etree.ElementTree as ET
import re

class Qsys:
    "Massage a Qsys file by changing various parts of the XML tree"

    # currently doesn't handle the bonusData section due to lack of a proper
    # parser for that grammar, but Qsys seems to manage if we strip that section

    def __init__(self, filename):
        "Load a Qsys file and create a Qsys object containing its parse tree"
        [self.tree, self.root] = self.readQsys(filename)

    def readQsys(self, filename):
        "Read a Qsys project from a file and parse the XML"
        self.tree = ET.parse(filename)
        self.root = self.tree.getroot()
        return [self.tree, self.root]


    def deleteConnection(self, start, end):
        "Delete a named connection between two modules"

        connections = self.root.findall('./connection')
        print connections

        for connection in connections:
            if ((connection.attrib['start']==start and connection.attrib['end']==end) or
                (connection.attrib['start']==end and connection.attrib['end']==start)):
                print connection.attrib
                self.root.remove(connection)

        return self.root

    def deleteConduit(self, component, port):
        "Delete a conduit from a named module. " \
        "Note this is the name of the port on the module, not the exported name"

        interfaces = self.root.findall('./interface')
        print interfaces

        for interface in interfaces:
            print interface.attrib['internal']
            if (interface.attrib['internal']==component+'.'+port):
                print interface
                self.root.remove(interface)

        return self.root


    def deleteComponent(self, componentName):
        "Delete a named component and all of its connections"

        # remove all its connections
        connections = self.root.findall('./connection')
        print connections
        for connection in connections:
            [startComponent, startNode] = connection.attrib['start'].split('.')
            [endComponent, endNode] = connection.attrib['end'].split('.')
            print "%s -> %s" % (startComponent, endComponent)
            if (startComponent == componentName or endComponent == componentName):
                self.root.remove(connection)

        # and the component itself
        components = self.root.findall('./module')
        print components
        for component in components:
            if (component.attrib['name']==componentName):
                print component.attrib
                self.root.remove(component)

        # and its interfaces
        interfaces = self.root.findall('./interface')
        print interfaces
        for interface in interfaces:
            print interface.attrib['internal']
            if (interface.attrib['internal'].split('.')[0]==component):
                print interface
                self.root.remove(interface)


        return

    def renameComponent(self, oldName, newName):
        "Rename a component instance"

        # rename the connections
        connections = self.root.findall('./connection')
        print connections
        for connection in connections:
            [startComponent, startNode] = connection.attrib['start'].split('.')
            [endComponent, endNode] = connection.attrib['end'].split('.')
            print "%s.%s -> %s.%s" % (startComponent, startNode, endComponent, endNode)
            if (startComponent == oldName):
                connection.attrib['start'] = newName+'.'+startNode
            if (endComponent == oldName):
                connection.attrib['end'] = newName+'.'+endNode

        # and the component
        components = self.root.findall('./module')
        print components
        for component in components:
            if (component.attrib['name']==oldName):
                print component.attrib
                component.attrib['name'] = newName

        # and all its interfaces (exported conduits)
        interfaces = self.root.findall('./interface')
        print interfaces
        for interface in interfaces:
            print interface.attrib['internal']
            [interfaceComponent, interfaceNode] = interface.attrib['internal'].split('.')
            if (interfaceComponent==oldName):
                print interface.attrib
                interface.attrib['internal'] = newName + '.' + interfaceNode

        # and rename it in the bonus data tree
        self.bonusDataRename(oldName, newName)

        return


    def bonusDataRename(self, oldName, newName):
        "Rename values in the bonusData field. " \
        "Proper parser wanted here"

        regex = re.compile(r'\b'+oldName+r'\b')

        parameters = self.root.findall('./parameter')
        for parameter in parameters:
            #print parameter.attrib['name']
            if (parameter.attrib['name'] == 'bonusData'):
                bonusData = parameter.text
                #print bonusData
                parameter.text = regex.sub(newName, bonusData)
            #
        return
    #
    # def bonusDataRemove(oldName):
    #     "Remove a block from the bonusData field. " \
    #     "A parser would be such fun..."
    #
    #     stripParens = re.compile(r'(\w+)\s+(\S+)\s+\{(.+)\}')
    #
    #     parameters = self.root.findall('./parameter')
    #     for parameter in parameters:
    #         #print parameter.attrib['name']
    #         if (parameter.attrib['name'] == 'bonusData'):
    #             bonusData = parameter.text
    #             m = stripParens.search(bonusData)
    #             print m #.group(1)

    def bonusDataStrip(self):
        "Remove the bonusData block completely"

        parameters = self.root.findall('./parameter')
        for parameter in parameters:
            #print parameter.attrib['name']
            if (parameter.attrib['name'] == 'bonusData'):
                bonusData = parameter.text
                self.root.remove(parameter)
                #print bonusData
                #parameter.text = regex.sub(newName, bonusData)

        return



    def writeQsys(self, filename):
        "Output a Qsys project to a file"

        f = open(filename, 'w')
        self.tree.write(f, encoding='UTF-8', xml_declaration=True)
        f.close()
        return


def qsys_test():

    q = Qsys('peripherals.qsys')
    q.deleteConnection('MTL_Framebuffer_Flash_0.stream_out', 'displayFeed.in')
    q.deleteComponent('tse_mac')
    q.renameComponent('tse_mac1', 'cheese')
    q.deleteComponent('Switches')
    q.deleteConduit('LEDs', 'external_connection')
    q.bonusDataRename('element', 'moo')
    #bonusDataRemove(root, 'foo')
    q.bonusDataStrip()

    q.writeQsys('output.qsys')

    return True


if __name__ == '__main__':
    qsys_test()

