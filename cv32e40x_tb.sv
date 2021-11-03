// Copyright TU Wien
// Licensed under the ISC license, see LICENSE.txt for details
// SPDX-License-Identifier: ISC


module cv32e40x_tb #(
        parameter              PROG_PATHS_LIST = "",
        parameter int unsigned MEM_W           = 32,
        parameter int unsigned MEM_SZ          = 262144,
        parameter int unsigned MEM_LATENCY     = 1
    );

    logic clk, rst;
    always begin
        clk = 1'b0;
        #5;
        clk = 1'b1;
        #5;
    end

    logic        mem_req;
    logic [31:0] mem_addr;
    logic        mem_we;
    logic [3:0]  mem_be;
    logic [31:0] mem_wdata;
    logic        mem_rvalid;
    logic        mem_err;
    logic [31:0] mem_rdata;

    cv32e40x_wrapper #(
        .MEM_W         ( MEM_W                       )
    ) wrapper (
        .clk_i         ( clk                         ),
        .rst_ni        ( ~rst                        ),
        .mem_req_o     ( mem_req                     ),
        .mem_addr_o    ( mem_addr                    ),
        .mem_we_o      ( mem_we                      ),
        .mem_be_o      ( mem_be                      ),
        .mem_wdata_o   ( mem_wdata                   ),
        .mem_rvalid_i  ( mem_rvalid                  ),
        .mem_err_i     ( mem_err                     ),
        .mem_rdata_i   ( mem_rdata                   )
    );

    // memory
    logic [MEM_W-1:0]                    mem[MEM_SZ/(MEM_W/8)];
    logic [$clog2(MEM_SZ/(MEM_W/8))-1:0] mem_idx;
    assign mem_idx = mem_addr[$clog2(MEM_SZ)-1 : $clog2(MEM_W/8)];
    // latency pipeline
    logic        mem_rvalid_queue[MEM_LATENCY];
    logic [31:0] mem_rdata_queue [MEM_LATENCY];
    logic        mem_err_queue   [MEM_LATENCY];
    always_ff @(posedge clk) begin
        if (mem_req & mem_we) begin
            for (int i = 0; i < MEM_W/8; i++) begin
                if (mem_be[i]) begin
                    mem[mem_idx][i*8 +: 8] <= mem_wdata[i*8 +: 8];
                end
            end
        end
        for (int i = 1; i < MEM_LATENCY; i++) begin
            mem_rvalid_queue[i] <= mem_rvalid_queue[i-1];
            mem_rdata_queue [i] <= mem_rdata_queue [i-1];
            mem_err_queue   [i] <= mem_err_queue   [i-1];
        end
        mem_rvalid <= mem_rvalid_queue[MEM_LATENCY-1];
        mem_rdata  <= mem_rdata_queue [MEM_LATENCY-1];
        mem_err    <= mem_err_queue   [MEM_LATENCY-1];
    end
    assign mem_rvalid_queue[0] = mem_req;
    assign mem_rdata_queue [0] = mem[mem_idx];
    assign mem_err_queue   [0] = mem_addr[31:$clog2(MEM_SZ)] != '0;

    logic prog_end, done;
    assign prog_end = mem_req & (mem_addr == '0);

    integer fd1, fd2, cnt, ref_start, ref_end, dump_start, dump_end;
    string  line, prog_path, ref_path, dump_path;
    initial begin
        done = 1'b0;

        fd1 = $fopen(PROG_PATHS_LIST, "r");
        for (int i = 0; !$feof(fd1); i++) begin
            rst = 1'b1;

            $fgets(line, fd1);
            cnt = $sscanf(line, "%s %s %x %x %s %x %x", prog_path, ref_path, ref_start, ref_end, dump_path, dump_start, dump_end);
            if (cnt != 7) begin
                continue;
            end

            for (int j = 0; j < MEM_SZ / (MEM_W/8); j++) begin
                mem[j] = '0;
            end
            $readmemh(prog_path, mem);

            fd2 = $fopen(ref_path, "w");
            for (int j = ref_start / (MEM_W/8); j < ref_end / (MEM_W/8); j++) begin
                for (int k = 0; k < MEM_W/32; k++) begin
                    $fwrite(fd2, "%x\n", mem[j][k*32 +: 32]);
                end
            end
            $fclose(fd2);

            // reset for 10 cycles
            #100
            rst = 1'b0;

            // wait for completion (i.e. request of instr mem addr 0x00000000)
            //@(posedge prog_end);
            while (1) begin
                @(posedge clk);
                if (prog_end) begin
                    break;
                end
            end

            fd2 = $fopen(dump_path, "w");
            for (int j = dump_start / (MEM_W/8); j < dump_end / (MEM_W/8); j++) begin
                for (int k = 0; k < MEM_W/32; k++) begin
                    $fwrite(fd2, "%x\n", mem[j][k*32 +: 32]);
                end
            end
            $fclose(fd2);
        end
        $fclose(fd1);
        done = 1'b1;
    end

endmodule
