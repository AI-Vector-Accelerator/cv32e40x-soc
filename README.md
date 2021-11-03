# Minimal SoC for the CV32E40X Core

This repository includes the
[CV32E40X repository](https://github.com/openhwgroup/cv32e40x.git)
as a submodule. After cloning you need to initialize the submodule:

    git submodule update --init --recursive

## Simulate using Verilator

Issue the following command to start simulating the programs listed in
`progs.csv` using Verilator:

    make verilator

Verify that the program was correctly executed by comparing the memory dump of
the program run with reference dump:

    diff -u test.ref.vmem test.dump.vmem
