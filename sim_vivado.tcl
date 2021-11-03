# Copyright TU Wien
# Licensed under the ISC license, see LICENSE.txt for details
# SPDX-License-Identifier: ISC


################################################################################
# Create Project and Run Simulation
################################################################################

if {$argc < 5} {
    puts "usage: sim.tcl SIM_DIR CORE_DIR PARAMS LOG_FILE PROG_PATHS_LIST \[SYMBOLS ...\]"
    exit 2
}

# get command line arguments
set sim_dir [lindex $argv 0]
set core_dir  [lindex $argv 1]
set params_var "[lindex $argv 2]"
set log_file_path [lindex $argv 3]
set prog_paths_var "PROG_PATHS_LIST=\"[lindex $argv 4]\""

# create project
set _xil_proj_name_ "cv32e40x_sim"
create_project -part xc7a200tfbg484-2 ${_xil_proj_name_} ${_xil_proj_name_}
set proj_dir [get_property directory [current_project]]

# set project properties
set obj [current_project]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "dsa.accelerator_binary_content" -value "bitstream" -objects $obj
set_property -name "dsa.accelerator_binary_format" -value "xclbin2" -objects $obj
set_property -name "dsa.description" -value "Vivado generated DSA" -objects $obj
set_property -name "dsa.dr_bd_base_address" -value "0" -objects $obj
set_property -name "dsa.emu_dir" -value "emu" -objects $obj
set_property -name "dsa.flash_interface_type" -value "bpix16" -objects $obj
set_property -name "dsa.flash_offset_address" -value "0" -objects $obj
set_property -name "dsa.flash_size" -value "1024" -objects $obj
set_property -name "dsa.host_architecture" -value "x86_64" -objects $obj
set_property -name "dsa.host_interface" -value "pcie" -objects $obj
set_property -name "dsa.platform_state" -value "pre_synth" -objects $obj
set_property -name "dsa.uses_pr" -value "1" -objects $obj
set_property -name "dsa.vendor" -value "xilinx" -objects $obj
set_property -name "dsa.version" -value "0.0" -objects $obj
set_property -name "enable_vhdl_2008" -value "1" -objects $obj
set_property -name "ip_cache_permissions" -value "read write" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${_xil_proj_name_}.cache/ip" -objects $obj
set_property -name "mem.enable_memory_map_generation" -value "1" -objects $obj
set_property -name "part" -value "xc7a200tfbg484-2" -objects $obj
set_property -name "sim.central_dir" -value "$proj_dir/${_xil_proj_name_}.ip_user_files" -objects $obj
set_property -name "sim.ip.auto_export_scripts" -value "1" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj

# add source files
set obj [get_filesets sources_1]
set src_list {}
lappend src_list "$sim_dir/cv32e40x_tb.sv"
lappend src_list "$core_dir/rtl/include/cv32e40x_pkg.sv"
lappend src_list "$sim_dir/cv32e40x_wrapper.sv"
foreach file {
    if_xif.sv if_c_obi.sv cv32e40x_core.sv
    cv32e40x_if_stage.sv cv32e40x_id_stage.sv cv32e40x_ex_stage.sv
    cv32e40x_load_store_unit.sv cv32e40x_wb_stage.sv cv32e40x_register_file.sv
    cv32e40x_register_file_wrapper.sv cv32e40x_cs_registers.sv cv32e40x_csr.sv
    cv32e40x_a_decoder.sv           cv32e40x_decoder.sv              cv32e40x_pc_target.sv
    cv32e40x_alignment_buffer.sv    cv32e40x_div.sv                  cv32e40x_pma.sv
    cv32e40x_alu_b_cpop.sv          cv32e40x_popcnt.sv               cv32e40x_m_decoder.sv
    cv32e40x_alu.sv                 cv32e40x_ff_one.sv               cv32e40x_prefetcher.sv
    cv32e40x_b_decoder.sv           cv32e40x_i_decoder.sv            cv32e40x_prefetch_unit.sv
    cv32e40x_compressed_decoder.sv  cv32e40x_controller_bypass.sv    cv32e40x_mpu.sv
    cv32e40x_controller_fsm.sv      cv32e40x_instr_obi_interface.sv  cv32e40x_sleep_unit.sv
    cv32e40x_controller.sv          cv32e40x_int_controller.sv       cv32e40x_mult.sv
    cv32e40x_data_obi_interface.sv
} {
    lappend src_list "$core_dir/rtl/$file"
}
lappend src_list "$core_dir/bhv/cv32e40x_sim_clock_gate.sv"
add_files -fileset $obj -norecurse -scan_for_includes $src_list

# configure simulation
set_property top cv32e40x_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property generic "$prog_paths_var $params_var" -objects [get_filesets sim_1]

launch_simulation

set log_signals [get_objects -r [lrange $argv 5 end]]
add_wave $log_signals

set complete_signal "done"
add_wave $complete_signal

set outf [open $log_file_path "w"]
puts "logging following signals to $log_file_path: $log_signals"

foreach sig $log_signals {
    set sig_name_start [string wordstart $sig end]
    puts -nonewline $outf "[string range $sig $sig_name_start end];"
}
puts $outf ""

# restart the simulation
restart

for {set step 0} 1 {incr step} {
    # log the value of each signal
    foreach sig $log_signals {
        puts -nonewline $outf "[get_value $sig];"
    }
    puts $outf ""

    # advance by 1 clock cycle
    run 10 ns

    # check if the abort condition has been met
    if {[get_value [lindex $complete_signal 0]] != 0} {
        puts "exit condition met after $step clock cycles"
        break
    }
}
close $outf
close_sim -force
