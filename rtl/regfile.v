// 32 x 32-bit register file: two read ports (ID stage), one write port
// (WB stage). x0 always reads as zero. A register written in WB is passed
// straight to a read of the same register in ID, so an instruction three
// places behind its producer needs no forwarding.
module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] regs [0:31];

    // Registers start at zero (an FPGA loads this as the initial value), so a
    // program that saves a register it never set behaves like the reference model.
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] = 32'd0;
        end
    end

    wire write_rd = we && (rd != 5'd0);

    assign rs1_data = (rs1 == 5'd0) ? 32'd0 : ((write_rd && rd == rs1) ? rd_data : regs[rs1]);
    assign rs2_data = (rs2 == 5'd0) ? 32'd0 : ((write_rd && rd == rs2) ? rd_data : regs[rs2]);

    always @(posedge clk) begin
        if (write_rd) begin
            regs[rd] <= rd_data;
        end
    end
endmodule
