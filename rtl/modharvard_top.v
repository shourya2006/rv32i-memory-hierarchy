// System 3, modified Harvard: split L1 instruction and data caches in front
// of one shared main memory (the "shared lower-level memory").
//
// The core sees two ports, as in the Harvard system, and most accesses hit
// in a cache in one cycle. Only misses (and dirty-line write-backs) reach
// main memory, where an arbiter shares the single port between the caches.
//
// The D-cache can hold a store to the code region that the I-cache does not
// see. FENCE.I fixes that: it writes back every dirty D-cache line and
// invalidates the I-cache before the next instruction is fetched.
module modharvard_top #(
    parameter MEM_WAIT   = 1,        // wait states of main memory
    parameter CACHE_SETS = 64        // sets per L1 cache (64 x 16 B = 1 KB each)
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

    wire fence_req = d_req && d_fence;

    // L1 instruction cache
    wire        ic_mem_req;
    wire        ic_mem_we;
    wire [31:0] ic_mem_addr;
    wire [31:0] ic_mem_wdata;
    wire        ic_mem_ready;
    wire        ic_flushed;
    wire [31:0] mem_rdata;

    cache #(.SETS(CACHE_SETS)) u_icache (
        .clk(clk), .rst(rst),
        .cpu_req(i_req), .cpu_we(1'b0), .cpu_addr(i_addr), .cpu_wdata(32'd0), .cpu_wstrb(4'b0000),
        .cpu_ready(i_ready), .cpu_rdata(i_rdata),
        .flush_req(fence_req), .flush_done(ic_flushed),
        .mem_req(ic_mem_req), .mem_we(ic_mem_we), .mem_addr(ic_mem_addr), .mem_wdata(ic_mem_wdata),
        .mem_ready(ic_mem_ready), .mem_rdata(mem_rdata)
    );

    // Data side: the I/O page bypasses the D-cache
    wire sel_code;
    wire sel_data;
    wire sel_io;
    wire unmapped;

    addr_decoder u_decoder (
        .addr(d_addr),
        .sel_code(sel_code), .sel_data(sel_data), .sel_io(sel_io), .unmapped(unmapped)
    );

    wire access     = d_req && !d_fence;        // load or store
    wire dcache_req = access && (sel_code || sel_data);
    wire dcache_ready;
    wire dc_flushed;

    // L1 data cache
    wire        dc_mem_req;
    wire        dc_mem_we;
    wire [31:0] dc_mem_addr;
    wire [31:0] dc_mem_wdata;
    wire        dc_mem_ready;

    cache #(.SETS(CACHE_SETS)) u_dcache (
        .clk(clk), .rst(rst),
        .cpu_req(dcache_req), .cpu_we(d_we), .cpu_addr(d_addr), .cpu_wdata(d_wdata), .cpu_wstrb(d_wstrb),
        .cpu_ready(dcache_ready), .cpu_rdata(d_rdata),
        .flush_req(fence_req), .flush_done(dc_flushed),
        .mem_req(dc_mem_req), .mem_we(dc_mem_we), .mem_addr(dc_mem_addr), .mem_wdata(dc_mem_wdata),
        .mem_ready(dc_mem_ready), .mem_rdata(mem_rdata)
    );

    assign d_ready = fence_req  ? (ic_flushed && dc_flushed) :
                     dcache_req ? dcache_ready : d_req;    // I/O and errors answer at once
    assign out_valid = access && d_we && sel_io;
    assign out_data  = d_wdata;
    assign bus_error = access && unmapped;

    // Shared main memory behind both caches
    wire        bus_req;
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [3:0]  bus_wstrb;
    wire        bus_ready;

    mem_arbiter u_arbiter (
        .clk(clk), .rst(rst),
        .d_req(dc_mem_req), .d_we(dc_mem_we), .d_addr(dc_mem_addr), .d_wdata(dc_mem_wdata),
        .d_wstrb(4'b1111), .d_ready(dc_mem_ready),
        .i_req(ic_mem_req), .i_addr(ic_mem_addr), .i_ready(ic_mem_ready),
        .mem_req(bus_req), .mem_we(bus_we), .mem_addr(bus_addr), .mem_wdata(bus_wdata),
        .mem_wstrb(bus_wstrb), .mem_ready(bus_ready)
    );

    wire bus_sel_code;
    wire bus_sel_data;
    wire bus_sel_io;
    wire bus_unmapped;

    addr_decoder u_mem_decoder (
        .addr(bus_addr),
        .sel_code(bus_sel_code), .sel_data(bus_sel_data), .sel_io(bus_sel_io), .unmapped(bus_unmapped)
    );

    // One 32 KB memory: code in the lower half, data in the upper half.
    main_memory #(.WORDS(8192), .WAIT(MEM_WAIT)) u_mem (
        .clk(clk), .rst(rst),
        .req(bus_req), .we(bus_we), .addr({17'd0, bus_sel_data, bus_addr[13:2], 2'b00}),
        .wdata(bus_wdata), .wstrb(bus_wstrb),
        .ready(bus_ready), .rdata(mem_rdata)
    );
endmodule
