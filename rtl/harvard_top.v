// System 2, Harvard: instruction memory and data memory are separate, each
// with its own port, so a fetch and a data access proceed in the same cycle.
// The data side has no path to instruction memory: a load or store to the
// code region is a bus error.
module harvard_top #(
    parameter MEM_WAIT   = 1,        // wait states of each memory
    parameter CACHE_SETS = 64,       // unused here; keeps one parameter list for all systems
    parameter PROGRAM    = ""        // hex file for the instruction ROM (synthesis needs its contents)
) (
    input  wire        clk,
    input  wire        rst,
    output wire        out_valid,    // store to the I/O page this cycle
    output wire [31:0] out_data,
    output wire        bus_error
);
    wire        i_req;
    wire [31:0] i_addr;
    wire        i_ready;
    wire [31:0] i_rdata;
    wire        d_req;
    wire        d_we;
    wire        d_fence;
    wire [31:0] d_addr;
    wire [31:0] d_wdata;
    wire [3:0]  d_wstrb;
    wire        d_ready;
    wire [31:0] d_rdata;

    core u_core (
        .clk(clk), .rst(rst),
        .i_req(i_req), .i_addr(i_addr), .i_ready(i_ready), .i_rdata(i_rdata),
        .d_req(d_req), .d_we(d_we), .d_fence(d_fence), .d_addr(d_addr),
        .d_wdata(d_wdata), .d_wstrb(d_wstrb), .d_ready(d_ready), .d_rdata(d_rdata)
    );

    // Instruction side: its own memory, read only
    main_memory #(.WORDS(4096), .WAIT(MEM_WAIT), .INIT_FILE(PROGRAM)) u_imem (
        .clk(clk), .rst(rst),
        .req(i_req), .we(1'b0), .addr(i_addr), .wdata(32'd0), .wstrb(4'b0000),
        .ready(i_ready), .rdata(i_rdata)
    );

    // Data side
    wire sel_code;
    wire sel_data;
    wire sel_io;
    wire unmapped;

    addr_decoder u_decoder (
        .addr(d_addr),
        .sel_code(sel_code), .sel_data(sel_data), .sel_io(sel_io), .unmapped(unmapped)
    );

    wire access   = d_req && !d_fence;          // load or store
    wire dmem_req = access && sel_data;
    wire dmem_ready;

    main_memory #(.WORDS(4096), .WAIT(MEM_WAIT)) u_dmem (
        .clk(clk), .rst(rst),
        .req(dmem_req), .we(d_we), .addr(d_addr), .wdata(d_wdata), .wstrb(d_wstrb),
        .ready(dmem_ready), .rdata(d_rdata)
    );

    // FENCE.I has nothing to do here (no caches); I/O and errors answer at once.
    assign d_ready   = dmem_req ? dmem_ready : d_req;
    assign out_valid = access && d_we && sel_io;
    assign out_data  = d_wdata;
    assign bus_error = access && (sel_code || unmapped);
endmodule
