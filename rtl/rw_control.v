// Memory read/write control for loads and stores.
//   Stores: pick the byte lanes to write (wstrb) and place the data on them.
//   Loads:  pull the addressed byte/halfword out of the word and extend it.
// shortcut: misaligned halfword/word accesses are not trapped; programs keep
// accesses aligned, as RV32I software normally does.
module rw_control (
    input  wire [2:0]  funct3,       // access size and signedness from the instruction
    input  wire [1:0]  byte_offset,  // address bits [1:0]
    input  wire [31:0] store_data,   // rs2
    input  wire [31:0] mem_rdata,    // whole word read from memory
    output reg  [3:0]  wstrb,
    output reg  [31:0] wdata,
    output reg  [31:0] load_data
);
    wire [31:0] shifted = mem_rdata >> {byte_offset, 3'b000};

    always @(*) begin
        // The data is copied onto every lane; wstrb decides which lanes are written.
        case (funct3[1:0])
            2'b00: begin                                   // SB
                wstrb = 4'b0001 << byte_offset;
                wdata = {4{store_data[7:0]}};
            end
            2'b01: begin                                   // SH
                wstrb = 4'b0011 << byte_offset;
                wdata = {2{store_data[15:0]}};
            end
            default: begin                                 // SW
                wstrb = 4'b1111;
                wdata = store_data;
            end
        endcase

        case (funct3)
            3'b000:  load_data = {{24{shifted[7]}}, shifted[7:0]};    // LB
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};  // LH
            3'b100:  load_data = {24'd0, shifted[7:0]};               // LBU
            3'b101:  load_data = {16'd0, shifted[15:0]};              // LHU
            default: load_data = mem_rdata;                           // LW
        endcase
    end
endmodule
