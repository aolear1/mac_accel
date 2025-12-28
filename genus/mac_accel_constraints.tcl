set clk_pin CLK 
set rstn_pin RST_N 

set clk_period 2.0
set eighths [ expr $clk_period / 8.0 ]
set sixteenths [ expr $clk_period / 16.0 ] 

set inputs_no_clk_rstn [remove_from_collection [all_inputs] [get_ports "$clk_pin $rstn_pin"]]

create_clock [get_ports $clk_pin] -name $clk_pin -period $clk_period
create_clock -period $clk_period -name io_virtual_clk

set_clock_latency $eighths [get_clocks $clk_pin]
set_clock_uncertainty $eighths [get_clocks $clk_pin]

set_clock_latency $eighths [get_clocks io_virtual_clk]

set_driving_cell -lib_cell DFFX1 -input_transition_rise [expr 1 * $eighths] -input_transition_fall [expr 1 * $eighths] $inputs_no_clk_rstn
set_load [expr [load_of [get_lib_pins */NAND2X4/A]] * 4] [all_outputs]
set_max_fanout 4 $inputs_no_clk_rstn


# constraints for input -> flop, flop -> output
set_input_delay -max [expr 2.0 * $eighths  ] -clock io_virtual_clk -add_delay $inputs_no_clk_rstn
set_output_delay -max [ expr 6.0 * $eighths ] -clock io_virtual_clk -add_delay [all_outputs]


