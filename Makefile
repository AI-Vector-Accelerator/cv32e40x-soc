# Copyright TU Wien
# Licensed under the ISC license, see LICENSE.txt for details
# SPDX-License-Identifier: ISC


# Simulations Makefile
# requires GNU make; avoid spaces in directory names!

SHELL := /bin/bash

# get the absolute path of the simulation directory (must not contain spaces!)
SIM_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Vivado TCL script
VIVADO_TCL := $(addprefix $(SIM_DIR),sim_vivado.tcl)

# project directory
PROJ_DIR_TMP := $(shell mktemp -d)
PROJ_DIR     ?= $(PROJ_DIR_TMP)

# main core directory
CORE_DIR ?= $(SIM_DIR)/cv32e40x/

# memory files
PROG_PATHS_LIST ?= progs.csv

# select memory width (bits), size (bytes), and latency (cycles, 1 is minimum)
MEM_W		?= 32
MEM_SZ      ?= 262144
MEM_LATENCY ?= 1

vivado:
	cd $(PROJ_DIR) && vivado -mode batch -source $(VIVADO_TCL)                \
	    -tclargs $(SIM_DIR) $(CORE_DIR)                                       \
	    "MEM_W=$(MEM_W) MEM_SZ=$(MEM_SZ) MEM_LATENCY=$(MEM_LATENCY)"          \
	    $(SIM_DIR)/vivado.csv $(abspath $(PROG_PATHS_LIST)) 'clk'

verilator:
	cp $(SIM_DIR)/verilator_main.cpp $(PROJ_DIR)/
	cd $(PROJ_DIR);                                                           \
	trace="";                                                                 \
	if [[ "$(TRACE_VCD)" != "" ]]; then                                       \
	    trace="--trace -CFLAGS -DTRACE_VCD";                                  \
	fi;                                                                       \
	verilator --unroll-count 1024 -Wno-UNSIGNED                               \
	    -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT                             \
	    -Wno-IMPLICIT -Wno-LITENDIAN -Wno-CASEINCOMPLETE -Wno-SYMRSVDWORD     \
	    -Wno-BLKANDNBLK                                                       \
	    -I$(SIM_DIR) -I$(CORE_DIR)/rtl/ -I$(CORE_DIR)/rtl/include             \
	    -I$(CORE_DIR)/bhv/                                                    \
	    -GMEM_W=$(MEM_W)                                                      \
	    --cc cv32e40x_pkg.sv if_xif.sv cv32e40x_wrapper.sv                    \
	    cv32e40x_sim_clock_gate.sv cv32e40x_core.sv                           \
	    --top-module cv32e40x_wrapper                                         \
	    --clk clk_i $$trace --exe verilator_main.cpp;                         \
	if [ "$$?" != "0" ]; then                                                 \
	    exit 1;                                                               \
	fi;                                                                       \
	make -C $(PROJ_DIR)/obj_dir -f Vcv32e40x_wrapper.mk Vcv32e40x_wrapper;    \
	$(PROJ_DIR)/obj_dir/Vcv32e40x_wrapper $(abspath $(PROG_PATHS_LIST))       \
	    $(MEM_W) $(MEM_SZ) $(MEM_LATENCY) 100 $(abspath $(TRACE_VCD))
