// System 1, von Neumann: code and data share one memory behind one port.
// The arbiter serves the data access first, so every load or store holds
// up the fetch behind it.
module vonneumann_top #(
    parameter MEM_WAIT   = 1,        // wait states of the memory
    parameter CACHE_SETS = 64        // unused here; keeps one parameter list for all systems
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

    wire        access = d_req && !d_fence;     // load or store
    wire        access_ready;
    wire        bus_req;
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [3:0]  bus_wstrb;
    wire        bus_ready;

    mem_arbiter u_arbiter (
        .clk(clk), .rst(rst),
        .d_req(access), .d_we(d_we), .d_addr(d_addr), .d_wdata(d_wdata), .d_wstrb(d_wstrb),
        .d_ready(access_ready),
        .i_req(i_req), .i_addr(i_addr), .i_ready(i_ready),
        .mem_req(bus_req), .mem_we(bus_we), .mem_addr(bus_addr), .mem_wdata(bus_wdata),
        .mem_wstrb(bus_wstrb), .mem_ready(bus_ready)
    );

    wire sel_code;
    wire sel_data;
    wire sel_io;
    wire unmapped;

    addr_decoder u_decoder (
        .addr(bus_addr),
        .sel_code(sel_code), .sel_data(sel_data), .sel_io(sel_io), .unmapped(unmapped)
    );

    // One 32 KB memory: code in the lower half, data in the upper half.
    wire mem_req = bus_req && (sel_code || sel_data);
    wire mem_ready;
    wire [31:0] mem_rdata;

    main_memory #(.WORDS(8192), .WAIT(MEM_WAIT)) u_mem (
        .clk(clk), .rst(rst),
        .req(mem_req), .we(bus_we), .addr({17'd0, sel_data, bus_addr[13:2], 2'b00}),
        .wdata(bus_wdata), .wstrb(bus_wstrb),
        .ready(mem_ready), .rdata(mem_rdata)
    );

    assign bus_ready = mem_req ? mem_ready : bus_req;   // I/O and errors answer at once
    assign i_rdata   = mem_rdata;
    assign d_rdata   = mem_rdata;
    assign d_ready   = d_fence ? d_req : access_ready;  // FENCE.I: nothing to do, one memory
    assign out_valid = bus_req && bus_we && sel_io;
    assign out_data  = bus_wdata;
    assign bus_error = bus_req && unmapped;
endmodule
