// Copyright TU Wien
// Licensed under the ISC license, see LICENSE.txt for details
// SPDX-License-Identifier: ISC


#include <stdio.h>
#include <stdint.h>
#include "Vcv32e40x_wrapper.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

static void log_cycle(VerilatedVcdC* tfp);

int main(int argc, char **argv) {
    if (argc != 6 && argc != 7) {
        fprintf(stderr, "Usage: %s PROG_PATHS_LIST MEM_W MEM_SZ MEM_LATENCY EXTRA_CYCLES [WAVEFORM_FILE]\n", argv[0]);
        return 1;
    }

    int mem_w, mem_sz, mem_latency, extra_cycles;
    {
        char *endptr;
        mem_w = strtol(argv[2], &endptr, 10);
        if (mem_w == 0 || *endptr != 0) {
            fprintf(stderr, "ERROR: invalid MEM_W argument\n");
            return 1;
        }
        mem_sz = strtol(argv[3], &endptr, 10);
        if (mem_sz == 0 || *endptr != 0) {
            fprintf(stderr, "ERROR: invalid MEM_SZ argument\n");
            return 1;
        }
        mem_latency = strtol(argv[4], &endptr, 10);
        if (*endptr != 0) {
            fprintf(stderr, "ERROR: invalid MEM_LATENCY argument\n");
            return 1;
        }
        extra_cycles = strtol(argv[5], &endptr, 10);
        if (*endptr != 0) {
            fprintf(stderr, "ERROR: invalid EXTRA_CYCLES argument\n");
            return 1;
        }
    }

    Verilated::traceEverOn(true);
    //Verilated::commandArgs(argc, argv);

    FILE *fprogs = fopen(argv[1], "r");
    if (fprogs == NULL) {
        fprintf(stderr, "ERROR: opening `%s': %s\n", argv[1], strerror(errno));
        return 2;
    }

    unsigned char *mem = (unsigned char *)malloc(mem_sz);
    if (mem == NULL) {
        fprintf(stderr, "ERROR: allocating %d bytes of memory: %s\n", mem_sz, strerror(errno));
        return 3;
    }
    int64_t *mem_rvalid_queue = (int64_t *)malloc(sizeof(int64_t) * mem_latency);
    int64_t *mem_rdata_queue  = (int64_t *)malloc(sizeof(int64_t) * mem_latency);
    int64_t *mem_err_queue    = (int64_t *)malloc(sizeof(int64_t) * mem_latency);

    Vcv32e40x_wrapper *top = new Vcv32e40x_wrapper;
    VerilatedVcdC* tfp = NULL;
#ifdef TRACE_VCD
    if (argc == 7) {
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);  // Trace 99 levels of hierarchy
        tfp->open(argv[6]);
    }
#endif

    char *line = NULL, *prog_path = NULL, *ref_path = NULL, *dump_path = NULL;
    size_t line_sz = 0;
    while (getline(&line, &line_sz, fprogs) > 0) {
        prog_path = (char *)realloc(prog_path, line_sz);
        ref_path  = (char *)realloc(ref_path,  line_sz);
        dump_path = (char *)realloc(dump_path, line_sz);

        int ref_start, ref_end, dump_start, dump_end, items;
        items = sscanf(line, "%s %s %x %x %s %x %x", prog_path, ref_path, &ref_start, &ref_end, dump_path, &dump_start, &dump_end);
        if (items != 7)
            continue;

        // read program file
        {
            FILE *ftmp = fopen(prog_path, "r");
            if (ftmp == NULL) {
                fprintf(stderr, "ERROR: opening `%s': %s\n", prog_path, strerror(errno));
                continue;
            }
            memset(mem, 0, mem_sz);
            char buf[256];
            int addr = 0;
            while (fgets(buf, sizeof(buf), ftmp) != NULL) {
                if (buf[0] == '#' || buf[0] == '/')
                    continue;
                char *ptr = buf;
                if (buf[0] == '@') {
                    addr = strtol(ptr + 1, &ptr, 16) * 4;
                    while (*ptr == ' ')
                        ptr++;
                }
                while (*ptr != '\n' && *ptr != 0) {
                    int data = strtol(ptr, &ptr, 16);
                    int i;
                    for (i = 0; i < 4; i++)
                        mem[addr+i] = data >> (8*i);
                    addr += 4;
                    while (*ptr == ' ')
                        ptr++;
                }
            }
            fclose(ftmp);
        }

        // write reference file
        {
            FILE *ftmp = fopen(ref_path, "w");
            if (ftmp == NULL) {
                fprintf(stderr, "ERROR: opening `%s': %s\n", ref_path, strerror(errno));
            }
            int addr;
            for (addr = ref_start; addr < ref_end; addr += 4) {
                int data = mem[addr] | (mem[addr+1] << 8) | (mem[addr+2] << 16) | (mem[addr+3] << 24);
                fprintf(ftmp, "%08x\n", data);
            }
            fclose(ftmp);
        }

        // simulate program execution
        {
            int i;
            for (i = 0; i < mem_latency; i++)
                mem_rvalid_queue[i] = 0;
            top->mem_rvalid_i = 0;
            top->clk_i        = 0;
            top->rst_ni       = 0;
            for (i = 0; i < 10; i++) {
                top->clk_i = 1;
                top->eval();
                top->clk_i = 0;
                top->eval();
                log_cycle(tfp);
            }
            top->rst_ni = 1;
            top->eval();

            int end_cnt = 0;
            //int end_cnt = 1;
            while (end_cnt < extra_cycles) {
                // read memory request
                int addr = (top->mem_addr_o % mem_sz) & ~(mem_w/8-1);
                if (top->mem_req_o && top->mem_we_o) {
                    for (i = 0; i < mem_w / 8; i++)
                        if ((top->mem_be_o & (1<<i)))
                            mem[addr+i] = top->mem_wdata_o >> (i*8);
                }
                mem_rvalid_queue[0] = top->mem_req_o;
                mem_err_queue   [0] = addr >= mem_sz;
                mem_rdata_queue [0] = 0;
                for (i = 0; i < mem_w / 8; i++)
                    mem_rdata_queue[0] |= ((int64_t)mem[addr+i]) << (i*8);

                // rising clock edge
                top->clk_i = 1;
                top->eval();

                // fulfill memory request
                top->mem_rvalid_i = mem_rvalid_queue[mem_latency-1];
                top->mem_rdata_i  = mem_rdata_queue [mem_latency-1];
                top->mem_err_i    = mem_err_queue   [mem_latency-1];
                top->eval();
                for (i = mem_latency-1; i > 0; i--) {
                    mem_rvalid_queue[i] = mem_rvalid_queue[i-1];
                    mem_rdata_queue [i] = mem_rdata_queue [i-1];
                    mem_err_queue   [i] = mem_err_queue   [i-1];
                }

                // falling clock edge
                top->clk_i = 0;
                top->eval();

                // log data
                log_cycle(tfp);

                if (end_cnt > 0 || (top->mem_req_o == 1 && top->mem_addr_o == 0)) {
                    end_cnt++;
                }
            }
        }

        // write dump file
        {
            FILE *ftmp = fopen(dump_path, "w");
            if (ftmp == NULL) {
                fprintf(stderr, "ERROR: opening `%s': %s\n", dump_path, strerror(errno));
            }
            int addr;
            for (addr = dump_start; addr < dump_end; addr += 4) {
                int data = mem[addr] | (mem[addr+1] << 8) | (mem[addr+2] << 16) | (mem[addr+3] << 24);
                fprintf(ftmp, "%08x\n", data);
            }
            fclose(ftmp);
        }
    }

#ifdef TRACE_VCD
    if (tfp != NULL)
        tfp->close();
#endif
    top->final();
    free(prog_path);
    free(ref_path);
    free(dump_path);
    free(line);
    free(mem);
    free(mem_rvalid_queue);
    free(mem_rdata_queue);
    free(mem_err_queue);
    fclose(fprogs);
    return 0;
}

vluint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

static void log_cycle(VerilatedVcdC* tfp) {
    main_time++;
#ifdef TRACE_VCD
    if (tfp != NULL)
        tfp->dump(main_time);
#endif
}
