package require -exact qsys 13.1
set_module_property DESCRIPTION "JTAG UART with adjustable Atlantic parameters including Instance ID"
set_module_property NAME adjustable_jtag_uart
set_module_property VERSION 13.1
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property GROUP Cheri_IO
set_module_property AUTHOR "Altera code patched by Theo Markettos"
set_module_property DISPLAY_NAME "Adjustable JTAG UART"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property ANALYZE_HDL AUTO
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL adjustable_jtag_uart
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
add_fileset_file adjustable_jtag_uart.v VERILOG PATH adjustable_jtag_uart.v TOP_LEVEL_FILE

add_parameter INSTANCE_ID INTEGER 0 "JTAG Atlantic instance ID as exposed to nios2-terminal"
set_parameter_property INSTANCE_ID DEFAULT_VALUE 0
set_parameter_property INSTANCE_ID DISPLAY_NAME INSTANCE_ID
set_parameter_property INSTANCE_ID TYPE INTEGER
set_parameter_property INSTANCE_ID UNITS None
set_parameter_property INSTANCE_ID DESCRIPTION "JTAG Atlantic instance ID as exposed to nios2-terminal"
set_parameter_property INSTANCE_ID HDL_PARAMETER true
add_parameter LOG2_RXFIFO_DEPTH INTEGER 9 "JTAG Atlantic receive FIFO depth"
set_parameter_property LOG2_RXFIFO_DEPTH DEFAULT_VALUE 9
set_parameter_property LOG2_RXFIFO_DEPTH DISPLAY_NAME LOG2_RXFIFO_DEPTH
set_parameter_property LOG2_RXFIFO_DEPTH TYPE INTEGER
set_parameter_property LOG2_RXFIFO_DEPTH UNITS None
set_parameter_property LOG2_RXFIFO_DEPTH DESCRIPTION "JTAG Atlantic receive FIFO depth"
set_parameter_property LOG2_RXFIFO_DEPTH HDL_PARAMETER true
add_parameter LOG2_TXFIFO_DEPTH INTEGER 12 "JTAG Atlantic receive FIFO depth"
set_parameter_property LOG2_TXFIFO_DEPTH DEFAULT_VALUE 12
set_parameter_property LOG2_TXFIFO_DEPTH DISPLAY_NAME LOG2_TXFIFO_DEPTH
set_parameter_property LOG2_TXFIFO_DEPTH TYPE INTEGER
set_parameter_property LOG2_TXFIFO_DEPTH UNITS None
set_parameter_property LOG2_TXFIFO_DEPTH DESCRIPTION "JTAG Atlantic receive FIFO depth"
set_parameter_property LOG2_TXFIFO_DEPTH HDL_PARAMETER true
add_parameter SLD_AUTO_INSTANCE_INDEX STRING YES "YES = assign instance ID automatically, NO = set by INSTANCE_ID"
set_parameter_property SLD_AUTO_INSTANCE_INDEX DEFAULT_VALUE YES
set_parameter_property SLD_AUTO_INSTANCE_INDEX DISPLAY_NAME SLD_AUTO_INSTANCE_INDEX
set_parameter_property SLD_AUTO_INSTANCE_INDEX WIDTH ""
set_parameter_property SLD_AUTO_INSTANCE_INDEX TYPE STRING
set_parameter_property SLD_AUTO_INSTANCE_INDEX UNITS None
set_parameter_property SLD_AUTO_INSTANCE_INDEX DESCRIPTION "YES = assign instance ID automatically, NO = set by INSTANCE_ID"
set_parameter_property SLD_AUTO_INSTANCE_INDEX HDL_PARAMETER true

add_interface av avalon end
set_interface_property av addressUnits WORDS
set_interface_property av associatedClock clock
set_interface_property av associatedReset reset_sink
set_interface_property av bitsPerSymbol 8
set_interface_property av burstOnBurstBoundariesOnly false
set_interface_property av burstcountUnits WORDS
set_interface_property av explicitAddressSpan 0
set_interface_property av holdTime 0
set_interface_property av linewrapBursts false
set_interface_property av maximumPendingReadTransactions 0
set_interface_property av readLatency 0
set_interface_property av readWaitTime 1
set_interface_property av setupTime 0
set_interface_property av timingUnits Cycles
set_interface_property av writeWaitTime 0
set_interface_property av ENABLED true
set_interface_property av EXPORT_OF ""
set_interface_property av PORT_NAME_MAP ""
set_interface_property av CMSIS_SVD_VARIABLES ""
set_interface_property av SVD_ADDRESS_GROUP ""

add_interface_port av av_address address Input 1
add_interface_port av av_chipselect chipselect Input 1
add_interface_port av av_read_n read_n Input 1
add_interface_port av av_write_n write_n Input 1
add_interface_port av av_writedata writedata Input 32
add_interface_port av av_waitrequest waitrequest Output 1
add_interface_port av dataavailable dataavailable Output 1
add_interface_port av readyfordata readyfordata Output 1
add_interface_port av av_readdata readdata Output 32
set_interface_assignment av embeddedsw.configuration.isFlash 0
set_interface_assignment av embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment av embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment av embeddedsw.configuration.isPrintableDevice 0

add_interface clock clock end
set_interface_property clock clockRate 0
set_interface_property clock ENABLED true
set_interface_property clock EXPORT_OF ""
set_interface_property clock PORT_NAME_MAP ""
set_interface_property clock CMSIS_SVD_VARIABLES ""
set_interface_property clock SVD_ADDRESS_GROUP ""

add_interface_port clock clk clk Input 1

add_interface reset_sink reset end
set_interface_property reset_sink associatedClock clock
set_interface_property reset_sink synchronousEdges DEASSERT
set_interface_property reset_sink ENABLED true
set_interface_property reset_sink EXPORT_OF ""
set_interface_property reset_sink PORT_NAME_MAP ""
set_interface_property reset_sink CMSIS_SVD_VARIABLES ""
set_interface_property reset_sink SVD_ADDRESS_GROUP ""

add_interface_port reset_sink rst_n reset_n Input 1

add_interface interrupt_sender interrupt end
set_interface_property interrupt_sender associatedAddressablePoint ""
set_interface_property interrupt_sender associatedClock clock
set_interface_property interrupt_sender ENABLED true
set_interface_property interrupt_sender EXPORT_OF ""
set_interface_property interrupt_sender PORT_NAME_MAP ""
set_interface_property interrupt_sender CMSIS_SVD_VARIABLES ""
set_interface_property interrupt_sender SVD_ADDRESS_GROUP ""

add_interface_port interrupt_sender av_irq irq Output 1

