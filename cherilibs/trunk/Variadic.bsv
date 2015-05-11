/*-
 * Copyright (c) 2013 Alex Horsman
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
 */

/*****************************************************************************

Variadic
========

This library provides convenient construction functions which can accept a
variable number of arguments and produce a sequence type containing the
corresponding values. Currently the supported sequence types are List, Vector,
ListN and HList, each of which has a correspondingly named constructor
function, with the first character in lowercase.

For example, if we wish to construct a Vector of Integers containing the
values one to four, we can do so with the "vector" function:

    Vector#(4,Integer) oneToFour = vector(1,2,3,4);

If you receive an error message referring to a typeclass with a name ending
in Builder, for example Variadic::VectorBuilder this most likely means you
have made a type error in your use of one the corresponding function.

The typeclass mechanism used to allow these functions is based on one used
in Haskell, explained here:
http://stackoverflow.com/questions/7828072/how-does-haskell-printf-work

*****************************************************************************/

package Variadic;


import List::*;

export list;
export ListBuilder;


typeclass ListBuilder#(type a, type bldr)
dependencies(bldr determines a);
    function bldr listBuild(List#(a) x);
endtypeclass

instance ListBuilder#(a,List#(a));
    function listBuild = List::reverse;
endinstance

instance ListBuilder#(a,function bldr f(a x))
provisos(ListBuilder#(a,bldr));
    function listBuild(xs,x) = listBuild(List::cons(x,xs));
endinstance

function bldr list provisos(ListBuilder#(a,bldr)) =
    listBuild(Nil);


import Vector::*;

export vector;
export VectorBuilder;


typeclass VectorBuilder#(type n, type a, type bldr)
dependencies(bldr determines (n,a));
    function bldr vecBuild(Vector#(n,a) x);
endtypeclass

instance VectorBuilder#(n,a,Vector#(n,a));
    function vecBuild = Vector::reverse;
endinstance

instance VectorBuilder#(n,a,function bldr f(a x))
provisos(VectorBuilder#(TAdd#(n,1),a,bldr));
    function vecBuild(xs,x) = vecBuild(Vector::cons(x,xs));
endinstance

function bldr vector provisos(VectorBuilder#(0,a,bldr)) =
    vecBuild(Vector::nil);


import ListN::*;

export listN;
export ListNBuilder;


typeclass ListNBuilder#(type n, type a, type bldr)
dependencies(bldr determines (n,a));
    function bldr listNBuild(ListN#(n,a) x);
endtypeclass

instance ListNBuilder#(n,a,ListN#(n,a));
    function listNBuild = ListN::reverse;
endinstance

instance ListNBuilder#(n,a,function bldr f(a x))
provisos(ListNBuilder#(TAdd#(n,1),a,bldr));
    function listNBuild(xs,x) = listNBuild(ListN::cons(x,xs));
endinstance

function bldr listN provisos(ListNBuilder#(0,a,bldr)) =
    listNBuild(ListN::nil);


import HList::*;

export hList;
export HListBuilder;


typeclass HReverse#(type as, type bs)
dependencies(as determines bs);
    function bs hReverse(as x);
endtypeclass

instance HReverse#(HNil,HNil);
    function hReverse = id;
endinstance

instance HReverse#(HCons#(a,as),cs)
provisos(HReverse#(as,bs),HAppend#(bs,HList1#(a),cs));
    function hReverse(xs) = hAppend(hReverse(xs.tl),hList1(xs.hd));
endinstance


typeclass HListBuilder#(type current, type bldr)
dependencies(bldr determines current);
    function bldr hListBuild(current x);
endtypeclass

instance HListBuilder#(as, bs)
provisos(HReverse#(as,bs));
    function hListBuild = hReverse;
endinstance

instance HListBuilder#(as, function bldr f(a x))
provisos(HListBuilder#(HCons#(a,as),bldr));
    function hListBuild(xs,x) = hListBuild(hCons(x,xs));
endinstance

function bldr hList provisos(HListBuilder#(HNil,bldr)) =
    hListBuild(HNil{});


endpackage
