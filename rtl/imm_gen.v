// Immediate generator (ID stage): builds the sign-extended immediate for
// each RV32I instruction format.
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    always @(*) begin
        case (instr[6:0])
            7'b0100011:                                          // S-type: stores
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011:                                          // B-type: branches
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            7'b0110111, 7'b0010111:                              // U-type: LUI, AUIPC
                imm = {instr[31:12], 12'd0};
            7'b1101111:                                          // J-type: JAL
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default:                                             // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
        endcase
    end
endmodule
