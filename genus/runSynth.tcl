# Setting the vars/folder to be used throughout flow
set RUN_NAME v1
set OUT_FOLDER /ubc/ece/home/ugrads/a/aolear01/CPEN402/lab3/$RUN_NAME/syn/output
set SOURCE_FOLDER /ubc/ece/home/ugrads/a/aolear01/CPEN402/lab3/$RUN_NAME

set LIB_FOLDER /ubc/ece/data/cmc2/kits/GPDK45/gsclib045_all_v4.4/gsclib045/timing
set TOP_LEVEL mac_accel 

# 1) Setting the library search path
set_db lib_search_path [concat [get_db lib_search_path] $SOURCE_FOLDER $LIB_FOLDER ]
set_db library "slow_vdd1v0_basicCells.lib"
# Here: get_db libraries -> "library:default_emulate_libset_max/slow_vdd1v0" here.
# Here: report_units -> LIBRARY                slow_vdd1v0; Time_unit              :1000ps ...

# 2) Reading the verilog codes
read_hdl -sv ./${TOP_LEVEL}.sv 
elaborate
check_design -unresolved  
# Here: get_db current_design -> should show :$TOP_LEVEL

# 3) Read timing constraints
source ${TOP_LEVEL}_constraints.tcl 
#retime -prepare
#retime -min_delay

# 4) synthesis of the design
synthesize -to_generic -effort medium

synthesize -to_mapped -effort medium -no_incr

synthesize -to_mapped -effort medium -incr

insert_tiehilo_cells
# Here:   report_timing -lint -> will show potential issues in the timing constraints

# 5) Report specs and save 
report_area > ./reports/${TOP_LEVEL}_${RUN_NAME}_area.rpt 
report_gates > ./reports/${TOP_LEVEL}_${RUN_NAME}_gates.rpt   
report_timing > ./reports/${TOP_LEVEL}_${RUN_NAME}_timing.rpt 
report_power > ./reports/${TOP_LEVEL}_${RUN_NAME}_power.rpt
report_qor > ./reports/${TOP_LEVEL}_${RUN_NAME}_qor.rpt

write_hdl -mapped > ./outputs/${TOP_LEVEL}_${RUN_NAME}_map.sv 
write_sdc  > ./outputs/${TOP_LEVEL}_${RUN_NAME}_map.sdc 
write_sdf > ./outputs/${TOP_LEVEL}_${RUN_NAME}_map.sdf

write_db -to ./chkpts/${TOP_LEVEL}_synth_${RUN_NAME}.dat
# Here: report_qor -> would show summarized results for the synthesis
# Here: gui_show -> Right-click the top design on the left column to see the schematic on gui
