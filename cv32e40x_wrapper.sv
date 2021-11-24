
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

    // Data read/write for Vector Unit
    logic                vdata_gnt;
    logic                vdata_rvalid;
    logic                vdata_err;
    logic [31:0]         vdata_rdata;
    logic                vdata_req;
    logic [31:0]         vdata_addr;
    logic                vdata_we;
    logic [3:0]          vdata_be;
    logic [31:0]         vdata_wdata;

    xava ext (
        .clk_i          ( clk_i  ),
        .rst_ni         ( rst_ni ),
        .xif_compressed ( ext_if ),
        .xif_issue      ( ext_if ),
        .xif_commit     ( ext_if ),
        .xif_mem        ( ext_if ),
        .xif_mem_result ( ext_if ),
        .xif_result     ( ext_if ),
	
	.data_req_o       ( vdata_req          ),
        .data_gnt_i       ( vdata_gnt          ),
        .data_rvalid_i    ( vdata_rvalid       ),
        .data_rdata_i     ( vdata_rdata        ),
        .data_addr_o      ( vdata_addr         ),
        .data_we_o        ( vdata_we           ),
        .data_be_o        ( vdata_be           ),
        .data_wdata_o     ( vdata_wdata        )

    );


    // Data arbiter for main core and vector unit
    logic              sdata_hold;
    logic              data_req;
    logic [31:0]       data_addr;
    logic              data_we;
    logic [3:0]        data_be;
    logic [31:0]       data_wdata;
    logic              data_gnt;
    logic              data_rvalid;
    logic              data_err;
    logic [31:0]       data_rdata;
    logic              sdata_waiting, vdata_waiting;
    logic [31:0]       sdata_wait_addr;
    //assign sdata_hold = vdata_req | vect_pending_store | (vect_pending_load & sdata_we);
    assign sdata_hold = vdata_req;

    always_comb begin
        data_req   = vdata_req | (dmem_req & ~sdata_hold);
        data_addr  = dmem_addr;
        data_we    = dmem_we;
        data_be    = {{(MEM_W-32){1'b0}}, dmem_be} << (dmem_addr[$clog2(MEM_W/8)-1:0] & {{$clog2(MEM_W/32){1'b1}}, 2'b00});
        data_wdata = '0;
        for (int i = 0; i < MEM_W / 32; i++) begin
            data_wdata[32*i +: 32] = dmem_wdata;
        end
        if (vdata_req) begin
            data_addr  = vdata_addr;
            data_we    = vdata_we;
            data_be    = vdata_be;
            data_wdata = vdata_wdata;
        end
    end
    assign sdata_gnt = data_gnt & dmem_req & ~sdata_hold;
    assign vdata_gnt = data_gnt & vdata_req;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            sdata_waiting   <= 1'b0;
            vdata_waiting   <= 1'b0;
            sdata_wait_addr <= '0;
        end else begin
            if (sdata_gnt) begin
                sdata_waiting   <= 1'b1;
                sdata_wait_addr <= dmem_addr;
            end
            else if (sdata_rvalid) begin
                sdata_waiting <= 1'b0;
            end
            if (vdata_gnt) begin
                vdata_waiting <= ~vdata_we; // vector processor expects rvalid only for reads
            end
            else if (vdata_rvalid) begin
                vdata_waiting <= 1'b0;
            end
        end
    end
    assign sdata_rvalid = sdata_waiting & data_rvalid;
    assign vdata_rvalid = vdata_waiting & data_rvalid;
    assign sdata_err    = data_err;
    assign vdata_err    = data_err;
    assign sdata_rdata  = data_rdata[(sdata_wait_addr[$clog2(MEM_W/8)-1:0] & {{$clog2(MEM_W/32){1'b1}}, 2'b00})*8 +: 32];
    assign vdata_rdata  = data_rdata;


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

////////////////////////////////////////////////////////////////////
//AVA CORE
module xava(
    input logic              clk_i,
    input logic              rst_ni,
    if_xif.coproc_compressed xif_compressed, //unused
    if_xif.coproc_issue      xif_issue, //issue_valid, issue_ready, req and resp pkt 
    if_xif.coproc_commit     xif_commit, //commit_valid, commit pkt
    if_xif.coproc_mem        xif_mem, //mem_valid, mem_ready, req and resp pkt
    if_xif.coproc_mem_result xif_mem_result, //output mem_result_valid, output mem_result, mem result sent to 
    if_xif.coproc_result     xif_result, //result_valid, result_ready, result pkt

    // vector memory interface
    output logic                  data_req_o,
    input  logic                  data_gnt_i,
    input  logic                  data_rvalid_i,
    //input  logic                  data_err_i,
    input  logic [31:0]           data_rdata_i,
    output logic [31:0]           data_addr_o,
    output logic                  data_we_o,
    output logic [3:0]            data_be_o,
    output logic [31:0]           data_wdata_o

    );
    
    //Instantiate accelerator top and adaptor
    wire  [31:0] apu_result;
    wire  [4:0]  apu_flags_o;
    wire          apu_gnt;
    wire         apu_rvalid;
    
    wire         apu_req;
    wire  [2:0][31:0] apu_operands_i;
    wire  [5:0]  apu_op;
    wire  [14:0] apu_flags_i;
    //wire         data_req_o;
    //wire         data_gnt_i;
    //wire         data_rvalid_i;
    //wire         data_we_o;
    //wire  [3:0]  data_be_o;
    //wire  [31:0] data_addr_o;
    //wire  [31:0] data_wdata_o;
    //wire  [31:0] data_rdata_i;
    wire         core_halt_o;


    accelerator_top acctop0(
	    .apu_result		(apu_result),
	    .apu_flags_o	(apu_flag_o), //nothing returned to interface/cpu, maybe use for something else?
	    .apu_gnt		(apu_gnt), //WAIT state in decoder, when gnt = 1 apu_operands_o, apu_op_o, apu_flags_o may change next cycle
	    .apu_rvalid		(apu_rvalid),
	    .clk		(clk_i),
	    .n_reset		(rst_ni),
	    .apu_req		(apu_req), // && xif_issue.issue_ready), //ready for new instructions (revisit)
	    .apu_operands_i	(apu_operands_i), //this contains the funct3, major_opcode, funct6, source1, source2, destination fields 
	    //...of type wire [2:0][31:0];
	    .apu_op		(apu_op), //this tells the core what apu op is required but not used within ava... 
	    .apu_flags_i	(apu_flags_i), //again this is meant to pass in flags, just stored and not used

	    //VLSU signals
	    .data_req_o		(data_req_o), //vlsu signal for in LOAD_CYCLE and STORE_CYCLE in vlsu (request)
	    .data_gnt_i		(data_gnt_i), //vlsu signal, not used anywhere... (generate)
	    .data_rvalid_i	(data_rvalid_i), //vlsu signal for in LOAD_WAIT and STORE_WAIT (result valid)
	    .data_we_o		(data_we_o), //vlsu signal for in STORE_CYCLE (write enable?)
	    .data_be_o		(data_be_o), //vlsu signal, (byte enable?)
	    //= vlsu_store_i ? store_cycle_be : 4'b1111; in vlsu
	    .data_addr_o	(data_addr_o), //vlsu signal, data address output 
	    //= vlsu_store_i ? ({cycle_addr[31:2], 2'd0} + (store_cycles_cnt << 2)) : {cycle_addr[31:2], 2'd0};
	    .data_wdata_o	(data_wdata_o), //vlsu signal, (write data out), set to 0...
	    .data_rdata_i	(data_rdata_i), //vlsu signal, (read data in), written to temporary reg and split into words 32bits -> 4x8bits 
	    
	    //Core halt signal
	    .core_halt_o	(core_halt_o)  //core halt to stop main core?
	);

    //Pack the x interface
    //assign input output
   
    //COMPRESSED INTERFACE - NOT USED
    assign xif_compressed.compressed_ready = '0;
    assign xif_compressed.compressed_resp  = '0;

    //ISSUE INTERFACE
    assign apu_req = xif_issue.issue_valid;
    assign apu_operands_i [0] = xif_issue.issue_req.instr; //Contains instr
    assign apu_operands_i [1] = xif_issue.issue_req.rs[0]; //register operand 1
    assign apu_operands_i [2] = xif_issue.issue_req.rs[1]; //register operand 2
    assign xif_issue.issue_ready = apu_gnt; 
    assign apu_req = xif_issue.issue_valid;
    assign xif_issue.issue_resp.accept = '1; //Is copro accepted by processor?
    assign xif_issue.issue_resp.writeback = '1; //Will copro writeback?

    //COMMIT INTERFACE
    //assign ?? = xif_commit.commit_valid & ~xif_commit.commit_kill;
    //assign ?? = xif_commit.commit_valid & xif_commit.commit_kill;


    //RESULT INTERFACE
    //assign ?? = xif_result.result_ready; //apu result is ready...
    assign xif_result.result_valid = apu_rvalid;
    assign xif_result.result.id = '0;
    assign xif_result.result.data = apu_result;
    assign xif_result.result.rd = '0;
    assign xif_result.result.we = '1;
    assign xif_result.result.float = '0;
    assign xif_result.result.exc = '0;
    assign xif_result.result.exccode = '0;

endmodule
