/*-
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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

DebugModule
===========

This library allows modules to store a table of probe points, which is
propagated up the design hierarchy, without the necessity of explicitly
including it in every module's interface. The intention is that this can be
used to probe values at arbitrary points in the code, and then write debugging
logic at the top level. This avoids the incidental complexity of exposing
values deep in the hierarchy.

Also included are a few simple debugging tools which make use of these
features: A module for creating registers with a corresponding probe point,
and a module for exposing a list of probe points as a Get interface.


Before a module can make use of this library's features, it must declare its
module type as DebugModule. This is done by placing this type in square
brackets after the module keyword:

    module [DebugModule] mkModuleWithDebuggingFeatures(Ifc);

This must also be done for any modules which contain sub-modules which use the
features.

The table itself is an association list of names to signals. To add a probe
point to the table, use the addDebugEntry module. This takes a name for the
probe, along with its value, and adds it to the stored table. For example, you
can probe the value of a register like so:

    Reg#(UInt#(8)) probedReg <- mkReg(0);
    addDebugEntry("probeName",probedReg);

You can then use the corresponding getDebugEntry module to retrieve this value
at any point in the hierarchy after its introduction:

    UInt#(8) probeValue <- getDebugEntry("probeName");

Note that the table can store values of arbitrary bit widths. However, no type
information is preserved for these values. The compiler runtime will generate
an error if you attempt to extract a value to a type of the wrong width, but it
is otherwise the user's responsibility to ensure the correct types are used.

Finally, in order to synthesise a module which makes use of these features you
must convert it back to a native Module, by using runDebug:

    module [Module] mkTopLevelPhysical(TopLevelIfc);
        return runDebug(mkTopLevel);
    endmodule

Or alternatively:

    Module#(TopLevelIfc) mkTopLevelPhysical = runDebug(mkTopLevel);

The latter syntax is equivalent to the former, but may be preferable to
indicate that the module is created by transforming another module, rather than
being a completely new definition.

The runDebug module simply removes the stored table, and returns the
underlying Module. Note that this means the table cannot be carried over
synthesis boundaries. If you need to probe values across these boundaries, you
will have to expose them explicitly as in a typical design. (Future versions
of this library may include tools to simplify this process.)


To simplify some common cases this library also includes a few extra modules.

mkDebugReg: Creates a new register with a corresponding probe entry of the
            given name. There is also mkDebugRegU which takes no initial value.

mkTrace: Takes a list of names and concatenates their corresponding probe
         values, returning them as a Get interface.

*****************************************************************************/

package DebugModule;

import GetPut::*;

import List::*;
import Assoc::*;

import DynamicBits::*;
import ModuleContext::*;


typedef Assoc#(String,DynamicBits) DebugData;

typedef ModuleContext#(DebugData) DebugModule;


module [DebugModule] getDebugEntryDynamic#(String name)(DynamicBits);

    let err = error("Name: " + name + " not found in debug data.");
    let debugData <- getContext();
    return fromMaybe(err,lookup(name,debugData));

endmodule

//Get a single entry, given its name.
module [DebugModule] getDebugEntry#(String name)(dataT)
provisos(Bits#(dataT,dataWidth));

    let dynData <- getDebugEntryDynamic(name);
    return fromDynamic(dynData);

endmodule

//Add a new entry to the table with the specified name.
//If the name already exists, it will replace the existing entry.
module [DebugModule] addDebugEntry#(String name, dataT data)(Empty)
provisos(Bits#(dataT,dataWidth));

    let err = error("Name: " + name + " already exists in debug data.");
    applyToContext(insertWith(err,name,toDynamic(data)));

endmodule



//Create a register, and store its value in the table with the specified name.
module [DebugModule] mkDebugReg#(String name, dataT x)(Reg#(dataT))
provisos(Bits#(dataT,dataWidth));

    Reg#(dataT) store <- mkReg(x);
    addDebugEntry(name,store);
    return asReg(store);

endmodule

module [DebugModule] mkDebugRegU#(String name)(Reg#(dataT))
provisos(Bits#(dataT,dataWidth));

    Reg#(dataT) store <- mkRegU;
    addDebugEntry(name,store);
    return asReg(store);

endmodule

module [DebugModule] mkDebugEvent#(String name)(Action);

    PulseWire pw <- mkPulseWire;
    addDebugEntry(name,pw);
    return pw.send;

endmodule


module [DebugModule] debugRule#(String name, Bool cond, Action body)(Empty);

    addDebugEntry(name + "_condition",cond);

    Action fireEvent <- mkDebugEvent(name + "_fires");
    rule debug (cond);
        body;
        fireEvent;
    endrule

endmodule


function String integerToString(Integer i) =
    case (i) matches
        0 : return "0";
        1 : return "1";
        2 : return "2";
        3 : return "3";
        4 : return "4";
        5 : return "5";
        6 : return "6";
        7 : return "7";
        8 : return "8";
        9 : return "9";
        .x &&& (x < 0) :
            return "-" + integerToString(abs(x));
        .x &&& (x >= 10) :
            return integerToString(i/10) + integerToString(i%10);
    endcase;


//Takes a list of names and returns a Get interface, which outputs their values
//concatenated. The type used for output must be the correct width.
module [DebugModule] mkTrace#(List#(String) names)(Get#(dataT))
provisos(Bits#(dataT,dataWidth));

    let entries <- mapM(getDebugEntryDynamic,names);

    Handle traceInfo <- openFile("trace_info", WriteMode);

    function writePair(name,entry) =
        hPutStrLn(traceInfo,name + "," + integerToString(length(entry)));

    hPutStrLn(traceInfo,integerToString((valueof(dataWidth)+7)/8));
    zipWithM(writePair,names,entries);

    hFlush(traceInfo);
    hClose(traceInfo);


    method ActionValue#(dataT) get();
        return fromDynamic(concat(entries));
    endmethod

endmodule


typedef List#(Tuple2#(String,Integer)) BitFormat;


function DynamicBits packFormat(BitFormat fmt, DebugData debug);
    let err = error("Packing failed");
    return case (fmt) matches
        tagged Nil : return Nil;
        tagged Cons { _1: { .name, .size }, _2: .rest }:
            return append(
                fromMaybe(err,lookup(name,debug)),
                packFormat(rest,debug)
            );
    endcase;
endfunction

function DebugData unpackFormat(BitFormat fmt, DynamicBits bits) =
    case (fmt) matches
        tagged Nil : return Nil;
        tagged Cons { _1: { .name, .size }, _2: .rest }:
            return cons(
                tuple2(      name,take(size,bits)),
                unpackFormat(rest,drop(size,bits))
            );
    endcase;


module [DebugModule] withNamespace#(String namespace, DebugModule#(ifc) mod)(ifc);

    match { .debug, .mainIfc } <- liftModule(runWithContext(Nil,mod));

    function wrap(entry);
        match { .name, .val } = entry;
        return tuple2(namespace + "." + name,val);
    endfunction

    applyToContext(merge(map(wrap,debug)));

    return mainIfc;

endmodule



typeclass DebugSynth#(type ifc, numeric type debugWidth)
dependencies(ifc determines debugWidth);
    function BitFormat debugSynthFormat(ifc x);
endtypeclass


module [Module] mkSynthBoundary#(DebugModule#(ifc) mod)(Tuple2#(Bit#(debugWidth),ifc))
provisos(DebugSynth#(ifc,debugWidth));

    match { .debug, .mainIfc } <- runWithContext(Nil,mod);

    BitFormat fmt = debugSynthFormat(ifc'(?));
    Bit#(debugWidth) bits = fromDynamic(packFormat(fmt,debug));

    return tuple2(bits,mainIfc);

endmodule

module [DebugModule] unSynthBoundary#(
    Module#(Tuple2#(Bit#(debugWidth),ifc)) mod)(ifc)
provisos(DebugSynth#(ifc,debugWidth));

    match { .bits, .mainIfc } <- liftModule(mod);

    BitFormat fmt = debugSynthFormat(ifc'(?));
    DebugData debug = unpackFormat(fmt,toDynamic(bits));

    applyToContext(merge(debug));
    return mainIfc;

endmodule


//Strip the debug table, so that a module can be synthesised.
module [Module] runDebug#(DebugModule#(ifc) mod)(ifc);

    let x <- runWithContext(Nil,mod);
    return tpl_2(x);

endmodule


endpackage
