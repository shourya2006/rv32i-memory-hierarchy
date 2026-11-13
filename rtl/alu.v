// ALU. The op code is {instr[30], funct3}, the same bits RISC-V uses for
// R-type instructions, so the decoder needs no lookup table.
module alu (
    input  wire [3:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);
    wire [4:0] shamt = b[4:0];

    always @(*) begin
        case (op)
            4'b0000: y = a + b;                                          // ADD
            4'b1000: y = a - b;                                          // SUB
            4'b0001: y = a << shamt;                                     // SLL
            4'b0010: y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;      // SLT
            4'b0011: y = (a < b) ? 32'd1 : 32'd0;                        // SLTU
            4'b0100: y = a ^ b;                                          // XOR
            4'b0101: y = a >> shamt;                                     // SRL
            4'b1101: y = $signed(a) >>> shamt;                           // SRA
            4'b0110: y = a | b;                                          // OR
            4'b0111: y = a & b;                                          // AND
            default: y = 32'd0;
        endcase
    end
endmodule
