// Program counter. Holds its value when enable is low (fetch stalled).
module program_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [31:0] next_pc,
    output reg  [31:0] pc
);
    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h0000_0000;
        end else if (enable) begin
            pc <= next_pc;
        end
    end
endmodule
