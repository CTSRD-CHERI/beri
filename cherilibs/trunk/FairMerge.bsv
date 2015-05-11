/*-
 * Copyright (c) 2012 Simon W. Moore
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 *
 ****************************************************************************/


/*****************************************************************************
 FairMerge
 =========
 Simon Moore
 
 FairMerge
 ---------
 Generic package which provides "count" source "put" interfaces and merges
 these streams to one "get" interface.  Has a one element FIFO on each
 source input which introduces one cycle of latency.

 FairMergeTagged
 ---------------
 As above but tags the output with the input port number.
 
 FairSharedServer
 ----------------
 Merges multiple server interfaces down to one client.  Client responses
 are sent back to the corresponding server interface.  This can be used
 to fairly share some server module resource.

 FairMergeArbiter
 ----------------
 Arbiter (varient of Bluespec Arbiter library) used by FairMerge and
 FairMergeTagged.
 
 Version 1: Sept 2009
 Version 2: Oct 2009
   - fixed two bugs:
     1. If one source never sent any data then the system deadlocked.
     2. The FairMerge was unfair if the output was delayed by an amount
        that was not a multiple number of cycles of the number of inputs.
        This was fixed by creating FairMergeArbiter (based on Bluespec's
        arbiter library) which has a explicite "grant_consumed" method
        which guarantees that the next arbitration decision will not be
        made until the grant has been consumed (e.g. the FairMerge/
        FairMergeTagged unit's "get" method has completed).        
 Version 3: Nov 2009
   - added lockable version of the FairMergeServer and tested with
     FairMergeBridge which preserves the Avalon arbiterlock property
 Version 4: February 2010
   - tidied up the arbiter
*****************************************************************************/

package FairMerge;

import GetPut::*;
import Connectable::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;


interface FairMergeIfc#(numeric type count, type dataT);
   interface Vector#(count, Put#(dataT)) sources;
   interface Get#(dataT) sink;
endinterface


module mkFairMerge(FairMergeIfc#(count,dataT)) provisos(Bits#(dataT,dataT_width));
   let icount = valueOf(count);
   FairMergeArbiterIfc#(count) arbiter <- mkFairMergeArbiter;
   // data ports with ungarded dequeues
   Vector#(count, FIFOF#(dataT)) dataport <- replicateM(mkGLFIFOF(False,True));
   RWire#(TaggedDataT#(dataT, UInt#(TLog#(count)))) sink_rw <- mkRWire;
   
   for(Integer j=0; j<icount; j=j+1)
      rule send_requests (dataport[j].notEmpty);
	 arbiter.clients[j].request;
      endrule

   for(Integer j=0; j<icount; j=j+1)
      rule grant_one ((dataport[j].notEmpty) && (arbiter.grant_id==fromInteger(j)));
	 sink_rw.wset(TaggedDataT{d:dataport[j].first, p: fromInteger(j)});
      endrule
	 
   // create vector of source interfaces
   Vector#(count, Put#(dataT)) sources_vector = newVector;
   for(Integer j=0; j<icount; j=j+1)
      sources_vector[j] = toPut(dataport[j]);
   
   interface sources = sources_vector;

   // create sink interface	
   interface Get sink;
      method ActionValue#(dataT) get if (isValid(sink_rw.wget));
	 let s = fromMaybe(?,sink_rw.wget);
	 // notes on deq:
	 //  1. only dequeue when "get" is successful
	 //  2. will only attempt to deq if data from the corresponding fifo
	 //     was sent on sink_rw
	 //  3. deq has to be ungarded otherwise this will only fire
	 //     if every queue is ready to deq
	 dataport[s.p].deq;
	 arbiter.grant_consumed(False);
	 return s.d;
      endmethod
   endinterface
      
endmodule


/*****************************************************************************
 FairMergeTagged
  - same as FairMerge but the Get interface has the source port number tagged
 *****************************************************************************/

typedef struct { dataT d; portT p; }
   TaggedDataT#(type dataT, type portT) deriving(Bits);

interface FairMergeTaggedIfc#(numeric type count, type dataT);
   interface Vector#(count, Put#(dataT)) sources;
   interface Get#(TaggedDataT#(dataT, UInt#(TLog#(count)))) sink;
endinterface


module mkFairMergeTagged(FairMergeTaggedIfc#(count,dataT)) provisos(Bits#(dataT,dataT_width));
   let icount = valueOf(count);
   
   FairMergeArbiterIfc#(count) arbiter <- mkFairMergeArbiter;
   Vector#(count, FIFOF#(dataT)) dataport <- replicateM(mkGLFIFOF(False,True));
   RWire#(TaggedDataT#(dataT, UInt#(TLog#(count)))) sink_rw <- mkRWire;
   
   for(Integer j=0; j<icount; j=j+1)
      rule send_requests (dataport[j].notEmpty);
	 arbiter.clients[j].request;
      endrule

   for(Integer j=0; j<icount; j=j+1)
      rule grant_one ((dataport[j].notEmpty) && (arbiter.grant_id==fromInteger(j)));
	 sink_rw.wset(TaggedDataT{d:dataport[j].first, p: fromInteger(j)});
      endrule
	 
   // create vector of source interfaces
   Vector#(count, Put#(dataT)) sources_vector = newVector;
   for(Integer j=0; j<icount; j=j+1)
      sources_vector[j] = toPut(dataport[j]);
   
   interface sources = sources_vector;

   // create sink interface
   interface Get sink;
      method ActionValue#(TaggedDataT#(dataT, UInt#(TLog#(count)))) get if (isValid(sink_rw.wget));
	 let s = fromMaybe(?,sink_rw.wget);
	 // notes on deq:
	 //  1. only dequeue when "get" is successful
	 //  2. will only attempt to deq if data from the corresponding fifo
	 //     was sent on sink_rw
	 //  3. deq has to be ungarded otherwise this will only fire
	 //     if every queue is ready to deq
	 dataport[s.p].deq;
	 arbiter.grant_consumed(False);
	 return s;
      endmethod
   endinterface
endmodule

/*****************************************************************************
 Lockable Version of FairMergeTagged
 - i.e. there is a "lock" signal to hold arbitration state
 *****************************************************************************/

typedef struct{ dataT d; Bool locked; } LockableT#(type dataT) deriving(Bits);
typedef struct { dataT d; portT p; Bool locked; }
   TaggedLockableDataT#(type dataT, type portT) deriving(Bits);


interface LockableMergeTaggedIfc#(numeric type count, type dataT);
   interface Vector#(count, Put#(LockableT#(dataT))) sources;
   interface Get#(TaggedLockableDataT#(dataT, UInt#(TLog#(count)))) sink;
endinterface


module mkLockableMergeTagged(LockableMergeTaggedIfc#(count,dataT)) provisos(Bits#(dataT,dataT_width));
   let icount = valueOf(count);
   
   FairMergeArbiterIfc#(count) arbiter <- mkFairMergeArbiter;
   Vector#(count, FIFOF#(LockableT#(dataT))) dataport <- replicateM(mkGLFIFOF(False,True));
   RWire#(TaggedLockableDataT#(dataT, UInt#(TLog#(count)))) sink_rw <- mkRWire;
   
   for(Integer j=0; j<icount; j=j+1)
      rule send_requests (dataport[j].notEmpty);
	 arbiter.clients[j].request;
      endrule

   for(Integer j=0; j<icount; j=j+1)
      rule grant_one ((dataport[j].notEmpty) && (arbiter.grant_id==fromInteger(j)));
	 sink_rw.wset(TaggedLockableDataT{d:dataport[j].first.d, locked:dataport[j].first.locked, p: fromInteger(j)});
      endrule
	 
   // create vector of source interfaces
   Vector#(count, Put#(LockableT#(dataT))) sources_vector = newVector;
   for(Integer j=0; j<icount; j=j+1)
      sources_vector[j] = toPut(dataport[j]);
   
   interface sources = sources_vector;

   // create sink interface
   interface Get sink;
      method ActionValue#(TaggedLockableDataT#(dataT, UInt#(TLog#(count)))) get if (isValid(sink_rw.wget));
	 let s = fromMaybe(?,sink_rw.wget);
	 // notes on deq:
	 //  1. only dequeue when "get" is successful
	 //  2. will only attempt to deq if data from the corresponding fifo
	 //     was sent on sink_rw
	 //  3. deq has to be ungarded otherwise this will only fire
	 //     if every queue is ready to deq
	 dataport[s.p].deq;
	 arbiter.grant_consumed(s.locked);
	 return s;
      endmethod
   endinterface
endmodule


/*****************************************************************************
 FargeSharedServer
 - merges requests from N clients and sends responses back to the appropriate
   clients
 *****************************************************************************/

interface FairSharedServerIfc#(numeric type count, type requestT, type responseT);
   interface Vector#(count, Server#(requestT,responseT)) sources;
   interface Client#(requestT,responseT) sink;
endinterface


/*****************************************************************************
 Connectivity from sources to sink and back: 
 sources[j].request (put) -> merge.sources[j].put
 merge.sink.get -> sink.request (get)
 sink.response (put) -> pushed_responses_vector (put) = connectable = responses_vector(get) ->sources[j].response (get)
 ****************************************************************************/ 

module mkFairSharedServer(FairSharedServerIfc#(count,requestT,responseT))
   provisos(Bits#(requestT,requestT_width),Bits#(responseT,responseT_width));
   
   FairMergeTaggedIfc#(count,requestT) merge <- mkFairMergeTagged;
   FIFO#(UInt#(TLog#(count))) tags <- mkSizedFIFO(4); // 4 is probably overkill
   
   // connect incoming requests from sources to the fair merge tagged unit
   Vector#(count, Server#(requestT,responseT)) sources_vector = newVector;
   Vector#(count, FIFOF#(responseT)) responses_vector <- replicateM(mkFIFOF1);
   for(Integer j=0; j<valueOf(count); j=j+1)
      sources_vector[j] = Server{request: merge.sources[j], response: toGet(responses_vector[j])};
   
/* the following does the same as the 2 lines above, just more verbose and with diagnostics
   for(Integer j=0; j<valueOf(count); j=j+1)
      sources_vector[j] = (interface Server#(requestT,responseT);
			      interface Put request;
				 method Action put(d);
				    $display("  %04t: shared server pushing val on channel %1d to merge unit",$time,j);
				    merge.sources[j].put(d);
				 endmethod
			      endinterface
			      interface Get response;
				 method ActionValue#(responseT) get;
				    $display("  %04t: shared server received val on channel %1d from server buffer queue",$time,j);
				    responses_vector[j].deq;
				    return responses_vector[j].first;
				 endmethod
			      endinterface
			   endinterface);
*/
   interface sources = sources_vector;
   
   interface Client sink;
      // connect output of merge to output of sink
      interface Get request;
	 method ActionValue#(requestT) get;
	    let m <- merge.sink.get;
	    tags.enq(m.p);
	    // $display("  %04t: merge sink consumed & server sending request for port %1d",$time,m.p);
	    return m.d;
	 endmethod
      endinterface
      // connect input of sink to appropriate server
      interface Put response;
	 method Action put(r);
	    let tag=tags.first;
	    tags.deq;
	    // $display("  %04t: server response: dequeued tag=%1d",$time,tag);
	    responses_vector[tag].enq(r);
	 endmethod
      endinterface
   endinterface
endmodule



/*****************************************************************************
 LockableSharedServer
 - like FairSharedServer but allows the arbitration to be locked (held onto)
 *****************************************************************************/

interface LockableSharedServerIfc#(numeric type count, type requestT, type responseT);
   interface Vector#(count, Server#(LockableT#(requestT),responseT)) sources;
   interface Client#(LockableT#(requestT),responseT) sink;
endinterface


module mkLockableSharedServer(LockableSharedServerIfc#(count,requestT,responseT))
   provisos(Bits#(requestT,requestT_width),Bits#(responseT,responseT_width));
   
   LockableMergeTaggedIfc#(count,requestT) merge <- mkLockableMergeTagged;
   FIFO#(UInt#(TLog#(count))) tags <- mkSizedFIFO(4); // 4 is probably overkill
   
   // connect incoming requests from sources to the fair merge tagged unit
   Vector#(count, Server#(LockableT#(requestT),responseT)) sources_vector = newVector;
   Vector#(count, FIFOF#(responseT)) responses_vector <- replicateM(mkFIFOF1);
   for(Integer j=0; j<valueOf(count); j=j+1)
      sources_vector[j] = Server{request: merge.sources[j], response: toGet(responses_vector[j])};
   
   interface sources = sources_vector;
   
   interface Client sink;
      // connect output of merge to output of sink
      interface Get request;
	 method ActionValue#(LockableT#(requestT)) get;
	    let m <- merge.sink.get;
	    tags.enq(m.p);
	    $display("     %05t: merge sink consumed & server sending request for port %1d",$time,m.p);
	    return LockableT{d:m.d, locked:m.locked};
	 endmethod
      endinterface
      // connect input of sink to appropriate server
      interface Put response;
	 method Action put(r);
	    let tag=tags.first;
	    tags.deq;
	    $display("     %05t: server response: dequeued tag=%1d",$time,tag);
	    responses_vector[tag].enq(r);
	 endmethod
      endinterface
   endinterface
endmodule



/////////////////////////////////////////////////////////////////////////////
// FairMergeArbiter
// Derived from Bluespec's Arbiter library
//  - adds "grant_consumed" as a method to rotate priorities (if lock=0)
//    or hold the priority (if lock=1)

interface FairMergeArbiterClientIfc;
   method Action request();
   method Bool grant();
endinterface

interface FairMergeArbiterIfc#(numeric type count);
   interface Vector#(count, FairMergeArbiterClientIfc) clients;
   method    Bit#(TLog#(count)) grant_id;
   method    Action grant_consumed(Bool locked);
endinterface

module mkFairMergeArbiter(FairMergeArbiterIfc#(count));
   let icount = valueOf(count);

   Vector#(count, Bool) init_value = replicate(False);
   init_value[0] = True;
   Reg#(Vector#(count, Bool))  priority_vector     <- mkReg(init_value);
   
   Wire#(Vector#(count, Bool)) grant_vector        <- mkBypassWire;
   Wire#(Bit#(TLog#(count)))   grant_id_wire       <- mkBypassWire;
   Vector#(count, PulseWire)   request_vector      <- replicateM(mkPulseWire);
   Reg#(Bool)                  lock_arbiter        <- mkReg(False);
   
   rule every (True);
      // calculate the grant_vector
      Vector#(count, Bool) grant_vector_local = replicate(False);
      Bit#(TLog#(count))   grant_id_local     = 0;
      
      Bool found = True;
      
      for (Integer x = 0; x < (2 * icount); x = x + 1)
	 begin
	    Integer y = (x % icount);
	    if (priority_vector[y]) found = False;
	    let granted = (lock_arbiter ? priority_vector[y] : !found) && request_vector[y];
	    if(granted)
	       begin
		  grant_vector_local[y] = True;
		  grant_id_local        = fromInteger(y);
		  found = True;
	       end
	 end
      
      grant_vector  <= grant_vector_local;
      grant_id_wire <= grant_id_local;
      
//       $display("(%5d)  priority vector: %4b", $time, priority_vector);
//       $display("(%5d)   request vector: %4b", $time, request_vector);
//       $display("(%5d)     Grant vector: %4b (lock_arbiter=%s)", $time, grant_vector_local,lock_arbiter ? "True":"False");
//       $display("(%5d)     Grant id:     %4d", $time, grant_id_local);
   endrule
   
   // Now create the vector of interfaces
   Vector#(count, FairMergeArbiterClientIfc) client_vector = newVector;

   for (Integer x = 0; x < icount; x = x + 1)
      client_vector[x] = (interface FairMergeArbiterClientIfc;
			     method Action request();
				request_vector[x].send();
			     endmethod
			     method grant ();
				return grant_vector[x];
			     endmethod
			  endinterface);
			   
   interface clients = client_vector;
   method    grant_id = grant_id_wire;
   method    Action grant_consumed(Bool locked);
      // rotate priorities when grant has been consumed and not(locked)
      if(pack(grant_vector)!=0)
	 priority_vector <= locked ? grant_vector : rotateR(grant_vector);
      lock_arbiter <= locked;
   endmethod
   
endmodule


endpackage
