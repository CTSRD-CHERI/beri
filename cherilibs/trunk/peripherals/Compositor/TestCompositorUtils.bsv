/*-
 * Copyright (c) 2013 Philip Withnall
 * All rights reserved.
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

package TestCompositorUtils;

import CompositorUtils::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositorUtils ();
	Stmt testSeq = seq
		/* Test arithmetic on PixelComponents. */
		/* TODO: Duplicate these tests for PixelComponentPMs. */
		/* Addition. */
		startTest ("Addition of PixelComponents");
		assertEqual (PixelComponent { v: 0 } + PixelComponent { v: 5 }, PixelComponent { v: 5 });
		assertEqual (PixelComponent { v: 0 } + PixelComponent { v: 255 }, PixelComponent { v: 255 });
		assertEqual (PixelComponent { v: 100 } + PixelComponent { v: 170 }, PixelComponent { v: 255 }); /* saturation! */
		assertEqual (PixelComponent { v: 0 } + PixelComponent { v: 0 }, PixelComponent { v: 0 });
		finishTest ();

		/* Subtraction. */
		startTest ("Subtraction of PixelComponents");
		assertEqual (PixelComponent { v: 0 } - PixelComponent { v: 0 }, PixelComponent { v: 0 });
		assertEqual (PixelComponent { v: 0 } - PixelComponent { v: 10 }, PixelComponent { v: 0 });
		assertEqual (PixelComponent { v: 255 } - PixelComponent { v: 255 }, PixelComponent { v: 0 });
		assertEqual (PixelComponent { v: 100 } - PixelComponent { v: 50 }, PixelComponent { v: 50 });
		assertEqual (PixelComponent { v: 50 } - PixelComponent { v: 0 }, PixelComponent { v: 50 });
		finishTest ();

		/* Multiplication. */
		startTest ("Multiplication of PixelComponents");
		assertEqual (PixelComponent { v: 255 } * PixelComponent { v: 0 }, PixelComponent { v: 0 });
		assertEqual (PixelComponent { v: 0 } * PixelComponent { v: 0 }, PixelComponent { v: 0 });
		assertEqual (PixelComponent { v: 255 } * PixelComponent { v: 100 }, PixelComponent { v: 100 });
		assertEqual (PixelComponent { v: 100 } * PixelComponent { v: 100 }, PixelComponent { v: 39 });
		assertEqual (PixelComponent { v: 255 } * PixelComponent { v: 255 }, PixelComponent { v: 255 });
		finishTest ();


		/* Test conversion of integer literals to PixelComponents. */
		/* fromInteger. */
		startTest ("Conversion of integer literals to PixelComponents");
		assertEqual (fromInteger (0), PixelComponent { v: 0 });
		assertEqual (fromInteger (255), PixelComponent { v: 255 });
		assertEqual (fromInteger (100), PixelComponent { v: 100 });
		assertEqual (fromInteger (500), PixelComponent { v: 255 });
		assertEqual (fromInteger (-5), PixelComponent { v: 0 });
		finishTest ();

		/* inLiteralRange. */
		startTest ("Range checking of integer literals for PixelComponents");
		assertEqual (inLiteralRange (PixelComponent { v: 0 }, -5), False);
		assertEqual (inLiteralRange (PixelComponent { v: 0 }, 500), False);
		assertEqual (inLiteralRange (PixelComponent { v: 0 }, 100), True);
		assertEqual (inLiteralRange (PixelComponent { v: 0 }, 0), True);
		assertEqual (inLiteralRange (PixelComponent { v: 0 }, 255), True);
		finishTest ();


		/* Test conversion of real literals to PixelComponents. */
		/* fromReal. */
		startTest ("Conversion of real literals to PixelComponents");
		assertEqual (fromReal (0.0), PixelComponent { v: 0 });
		assertEqual (fromReal (1.0), PixelComponent { v: 255 });
		assertEqual (fromReal (0.392), PixelComponent { v: 99 });
		assertEqual (fromReal (2.0), PixelComponent { v: 255 });
		assertEqual (fromReal (-0.6), PixelComponent { v: 0 });
		finishTest ();


		/* Test conversion between RGB and RGBA pixels. */
		/* rgbaToRgb. */
		startTest ("Conversion of RgbaPixels to RgbPixels");
		assertEqual (rgbaToRgb (RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }), RgbPixel { red: 1.0, green: 1.0, blue: 1.0 });
		assertEqual (rgbaToRgb (RgbaPixel { red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5 }), RgbPixel { red: 0.5, green: 0.5, blue: 0.5 });
		assertEqual (rgbaToRgb (RgbaPixel { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0 }), RgbPixel { red: 0.0, green: 0.0, blue: 0.0 });
		finishTest ();

		/* rgbToRgba. */
		startTest ("Conversion of RgbPixels to RgbaPixels");
		assertEqual (rgbToRgba (RgbPixel { red: 1.0, green: 1.0, blue: 1.0 }), RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 });
		assertEqual (rgbToRgba (RgbPixel { red: 0.0, green: 0.0, blue: 0.0 }), RgbaPixel { red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0 });
		assertEqual (rgbToRgba (RgbPixel { red: 0.5, green: 0.5, blue: 0.5 }), RgbaPixel { red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0 });
		finishTest ();
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositorUtils

endpackage: TestCompositorUtils
