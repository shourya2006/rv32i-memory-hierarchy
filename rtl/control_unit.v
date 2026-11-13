// Control unit (ID stage): turns one RV32I instruction into the control
// signals that the EX, MEM and WB stages use.
module control_unit (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output reg         fence_i,
    output reg  [1:0]  a_sel,        // ALU input A: 0 = rs1, 1 = pc, 2 = zero
    output reg         b_sel,        // ALU input B: 0 = rs2, 1 = immediate
    output reg  [3:0]  alu_op,       // {instr[30], funct3}, see alu.v
    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         illegal
);
    localparam A_RS1  = 2'd0;
    localparam A_PC   = 2'd1;
    localparam A_ZERO = 2'd2;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @(*) begin
        reg_write = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;
        fence_i   = 1'b0;
        a_sel     = A_RS1;
        b_sel     = 1'b1;
        alu_op    = 4'b0000;             // ADD: addresses, LUI, AUIPC
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        illegal   = 1'b0;

        case (opcode)
            7'b0110111: begin                                   // LUI
                reg_write = 1'b1;
                a_sel     = A_ZERO;
            end
            7'b0010111: begin                                   // AUIPC
                reg_write = 1'b1;
                a_sel     = A_PC;
            end
            7'b1101111: begin                                   // JAL
                reg_write = 1'b1;
                jal       = 1'b1;
            end
            7'b1100111: begin                                   // JALR
                reg_write = 1'b1;
                jalr      = 1'b1;
                uses_rs1  = 1'b1;
            end
            7'b1100011: begin                                   // BEQ ... BGEU
                branch   = 1'b1;
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                illegal  = (funct3 == 3'b010) || (funct3 == 3'b011);
            end
            7'b0000011: begin                                   // LB ... LHU
                reg_write = 1'b1;
                mem_read  = 1'b1;
                uses_rs1  = 1'b1;
                illegal   = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
            end
            7'b0100011: begin                                   // SB, SH, SW
                mem_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                illegal   = (funct3 > 3'b010);
            end
            7'b0010011: begin                                   // ADDI ... SRAI
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                // instr[30] only selects SRAI over SRLI; elsewhere it is immediate bits.
                alu_op    = {instr[30] & (funct3 == 3'b101), funct3};
            end
            7'b0110011: begin                                   // ADD ... AND
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                b_sel     = 1'b0;
                alu_op    = {instr[30], funct3};
                illegal   = !(funct7 == 7'b0000000 ||
                              (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)));
            end
            7'b0001111: begin                                   // FENCE (no-op here), FENCE.I
                fence_i = (funct3 == 3'b001);
            end
            default: begin
                illegal = 1'b1;
            end
        endcase

        // An illegal instruction flows down the pipeline as a no-op.
        if (illegal) begin
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b0;
        end
    end
endmodule
