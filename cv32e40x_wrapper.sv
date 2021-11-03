
module cv32e40x_wrapper #(
        parameter int unsigned     MEM_W = 32
    )(
        input  logic               clk_i,
        input  logic               rst_ni,

        output logic               mem_req_o,
        output logic [31:0]        mem_addr_o,
        output logic               mem_we_o,
        output logic [MEM_W/8-1:0] mem_be_o,
        output logic [MEM_W  -1:0] mem_wdata_o,
        input  logic               mem_rvalid_i,
        input  logic               mem_err_i,
        input  logic [MEM_W  -1:0] mem_rdata_i
    );

    logic             imem_req;
    logic             imem_gnt;
    logic [31:0]      imem_addr;
    logic             imem_rvalid;
    logic [MEM_W-1:0] imem_rdata;
    logic             imem_err;

    logic               dmem_req;
    logic               dmem_gnt;
    logic [31:0]        dmem_addr;
    logic               dmem_we;
    logic [MEM_W/8-1:0] dmem_be;
    logic [MEM_W  -1:0] dmem_wdata;
    logic               dmem_rvalid;
    logic [MEM_W  -1:0] dmem_rdata;
    logic               dmem_err;


    // eXtension Interface
    if_xif #(
        .X_NUM_RS    ( 2  ),
        .X_MEM_WIDTH ( 32 ),
        .X_RFR_WIDTH ( 32 ),
        .X_RFW_WIDTH ( 32 ),
        .X_MISA      ( '0 )
    ) ext_if();

    cv32e40x_core core (
        .clk_i               ( clk_i        ),
        .rst_ni              ( rst_ni       ),
        .scan_cg_en_i        ( 1'b0         ),
        .boot_addr_i         ( 32'h00000080 ),
        .mtvec_addr_i        ( 32'h00000000 ),
        .dm_halt_addr_i      ( '0           ),
        .hart_id_i           ( '0           ),
        .dm_exception_addr_i ( '0           ),
        .nmi_addr_i          ( '0           ),
        .instr_req_o         ( imem_req     ),
        .instr_gnt_i         ( imem_gnt     ),
        .instr_rvalid_i      ( imem_rvalid  ),
        .instr_addr_o        ( imem_addr    ),
        .instr_memtype_o     (              ),
        .instr_prot_o        (              ),
        .instr_rdata_i       ( imem_rdata   ),
        .instr_err_i         ( imem_err     ),
        .data_req_o          ( dmem_req     ),
        .data_gnt_i          ( dmem_gnt     ),
        .data_rvalid_i       ( dmem_rvalid  ),
        .data_we_o           ( dmem_we      ),
        .data_be_o           ( dmem_be      ),
        .data_addr_o         ( dmem_addr    ),
        .data_memtype_o      (              ),
        .data_prot_o         (              ),
        .data_wdata_o        ( dmem_wdata   ),
        .data_rdata_i        ( dmem_rdata   ),
        .data_err_i          ( dmem_err     ),
        .data_atop_o         (              ),
        .data_exokay_i       ( 1'b0         ),
        .xif_compressed_if   ( ext_if       ),
        .xif_issue_if        ( ext_if       ),
        .xif_commit_if       ( ext_if       ),
        .xif_mem_if          ( ext_if       ),
        .xif_mem_result_if   ( ext_if       ),
        .xif_result_if       ( ext_if       ),
        .irq_i               ( '0           ),
        .fencei_flush_req_o  (              ),
        .fencei_flush_ack_i  ( 1'b0         ),
        .debug_req_i         ( 1'b0         ),
        .debug_havereset_o   (              ),
        .debug_running_o     (              ),
        .debug_halted_o      (              ),
        .fetch_enable_i      ( 1'b1         ),
        .core_sleep_o        (              )
    );

    dummy_extension ext (
        .clk_i          ( clk_i  ),
        .rst_ni         ( rst_ni ),
        .xif_compressed ( ext_if ),
        .xif_issue      ( ext_if ),
        .xif_commit     ( ext_if ),
        .xif_mem        ( ext_if ),
        .xif_mem_result ( ext_if ),
        .xif_result     ( ext_if )
    );


    ///////////////////////////////////////////////////////////////////////////
    // Memory arbiter

    always_comb begin
        mem_req_o   = imem_req | dmem_req;
        mem_addr_o  = imem_addr;
        mem_we_o    = 1'b0;
        mem_be_o    = dmem_be;
        mem_wdata_o = dmem_wdata;
        if (dmem_req) begin
            mem_we_o   = dmem_we;
            mem_addr_o = dmem_addr;
        end
    end
    assign imem_gnt = imem_req & ~dmem_req;
    assign dmem_gnt =             dmem_req;

    // shift register keeping track of the source of mem requests for up to 32 cycles
    logic        req_sources  [32];
    logic [31:0] imem_req_addr[32]; // keeping track of address for instruction memory requests
    logic [4:0]  req_count;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            req_count <= '0;
        end else begin
            if (mem_rvalid_i) begin
                for (int i = 0; i < 31; i++) begin
                    req_sources  [i] <= req_sources  [i+1];
                    imem_req_addr[i] <= imem_req_addr[i+1];
                end
                if (~imem_gnt & ~dmem_gnt) begin
                    req_count <= req_count - 1;
                end else begin
                    req_sources  [req_count-1] <= dmem_gnt;
                    imem_req_addr[req_count-1] <= imem_addr;
                end
            end
            else if (imem_gnt | dmem_gnt) begin
                req_sources  [req_count] <= dmem_gnt;
                imem_req_addr[req_count] <= imem_addr;
                req_count                <= req_count + 1;
            end
        end
    end
    assign imem_rvalid = mem_rvalid_i & ~req_sources[0];
    assign dmem_rvalid = mem_rvalid_i &  req_sources[0];
    assign imem_err    = mem_err_i;
    assign dmem_err    = mem_err_i;
    assign imem_rdata  = mem_rdata_i[(imem_req_addr[0][$clog2(MEM_W/8)-1:0] & {{$clog2(MEM_W/32){1'b1}}, 2'b00})*8 +: 32];
    assign dmem_rdata  = mem_rdata_i;

endmodule


module dummy_extension (
        input logic              clk_i,
        input logic              rst_ni,

        if_xif.coproc_compressed xif_compressed,
        if_xif.coproc_issue      xif_issue,
        if_xif.coproc_commit     xif_commit,
        if_xif.coproc_mem        xif_mem,
        if_xif.coproc_mem_result xif_mem_result,
        if_xif.coproc_result     xif_result
    );

    assign xif_compressed.compressed_ready = '0;
    assign xif_compressed.compressed_resp  = '0;
    assign xif_issue.issue_ready           = '1;
    assign xif_issue.issue_resp.accept     = '1;
    assign xif_issue.issue_resp.writeback  = '1;
    assign xif_issue.issue_resp.float      = '0;
    assign xif_issue.issue_resp.dualwrite  = '0;
    assign xif_issue.issue_resp.dualread   = '0;
    assign xif_issue.issue_resp.loadstore  = '0;
    assign xif_issue.issue_resp.exc        = '1;
    assign xif_mem.mem_valid               = '0;
    assign xif_mem.mem_req                 = '0;
    assign xif_result.result_valid         = xif_result.result_ready;
    assign xif_result.result               = '0;

endmodule
