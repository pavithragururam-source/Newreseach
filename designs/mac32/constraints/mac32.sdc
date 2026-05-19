create_clock -name clk -period 1.0 [get_ports clk]

set_input_delay  -clock clk -max 0.3 [all_inputs]
set_input_delay  -clock clk -min 0.0 [all_inputs]
set_output_delay -clock clk -max 0.3 [all_outputs]
set_output_delay -clock clk -min 0.0 [all_outputs]

set_clock_uncertainty -setup 0.05 [get_clocks clk]
set_clock_uncertainty -hold  0.02 [get_clocks clk]

set_driving_cell -lib_cell BUFx2_ASAP7_75t_R -pin Y [all_inputs]
set_load 5 [all_outputs]

set_multicycle_path -setup 2 \
    -from [get_pins mul_r_reg*/Q] -to [get_pins acc_r_reg*/D]
set_multicycle_path -hold  1 \
    -from [get_pins mul_r_reg*/Q] -to [get_pins acc_r_reg*/D]

set_false_path -from [get_ports rst_n]
