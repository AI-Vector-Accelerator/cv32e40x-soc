
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

    logic               dmem_req; //connect to 'mem_valid' incoming handshake (<-)
    logic               dmem_gnt; //connect to 'mem_ready' outgoing (->)
    logic [31:0]        dmem_addr; // <- 'mem_req.addr'
    logic               dmem_we; // <- 'mem_req.we'
    logic [MEM_W/8-1:0] dmem_be;
    logic [MEM_W  -1:0] dmem_wdata; // 'mem_req.wdata'
    logic               dmem_rvalid; // -> 'mem_result_valid'
    logic [MEM_W  -1:0] dmem_rdata; // -> 'mem_result.rdata'
    logic               dmem_err; // -> 'mem_result.err'

    logic [1:0]         dmem_size;  // <- 'mem_req.size' - Specific to XIF, use instead of 'dmem_be' in such cases

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

    xava ext (
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
        mem_be_o    = dmem_be; //byte enables only relevant for data mem accesses
        mem_wdata_o = dmem_wdata; //instr accesses are only fetches
        if (dmem_req) begin // Seems like data memory access has priority in the case of simulataneous data/instr requests?
            mem_we_o   = dmem_we;
            mem_addr_o = dmem_addr;
        end
    end
    assign imem_gnt = imem_req & ~dmem_req; // Ah yep, seems to be confirmed here
    assign dmem_gnt =             dmem_req;

    // shift register keeping track of the source of mem requests for up to 32 cycles
    logic        req_sources  [32]; //data or instr req?
    logic [31:0] imem_req_addr[32]; // keeping track of address for instruction memory requests
    logic [4:0]  req_count; // keeps track of number of queued requests (And therein where in shift register to write new requests to)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (~rst_ni) begin
            req_count <= '0;
        end else begin
            if (mem_rvalid_i) begin
                for (int i = 0; i < 31; i++) begin
                    req_sources  [i] <= req_sources  [i+1];
                    imem_req_addr[i] <= imem_req_addr[i+1];
                end
                if (~imem_gnt & ~dmem_gnt) begin //i.e. No memory access requests
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
    if_xif.coproc_result     xif_result //result_valid, result_ready, result pkt
    );
    
    //Instantiate accelerator top and adaptor
    wire  [31:0] apu_result;
    wire  [4:0]  apu_flags_o;
    wire          apu_gnt;
    wire         apu_rvalid;
    wire  [X_ID_WIDTH-1:0]       instruction_id;
    
    wire         apu_req;
    wire  [2:0][31:0] apu_operands_i;
    wire  [X_ID_WIDTH-1:0] offloaded_id_i;
    wire  [5:0]  apu_op;
    wire  [14:0] apu_flags_i;
    wire         data_req_o;
    wire         data_gnt_i;
    wire         data_rvalid_i;
    wire         data_we_o;
    wire  [3:0]  data_be_o;
    wire  [31:0] data_addr_o;
    wire  [31:0] data_wdata_o;
    wire  [31:0] data_rdata_i;
    wire         core_halt_o;
    wire         vlsu_done_o;
    

    accelerator_top acctop0(
        .apu_result        (apu_result),
        .apu_flags_o        (apu_flag_o), //nothing returned to interface/cpu, maybe use for something else?
        .apu_gnt            (apu_gnt), //WAIT state in decoder, when gnt = 1 apu_operands_o, apu_op_o, apu_flags_o may change next cycle
        .apu_rvalid         (apu_rvalid),
        .instruction_id         (instruction_id),
        .clk        (clk_i),
        .n_reset        (rst_ni),
        .apu_req        (apu_req), // && xif_issue.issue_ready), //ready for new instructions (revisit)
        .apu_operands_i    (apu_operands_i), //this contains the funct3, major_opcode, funct6, source1, source2, destination fields
        //...of type wire [2:0][31:0];
        .offloaded_id_i     (offloaded_id_i),
        .apu_op        (apu_op), //this tells the core what apu op is required but not used within ava...
        .apu_flags_i    (apu_flags_i), //again this is meant to pass in flags, just stored and not used

        //VLSU signals
        .data_req_o        (data_req_o), //vlsu signal for in LOAD_CYCLE and STORE_CYCLE in vlsu (request)
        .data_gnt_i        (data_gnt_i), //vlsu signal, not used anywhere... (generate)
        .data_rvalid_i    (data_rvalid_i), //vlsu signal for in LOAD_WAIT and STORE_WAIT (result valid)
        .data_we_o        (data_we_o), //vlsu signal for in STORE_CYCLE (write enable?)
        .data_be_o        (data_be_o), //vlsu signal, (byte enable?)
        //= vlsu_store_i ? store_cycle_be : 4'b1111; in vlsu
        .data_addr_o    (data_addr_o), //vlsu signal, data address output
        //= vlsu_store_i ? ({cycle_addr[31:2], 2'd0} + (store_cycles_cnt << 2)) : {cycle_addr[31:2], 2'd0};
        .data_wdata_o    (data_wdata_o), //vlsu signal, (write data out), set to 0...
        .data_rdata_i    (data_rdata_i), //vlsu signal, (read data in), written to temporary reg and split into words 32bits -> 4x8bits
        
        //Core halt signal
        .core_halt_o    (core_halt_o),  //core halt to stop main core?
        
        //VLSU done signal to show final memory cycle (Load or Store)
        .vlsu_done_o    (vlsu_done_o)
    );

    //Pack the x interface
    //assign input output
   
    //COMPRESSED INTERFACE - NOT USED
    assign xif_compressed.compressed_ready = '0;
    assign xif_compressed.compressed_resp  = '0;

    //ISSUE INTERFACE
    // 20/11/21 - ID generation now exists in IF stage on core,
    assign apu_req = xif_issue.issue_valid;
    assign offloaded_if_i = xif_issue.issue_req_id;
    assign apu_operands_i [0] = xif_issue.issue_req.instr; //Contains instr
    assign apu_operands_i [1] = xif_issue.issue_req.rs[0]; //register operand 1
    assign apu_operands_i [2] = xif_issue.issue_req.rs[1]; //register operand 2
    assign xif_issue.issue_ready = apu_gnt;
    assign xif_issue.issue_resp.accept = '1; //Is copro accepted by processor?
    assign xif_issue.issue_resp.writeback = '1; //Will copro writeback?

    //COMMIT INTERFACE
    //assign ?? = xif_commit.commit_valid & ~xif_commit.commit.commit_kill;
    //assign ?? = xif_commit.commit_valid & xif_commit.commit.commit_kill;


    //RESULT INTERFACE
    //assign ?? = xif_result.result_ready; //apu result is ready...
    assign xif_result.result_valid = apu_rvalid;
    assign xif_result.result.id = instruction_id;
    assign xif_result.result.data = apu_result;
    assign xif_result.result.rd = '0;
    assign xif_result.result.we = '1;
    assign xif_result.result.float = '0;
    assign xif_result.result.exc = '0;
    assign xif_result.result.exccode = '0;
    
    // MEMORY (REQUEST/RESPONSE) INTERFACE
    assign xif_mem.mem_valid = data_req_o;
    assign xif_mem.mem_req.id = instruction_id;
    assign xif_mem.mem_req.addr = data_addr_o;
    assign xif_mem.mem_req.mode = 2'b11; // Machine-level privilege, as specified in issue interface signal from id/ex pipeline.
    assign xif_mem.mem_req.we = data_we_o;
    assign xif_mem.mem_req.size = 2'd2; //All loads and stores are 32-bit operations (Even loads take word into temp reg and then use byte enables to target specific bytes)
    assign xif_mem.mem_req.wdata = data_wdata_o;
    assign xif_mem.mem_req.last = vlsu_done_o;
    assign xif_mem.mem_req.spec = '0; //((!xif_commit.commit.commit_kill)&&(xif_commit.commit.id == xif_mem.mem_req_id))
                                        // Set to committed so that any errors coming back from CPU regarding access to mem are a real red flag
    
    
    // MEMORY RESULT INTERFACE
    assign data_rdata_i = xif_mem_result.mem_result_valid &&(xif_mem_result_mem_result.id == xif_mem.mem_req.id) ? xif_mem_result.mem_result.rdata : 32'd0;
    assign data_rvalid_i = xif_mem_result.mem_result_valid; //Signals VLSU that memory transaction (Read or write) has completed, so state machine can progress.
    // assign ?? = xif_mem_result.mem_result.err //Nothing to connect error code to, we just get incorrect operation
    // assign ?? = xif_mem_result.mem_result.id //According to spec, "Memory result transactions are provided by the CPU in the same order (with matching id) as the memory (request/response) transactions are received.", so ID can only be used to confirm this is true.
    

endmodule
