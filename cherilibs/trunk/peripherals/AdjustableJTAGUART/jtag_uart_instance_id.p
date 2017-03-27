--- vanilla_jtag_uart/vanilla_jtag_uart.v	2017-01-24 18:32:51.761149001 +0000
+++ vanilla_jtag_uart/vanilla_jtag_uart.v	2017-01-24 18:33:31.441279416 +0000
@@ -343,6 +343,12 @@
                          )
   /* synthesis ALTERA_ATTRIBUTE = "SUPPRESS_DA_RULE_INTERNAL=\"R101,C106,D101,D103\"" */ ;
 
+  /* BERI: expose parameters for instance ID and FIFO depth to the upper level */
+  parameter INSTANCE_ID = 0;
+  parameter LOG2_RXFIFO_DEPTH = 9;
+  parameter LOG2_TXFIFO_DEPTH = 12;
+  parameter SLD_AUTO_INSTANCE_INDEX = "NO";
+
   output           av_irq;
   output  [ 31: 0] av_readdata;
   output           av_waitrequest;
@@ -563,9 +569,9 @@
 //      .t_pause (t_pause)
 //    );
 //
-//  defparam vanilla_jtag_uart_alt_jtag_atlantic.INSTANCE_ID = 0,
-//           vanilla_jtag_uart_alt_jtag_atlantic.LOG2_RXFIFO_DEPTH = 9,
-//           vanilla_jtag_uart_alt_jtag_atlantic.LOG2_TXFIFO_DEPTH = 12,
-//           vanilla_jtag_uart_alt_jtag_atlantic.SLD_AUTO_INSTANCE_INDEX = "YES";
+//  defparam vanilla_jtag_uart_alt_jtag_atlantic.INSTANCE_ID = INSTANCE_ID,
+//           vanilla_jtag_uart_alt_jtag_atlantic.LOG2_RXFIFO_DEPTH = LOG2_RXFIFO_DEPTH,
+//           vanilla_jtag_uart_alt_jtag_atlantic.LOG2_TXFIFO_DEPTH = LOG2_TXFIFO_DEPTH,
+//           vanilla_jtag_uart_alt_jtag_atlantic.SLD_AUTO_INSTANCE_INDEX = SLD_AUTO_INSTANCE_INDEX;
 //
 //  always @(posedge clk or negedge rst_n)
