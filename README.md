# Minimal SoC for the Ibex Core

This repository includes the [Ibex repository](https://github.com/lowRISC/ibex)
as a submodule. After cloning you need to initialize the submodule:

    git submodule update --init --recursive

## Simulate using Verilator

Issue the following command to start simulating the programs listed in
`progs.csv` using Verilator:

    make verilator

Verify that the program was correctly executed by comparing the memory dump of
the program run with reference dump:

    diff -u test.ref.vmem test.dump.vmem
