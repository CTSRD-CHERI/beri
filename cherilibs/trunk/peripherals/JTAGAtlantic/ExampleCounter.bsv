import AlteraJtagUart::*;
import Connectable::*;
import FIFOF::*;

(* synthesize *)
module mkExampleCounter(Empty);
    AlteraJtagUart uart <- mkAlteraJtagUart(6, 6, 0, 0);
	Reg#(JtagWord) counter <- mkReg(0);

	rule rx_discard;
		let data <- uart.rx.get;
	endrule
	rule tx_counter;
		uart.tx.put(counter);
		counter <= counter + 1;
	endrule
endmodule
