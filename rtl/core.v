// Five-stage pipelined RV32I core: IF -> ID -> EX -> MEM -> WB.
//
// The core has two independent memory ports, one for instruction fetch (IF)
// and one for data (MEM). Both use the same handshake: the core holds a
// request until the memory side answers with ready. The memory system
// behind the ports decides how the two share memory, so the same core runs
// unchanged on all four memory organisations in this project.
//
// Hazards:
//   data      forwarding from EX/MEM and MEM/WB; one stall cycle for load-use
//   control   branches and jumps resolve in EX; the two younger instructions
//             are flushed (static not-taken prediction)
//   memory    fetch not ready      -> a bubble enters ID, the rest keeps going
//             data access waiting  -> IF..MEM freeze, a bubble enters WB
//   FENCE.I   waits in MEM until the memory system has made earlier stores
//             visible to instruction fetch, then refetches the next instruction
//
// Every pipeline slot carries a valid bit and, when empty, the reason it is
// empty. The reasons that reach WB add up to an exact cycle breakdown.
module core (
    input  wire        clk,
    input  wire        rst,

    // Instruction port (read only)
    output wire        i_req,
    output wire [31:0] i_addr,
    input  wire        i_ready,
    input  wire [31:0] i_rdata,

    // Data port
    output wire        d_req,
    output wire        d_we,
    output wire        d_fence,       // request is FENCE.I, not a load or store
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire [3:0]  d_wstrb,
    input  wire        d_ready,
    input  wire [31:0] d_rdata
);
    // Why a pipeline slot is empty
    localparam WHY_RESET    = 3'd1;   // pipeline still filling after reset
    localparam WHY_FETCH    = 3'd2;   // fetch not ready: memory latency, cache miss or port conflict
    localparam WHY_LOAD_USE = 3'd3;   // load-use stall
    localparam WHY_BRANCH   = 3'd4;   // flushed behind a taken branch or jump
    localparam WHY_DATA     = 3'd5;   // MEM stage waiting for the data port
    localparam WHY_FENCE    = 3'd6;   // flushed behind FENCE.I

    // Pipeline control, worked out further down
    wire        data_wait;            // MEM has a data request that is not ready yet
    wire        mem_redirect;         // FENCE.I finished in MEM
    wire        ex_redirect;          // taken branch or jump in EX
    wire        load_use_stall;
    wire [31:0] ex_target;
    reg  [31:0] ex_rs1_value;         // EX operands after forwarding
    reg  [31:0] ex_rs2_value;

    // ==================================================================
    // IF
    // ==================================================================
    wire [31:0] pc;
    reg         pc_enable;
    reg  [31:0] next_pc;

    // EX/MEM fields used by the PC logic
    reg  [31:0] ex_mem_pc;

    always @(*) begin
        pc_enable = 1'b0;
        next_pc   = pc + 32'd4;
        if (data_wait) begin
            pc_enable = 1'b0;
        end else if (mem_redirect) begin
            pc_enable = 1'b1;
            next_pc   = ex_mem_pc + 32'd4;
        end else if (ex_redirect) begin
            pc_enable = 1'b1;
            next_pc   = ex_target;
        end else if (load_use_stall) begin
            pc_enable = 1'b0;
        end else if (i_ready) begin
            pc_enable = 1'b1;
        end
    end

    program_counter u_pc (
        .clk(clk),
        .rst(rst),
        .enable(pc_enable),
        .next_pc(next_pc),
        .pc(pc)
    );

    assign i_req  = ~rst;
    assign i_addr = pc;

    // IF/ID register
    reg        if_id_valid;
    reg [2:0]  if_id_why;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    always @(posedge clk) begin
        if (rst) begin
            if_id_valid <= 1'b0;
            if_id_why   <= WHY_RESET;
        end else if (data_wait || (load_use_stall && !mem_redirect && !ex_redirect)) begin
            // hold
        end else if (mem_redirect) begin
            if_id_valid <= 1'b0;
            if_id_why   <= WHY_FENCE;
        end else if (ex_redirect) begin
            if_id_valid <= 1'b0;
            if_id_why   <= WHY_BRANCH;
        end else if (i_ready) begin
            if_id_valid <= 1'b1;
            if_id_pc    <= pc;
            if_id_instr <= i_rdata;
        end else begin
            if_id_valid <= 1'b0;
            if_id_why   <= WHY_FETCH;
        end
    end

    // ==================================================================
    // ID
    // ==================================================================
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [4:0] id_rd  = if_id_instr[11:7];

    wire       id_reg_write;
    wire       id_mem_read;
    wire       id_mem_write;
    wire       id_branch;
    wire       id_jal;
    wire       id_jalr;
    wire       id_fence_i;
    wire [1:0] id_a_sel;
    wire       id_b_sel;
    wire [3:0] id_alu_op;
    wire       id_uses_rs1;
    wire       id_uses_rs2;
    wire       id_illegal;

    control_unit u_control (
        .instr(if_id_instr),
        .reg_write(id_reg_write),
        .mem_read(id_mem_read),
        .mem_write(id_mem_write),
        .branch(id_branch),
        .jal(id_jal),
        .jalr(id_jalr),
        .fence_i(id_fence_i),
        .a_sel(id_a_sel),
        .b_sel(id_b_sel),
        .alu_op(id_alu_op),
        .uses_rs1(id_uses_rs1),
        .uses_rs2(id_uses_rs2),
        .illegal(id_illegal)
    );

    wire [31:0] id_imm;

    imm_gen u_imm_gen (
        .instr(if_id_instr),
        .imm(id_imm)
    );

    // MEM/WB fields used by the register file write port
    reg        mem_wb_valid;
    reg        mem_wb_reg_write;
    reg [4:0]  mem_wb_rd;
    reg [31:0] mem_wb_value;

    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    regfile u_regfile (
        .clk(clk),
        .we(mem_wb_valid & mem_wb_reg_write),
        .rs1(id_rs1),
        .rs2(id_rs2),
        .rd(mem_wb_rd),
        .rd_data(mem_wb_value),
        .rs1_data(id_rs1_data),
        .rs2_data(id_rs2_data)
    );

    // ID/EX register
    reg        id_ex_valid;
    reg [2:0]  id_ex_why;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_instr;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg        id_ex_reg_write;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg        id_ex_branch;
    reg        id_ex_jal;
    reg        id_ex_jalr;
    reg        id_ex_fence_i;
    reg [1:0]  id_ex_a_sel;
    reg        id_ex_b_sel;
    reg [3:0]  id_ex_alu_op;

    always @(posedge clk) begin
        if (rst) begin
            id_ex_valid <= 1'b0;
            id_ex_why   <= WHY_RESET;
        end else if (data_wait) begin
            // Hold, but keep the forwarded operands: the instruction in WB that
            // supplies one of them retires during the wait and stops forwarding.
            id_ex_rs1_data <= ex_rs1_value;
            id_ex_rs2_data <= ex_rs2_value;
        end else if (mem_redirect) begin
            id_ex_valid <= 1'b0;
            id_ex_why   <= WHY_FENCE;
        end else if (ex_redirect) begin
            id_ex_valid <= 1'b0;
            id_ex_why   <= WHY_BRANCH;
        end else if (load_use_stall) begin
            id_ex_valid <= 1'b0;
            id_ex_why   <= WHY_LOAD_USE;
        end else begin
            id_ex_valid     <= if_id_valid;
            id_ex_why       <= if_id_why;
            id_ex_pc        <= if_id_pc;
            id_ex_instr     <= if_id_instr;
            id_ex_rs1       <= id_rs1;
            id_ex_rs2       <= id_rs2;
            id_ex_rd        <= id_rd;
            id_ex_rs1_data  <= id_rs1_data;
            id_ex_rs2_data  <= id_rs2_data;
            id_ex_imm       <= id_imm;
            id_ex_reg_write <= id_reg_write;
            id_ex_mem_read  <= id_mem_read;
            id_ex_mem_write <= id_mem_write;
            id_ex_branch    <= id_branch;
            id_ex_jal       <= id_jal;
            id_ex_jalr      <= id_jalr;
            id_ex_fence_i   <= id_fence_i;
            id_ex_a_sel     <= id_a_sel;
            id_ex_b_sel     <= id_b_sel;
            id_ex_alu_op    <= id_alu_op;
        end
    end

    // ==================================================================
    // EX
    // ==================================================================
    reg         ex_mem_valid;
    reg         ex_mem_reg_write;
    reg  [4:0]  ex_mem_rd;
    reg  [31:0] ex_mem_result;

    wire [1:0] forward_a;
    wire [1:0] forward_b;

    hazard_unit u_hazard (
        .id_valid(if_id_valid),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_uses_rs1(id_uses_rs1),
        .id_uses_rs2(id_uses_rs2),
        .ex_valid(id_ex_valid),
        .ex_mem_read(id_ex_mem_read),
        .ex_rd(id_ex_rd),
        .ex_rs1(id_ex_rs1),
        .ex_rs2(id_ex_rs2),
        .mem_valid(ex_mem_valid),
        .mem_reg_write(ex_mem_reg_write),
        .mem_rd(ex_mem_rd),
        .wb_valid(mem_wb_valid),
        .wb_reg_write(mem_wb_reg_write),
        .wb_rd(mem_wb_rd),
        .load_use_stall(load_use_stall),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    always @(*) begin
        case (forward_a)
            2'b10:   ex_rs1_value = ex_mem_result;
            2'b01:   ex_rs1_value = mem_wb_value;
            default: ex_rs1_value = id_ex_rs1_data;
        endcase
        case (forward_b)
            2'b10:   ex_rs2_value = ex_mem_result;
            2'b01:   ex_rs2_value = mem_wb_value;
            default: ex_rs2_value = id_ex_rs2_data;
        endcase
    end

    reg [31:0] alu_a;

    always @(*) begin
        case (id_ex_a_sel)
            2'd1:    alu_a = id_ex_pc;
            2'd2:    alu_a = 32'd0;
            default: alu_a = ex_rs1_value;
        endcase
    end

    wire [31:0] alu_b = id_ex_b_sel ? id_ex_imm : ex_rs2_value;
    wire [31:0] alu_y;

    alu u_alu (
        .op(id_ex_alu_op),
        .a(alu_a),
        .b(alu_b),
        .y(alu_y)
    );

    reg branch_taken;

    always @(*) begin
        case (id_ex_instr[14:12])
            3'b000:  branch_taken = (ex_rs1_value == ex_rs2_value);                     // BEQ
            3'b001:  branch_taken = (ex_rs1_value != ex_rs2_value);                     // BNE
            3'b100:  branch_taken = ($signed(ex_rs1_value) <  $signed(ex_rs2_value));   // BLT
            3'b101:  branch_taken = ($signed(ex_rs1_value) >= $signed(ex_rs2_value));   // BGE
            3'b110:  branch_taken = (ex_rs1_value <  ex_rs2_value);                     // BLTU
            3'b111:  branch_taken = (ex_rs1_value >= ex_rs2_value);                     // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    assign ex_redirect = id_ex_valid && (id_ex_jal || id_ex_jalr || (id_ex_branch && branch_taken));
    assign ex_target   = id_ex_jalr ? (alu_y & ~32'd1) : (id_ex_pc + id_ex_imm);

    wire [31:0] ex_result = (id_ex_jal || id_ex_jalr) ? (id_ex_pc + 32'd4) : alu_y;

    // EX/MEM register
    reg [2:0]  ex_mem_why;
    reg [31:0] ex_mem_instr;
    reg        ex_mem_mem_read;
    reg        ex_mem_mem_write;
    reg        ex_mem_fence_i;
    reg [2:0]  ex_mem_funct3;
    reg [31:0] ex_mem_store_data;

    always @(posedge clk) begin
        if (rst) begin
            ex_mem_valid <= 1'b0;
            ex_mem_why   <= WHY_RESET;
        end else if (data_wait) begin
            // hold
        end else if (mem_redirect) begin
            ex_mem_valid <= 1'b0;
            ex_mem_why   <= WHY_FENCE;
        end else begin
            ex_mem_valid      <= id_ex_valid;
            ex_mem_why        <= id_ex_why;
            ex_mem_pc         <= id_ex_pc;
            ex_mem_instr      <= id_ex_instr;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_fence_i    <= id_ex_fence_i;
            ex_mem_funct3     <= id_ex_instr[14:12];
            ex_mem_result     <= ex_result;
            ex_mem_store_data <= ex_rs2_value;
        end
    end

    // ==================================================================
    // MEM
    // ==================================================================
    wire mem_uses_port = ex_mem_valid && (ex_mem_mem_read || ex_mem_mem_write || ex_mem_fence_i);

    assign data_wait    = mem_uses_port && !d_ready;
    assign mem_redirect = ex_mem_valid && ex_mem_fence_i && d_ready;

    wire [31:0] load_data;

    rw_control u_rw_control (
        .funct3(ex_mem_funct3),
        .byte_offset(ex_mem_result[1:0]),
        .store_data(ex_mem_store_data),
        .mem_rdata(d_rdata),
        .wstrb(d_wstrb),
        .wdata(d_wdata),
        .load_data(load_data)
    );

    assign d_req   = mem_uses_port;
    assign d_we    = ex_mem_valid && ex_mem_mem_write;
    assign d_fence = ex_mem_valid && ex_mem_fence_i;
    assign d_addr  = ex_mem_result;

    // MEM/WB register
    reg [2:0]  mem_wb_why;
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_instr;

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_valid <= 1'b0;
            mem_wb_why   <= WHY_RESET;
        end else if (data_wait) begin
            mem_wb_valid <= 1'b0;
            mem_wb_why   <= WHY_DATA;
        end else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_why       <= ex_mem_why;
            mem_wb_pc        <= ex_mem_pc;
            mem_wb_instr     <= ex_mem_instr;
            mem_wb_rd        <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_value     <= ex_mem_mem_read ? load_data : ex_mem_result;
        end
    end

    // WB: the register file write port is driven from MEM/WB above.
endmodule
