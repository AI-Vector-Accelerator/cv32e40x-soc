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

#ava core directory
AVA_DIR ?= $(SIM_DIR)/x-ava-core/

# memory files
PROG_PATHS_LIST ?= progs.csv

# select memory width (bits), size (bytes), and latency (cycles, 1 is minimum)
MEM_W		?= 32
MEM_SZ      ?= 262144
MEM_LATENCY ?= 1

# programs for testing
PROGS ?= test.S

TRACE_VCD = trace.vcd

.PHONY: vivado verilator clean

vivado: progs.csv
	cd $(PROJ_DIR) && vivado -mode batch -source $(VIVADO_TCL)                \
	    -tclargs $(SIM_DIR) $(CORE_DIR)                                       \
	    "MEM_W=$(MEM_W) MEM_SZ=$(MEM_SZ) MEM_LATENCY=$(MEM_LATENCY)"          \
	    $(SIM_DIR)/vivado.csv $(abspath $(PROG_PATHS_LIST)) 'clk'

verilator: progs.csv
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
	    -I$(CORE_DIR)/bhv/ -I$(AVA_DIR)/rtl/                                  \
	    -GMEM_W=$(MEM_W)                                                      \
	    --cc cv32e40x_pkg.sv if_xif.sv cv32e40x_wrapper.sv                    \
	    cv32e40x_sim_clock_gate.sv cv32e40x_core.sv accelerator_pkg.sv        \
	    --top-module cv32e40x_wrapper                                         \
	    --clk clk_i $$trace --exe verilator_main.cpp;                         \
	if [ "$$?" != "0" ]; then                                                 \
	    exit 1;                                                               \
	fi;                                                                       \
	make -C $(PROJ_DIR)/obj_dir -f Vcv32e40x_wrapper.mk Vcv32e40x_wrapper;    \
	$(PROJ_DIR)/obj_dir/Vcv32e40x_wrapper $(abspath $(PROG_PATHS_LIST))       \
	    $(MEM_W) $(MEM_SZ) $(MEM_LATENCY) 100 $(abspath $(TRACE_VCD))

progs.csv: $(PROGS)
	for prog in $(PROGS:.S=.vmem); do                                         \
	    make -f $(SIM_DIR)/sw/Makefile $$prog;                                \
	done
	@rm -f progs.csv;                                                         \
	for prog in $(abspath $(PROGS:.S=.vmem)); do                              \
	    elf="$${prog%.*}.elf";                                                \
	    vref_start=`readelf -s $$elf | grep vref_start |                      \
	                sed 's/^.*\([A-Fa-f0-9]\{8\}\).*$$/\1/'`;                 \
	    vref_end=`readelf -s $$elf | grep vref_end |                          \
	              sed 's/^.*\([A-Fa-f0-9]\{8\}\).*$$/\1/'`;                   \
	    vdata_start=`readelf -s $$elf | grep vdata_start |                    \
	                 sed 's/^.*\([A-Fa-f0-9]\{8\}\).*$$/\1/'`;                \
	    vdata_end=`readelf -s $$elf | grep vdata_end |                        \
	               sed 's/^.*\([A-Fa-f0-9]\{8\}\).*$$/\1/'`;                  \
	    memref="$${prog%.*}.ref.vmem $$vref_start $$vref_end";                \
	    memo="$${prog%.*}.dump.vmem $$vdata_start $$vdata_end";               \
	    echo "$$prog $$memref $$memo " >> progs.csv;                          \
	done

clean:
	rm -rf *.vmem *.elf *.o progs.csv
