// Two-master arbiter in front of one memory port.
//
// The data side (master D) wins when both ask in the same cycle: its
// request belongs to the older instruction, and the fetch can wait. Once a
// transfer has started and is still waiting for ready, the port stays with
// that master until the transfer completes, so a multi-cycle access is
// never cut off halfway.
module mem_arbiter (
    input  wire        clk,
    input  wire        rst,

    // Master D: data side
    input  wire        d_req,
    input  wire        d_we,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    input  wire [3:0]  d_wstrb,
    output wire        d_ready,

    // Master I: instruction side (read only)
    input  wire        i_req,
    input  wire [31:0] i_addr,
    output wire        i_ready,

    // Shared port
    output wire        mem_req,
    output wire        mem_we,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    output wire [3:0]  mem_wstrb,
    input  wire        mem_ready
);
    reg locked;                       // a transfer is in progress
    reg locked_to_i;                  // ... and it belongs to the instruction side

    wire grant_d = locked ? !locked_to_i : d_req;
    wire grant_i = locked ? locked_to_i  : (!d_req && i_req);

    assign mem_req   = (grant_d && d_req) || (grant_i && i_req);
    assign mem_we    = grant_d && d_we;
    assign mem_addr  = grant_d ? d_addr : i_addr;
    assign mem_wdata = d_wdata;
    assign mem_wstrb = d_wstrb;

    assign d_ready = grant_d && mem_ready;
    assign i_ready = grant_i && mem_ready;

    always @(posedge clk) begin
        if (rst) begin
            locked      <= 1'b0;
            locked_to_i <= 1'b0;
        end else begin
            locked      <= mem_req && !mem_ready;
            locked_to_i <= grant_i;
        end
    end
endmodule
