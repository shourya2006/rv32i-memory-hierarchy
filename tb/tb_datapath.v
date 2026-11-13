`timescale 1ns / 1ps
// Directed tests for the datapath blocks: alu, regfile, program_counter,
// imm_gen and control_unit.
module tb_datapath;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [3:0]  op;
    reg  [31:0] a;
    reg  [31:0] b;
    wire [31:0] y;

    alu u_alu (
        .op(op),
        .a(a),
        .b(b),
        .y(y)
    );

    reg         we = 1'b0;
    reg  [4:0]  rs1;
    reg  [4:0]  rs2;
    reg  [4:0]  rd;
    reg  [31:0] rd_data;
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;

    regfile u_regfile (
        .clk(clk),
        .we(we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .rd_data(rd_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    reg         rst;
    reg         enable;
    reg  [31:0] next_pc;
    wire [31:0] pc;

    program_counter u_pc (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .next_pc(next_pc),
        .pc(pc)
    );

    reg  [31:0] instr;
    wire [31:0] imm;
    wire        reg_write;
    wire        mem_read;
    wire        mem_write;
    wire        fence_i;
    wire [3:0]  ctrl_alu_op;
    wire        uses_rs2;
    wire        illegal;

    imm_gen u_imm_gen (
        .instr(instr),
        .imm(imm)
    );

    control_unit u_control (
        .instr(instr),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .branch(), .jal(), .jalr(), .fence_i(fence_i),
        .a_sel(), .b_sel(), .alu_op(ctrl_alu_op), .uses_rs1(), .uses_rs2(uses_rs2),
        .illegal(illegal)
    );

    integer checks = 0;
    integer errors = 0;

    task check(input [8*16-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %08h, expected %08h", name, got, expected);
            end
        end
    endtask

    task alu_case(input [3:0] operation, input [31:0] x, input [31:0] z, input [31:0] expected);
        begin
            op = operation;
            a = x;
            b = z;
            #1;
            check("alu", y, expected);
        end
    endtask

    initial begin
        alu_case(4'b0000, 5, -3, 2);                                     // ADD
        alu_case(4'b1000, 5, -3, 8);                                     // SUB
        alu_case(4'b0001, 1, 31, 32'h8000_0000);                         // SLL
        alu_case(4'b0001, 1, 33, 2);                                     // shift uses b[4:0] only
        alu_case(4'b0010, -3, 5, 1);                                     // SLT
        alu_case(4'b0011, -3, 5, 0);                                     // SLTU
        alu_case(4'b0100, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'h0FF0_0FF0);  // XOR
        alu_case(4'b0101, 32'h8000_0000, 4, 32'h0800_0000);              // SRL
        alu_case(4'b1101, 32'h8000_0000, 4, 32'hF800_0000);              // SRA
        alu_case(4'b0110, 32'hF0F0_0000, 32'h0000_0F0F, 32'hF0F0_0F0F);  // OR
        alu_case(4'b0111, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'hF000_F000);  // AND

        // Register file: x5 keeps a write, x0 ignores one.
        @(negedge clk);
        we = 1'b1;
        rd = 5'd5;
        rd_data = 32'h1234_5678;
        @(negedge clk);
        rd = 5'd0;
        rd_data = 32'hFFFF_FFFF;
        @(negedge clk);
        we = 1'b0;
        rs1 = 5'd5;
        rs2 = 5'd0;
        #1;
        check("x5", rs1_data, 32'h1234_5678);
        check("x0", rs2_data, 32'd0);

        // Program counter: reset, load, then hold while enable is low.
        rst = 1'b1;
        enable = 1'b0;
        next_pc = 32'h0000_0040;
        @(negedge clk);
        check("pc reset", pc, 32'd0);
        rst = 1'b0;
        enable = 1'b1;
        @(negedge clk);
        check("pc load", pc, 32'h0000_0040);
        enable = 1'b0;
        next_pc = 32'h0000_0080;
        @(negedge clk);
        check("pc hold", pc, 32'h0000_0040);

        // Register file: a register written in WB reads back in the same cycle.
        @(negedge clk);
        we = 1'b1;
        rd = 5'd9;
        rd_data = 32'hCAFE_0009;
        rs1 = 5'd9;
        #1;
        check("WB bypass", rs1_data, 32'hCAFE_0009);
        @(negedge clk);
        we = 1'b0;

        // Immediates, one per format
        instr = 32'hFFB0_0093; #1;                // addi x1, x0, -5        (I)
        check("imm I", imm, 32'hFFFF_FFFB);
        instr = 32'hFE55_2C23; #1;                // sw x5, -8(x10)         (S)
        check("imm S", imm, 32'hFFFF_FFF8);
        instr = 32'hFE20_9EE3; #1;                // bne x1, x2, -4         (B)
        check("imm B", imm, 32'hFFFF_FFFC);
        instr = 32'h1000_0537; #1;                // lui x10, 0x10000       (U)
        check("imm U", imm, 32'h1000_0000);
        instr = 32'hFFDF_F0EF; #1;                // jal ra, -4             (J)
        check("imm J", imm, 32'hFFFF_FFFC);

        // Control signals
        instr = 32'h0000_2283; #1;                // lw x5, 0(x0)
        check("lw controls", {reg_write, mem_read, mem_write}, 3'b110);
        instr = 32'h0055_2223; #1;                // sw x5, 4(x10)
        check("sw controls", {reg_write, mem_write, uses_rs2}, 3'b011);
        instr = 32'h4020_81B3; #1;                // sub x3, x1, x2
        check("sub op", ctrl_alu_op, 4'b1000);
        instr = 32'h4032_D293; #1;                // srai x5, x5, 3
        check("srai op", ctrl_alu_op, 4'b1101);
        instr = 32'h4000_0093; #1;                // addi x1, x0, 1024: bit 30 is immediate, not SUB
        check("addi with bit 30", ctrl_alu_op, 4'b0000);
        instr = 32'h0000_100F; #1;                // fence.i
        check("fence.i", {fence_i, reg_write}, 2'b10);
        instr = 32'h0000_0000; #1;                // all zeros is not an instruction
        check("illegal", {illegal, reg_write, mem_write}, 3'b100);

        if (errors == 0) begin
            $display("PASS tb_datapath: %0d checks", checks);
        end else begin
            $display("FAIL tb_datapath: %0d of %0d checks failed", errors, checks);
        end
        $finish;
    end
endmodule
