// System 4, unified cache: one L1 cache, twice the size of each split
// cache, holds both instructions and data. It is the von Neumann idea one
// level up: the fetch and the data access compete for the cache port every
// cycle, even when both would hit.
module unicache_top #(
    parameter MEM_WAIT   = 1,        // wait states of main memory
    parameter CACHE_SETS = 64        // the unified cache gets 2 x CACHE_SETS sets
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

    // The I/O page bypasses the cache
    wire sel_code;
    wire sel_data;
    wire sel_io;
    wire unmapped;

    addr_decoder u_decoder (
        .addr(d_addr),
        .sel_code(sel_code), .sel_data(sel_data), .sel_io(sel_io), .unmapped(unmapped)
    );

    wire access       = d_req && !d_fence;      // load or store
    wire cached_data  = access && (sel_code || sel_data);
    wire cached_ready;

    // Arbiter in front of the single cache port
    wire        c_req;
    wire        c_we;
    wire [31:0] c_addr;
    wire [31:0] c_wdata;
    wire [3:0]  c_wstrb;
    wire        c_ready;
    wire [31:0] c_rdata;

    mem_arbiter u_arbiter (
        .clk(clk), .rst(rst),
        .d_req(cached_data), .d_we(d_we), .d_addr(d_addr), .d_wdata(d_wdata), .d_wstrb(d_wstrb),
        .d_ready(cached_ready),
        .i_req(i_req), .i_addr(i_addr), .i_ready(i_ready),
        .mem_req(c_req), .mem_we(c_we), .mem_addr(c_addr), .mem_wdata(c_wdata),
        .mem_wstrb(c_wstrb), .mem_ready(c_ready)
    );

    wire        m_req;
    wire        m_we;
    wire [31:0] m_addr;
    wire [31:0] m_wdata;
    wire        m_ready;
    wire [31:0] m_rdata;

    cache #(.SETS(2 * CACHE_SETS)) u_cache (
        .clk(clk), .rst(rst),
        .cpu_req(c_req), .cpu_we(c_we), .cpu_addr(c_addr), .cpu_wdata(c_wdata), .cpu_wstrb(c_wstrb),
        .cpu_ready(c_ready), .cpu_rdata(c_rdata),
        .flush_req(1'b0), .flush_done(),
        .mem_req(m_req), .mem_we(m_we), .mem_addr(m_addr), .mem_wdata(m_wdata),
        .mem_ready(m_ready), .mem_rdata(m_rdata)
    );

    assign i_rdata   = c_rdata;
    assign d_rdata   = c_rdata;
    // FENCE.I has nothing to do: one cache holds both views. I/O and errors answer at once.
    assign d_ready   = cached_data ? cached_ready : d_req;
    assign out_valid = access && d_we && sel_io;
    assign out_data  = d_wdata;
    assign bus_error = access && unmapped;

    wire m_sel_code;
    wire m_sel_data;
    wire m_sel_io;
    wire m_unmapped;

    addr_decoder u_mem_decoder (
        .addr(m_addr),
        .sel_code(m_sel_code), .sel_data(m_sel_data), .sel_io(m_sel_io), .unmapped(m_unmapped)
    );

    // One 32 KB memory: code in the lower half, data in the upper half.
    main_memory #(.WORDS(8192), .WAIT(MEM_WAIT)) u_mem (
        .clk(clk), .rst(rst),
        .req(m_req), .we(m_we), .addr({17'd0, m_sel_data, m_addr[13:2], 2'b00}),
        .wdata(m_wdata), .wstrb(4'b1111),
        .ready(m_ready), .rdata(m_rdata)
    );
endmodule
