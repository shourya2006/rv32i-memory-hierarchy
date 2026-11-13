`timescale 1ns / 1ps
// Directed tests for the interconnect: the address decoder (region edges
// and holes) and the arbiter (data first, and a started transfer keeps the
// port until it completes).
module tb_interconnect;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg  [31:0] addr;
    wire        sel_code;
    wire        sel_data;
    wire        sel_io;
    wire        unmapped;

    addr_decoder decoder (
        .addr(addr),
        .sel_code(sel_code), .sel_data(sel_data), .sel_io(sel_io), .unmapped(unmapped)
    );

    reg         d_req = 1'b0;
    reg         i_req = 1'b0;
    wire        d_ready;
    wire        i_ready;
    wire        mem_req;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_ready;
    wire [31:0] mem_rdata;

    mem_arbiter arbiter (
        .clk(clk), .rst(rst),
        .d_req(d_req), .d_we(1'b0), .d_addr(32'h0000_0100), .d_wdata(32'd0), .d_wstrb(4'b0000),
        .d_ready(d_ready),
        .i_req(i_req), .i_addr(32'h0000_0040), .i_ready(i_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready)
    );

    // A memory with 2 wait states behind the arbiter
    main_memory #(.WORDS(256), .WAIT(2)) memory (
        .clk(clk), .rst(rst),
        .req(mem_req), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata), .wstrb(mem_wstrb),
        .ready(mem_ready), .rdata(mem_rdata)
    );

    integer checks = 0;
    integer errors = 0;

    task check(input [8*28-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %h, expected %h", name, got, expected);
            end
        end
    endtask

    // expected = {sel_code, sel_data, sel_io, unmapped}
    task decode_case(input [31:0] address, input [3:0] expected);
        begin
            addr = address;
            #1;
            check("decode", {sel_code, sel_data, sel_io, unmapped}, expected);
        end
    endtask

    initial begin
        decode_case(32'h0000_0000, 4'b1000);   // first code word
        decode_case(32'h0000_3FFC, 4'b1000);   // last code word
        decode_case(32'h0000_4000, 4'b0001);   // just past code
        decode_case(32'h0FFF_FFFC, 4'b0001);   // just below data
        decode_case(32'h1000_0000, 4'b0100);   // first data word
        decode_case(32'h1000_3FFC, 4'b0100);   // last data word (stack top)
        decode_case(32'h1000_4000, 4'b0001);   // just past data
        decode_case(32'h2000_0000, 4'b0010);   // output port
        decode_case(32'h2000_0FFC, 4'b0010);
        decode_case(32'h2000_1000, 4'b0001);
        decode_case(32'hFFFF_FFFC, 4'b0001);

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // The fetch asks alone: it gets the port and its transfer starts.
        @(negedge clk);
        i_req = 1'b1;
        #1;
        check("fetch alone granted", mem_addr, 32'h0000_0040);

        // One cycle in, the data side asks: the started fetch keeps the port.
        @(negedge clk);
        d_req = 1'b1;
        #1;
        check("started fetch keeps the port", mem_addr, 32'h0000_0040);
        check("data waits", d_ready, 1'b0);
        @(negedge clk);
        #1;
        check("fetch ready after 2 waits", i_ready, 1'b1);
        check("data still waits", d_ready, 1'b0);

        // The fetch is done: the waiting data access goes next.
        @(negedge clk);
        #1;
        check("then the data side", mem_addr, 32'h0000_0100);
        check("fetch now waits", i_ready, 1'b0);

        // Both ask from idle: the data side wins.
        d_req = 1'b0;
        i_req = 1'b0;
        @(negedge clk);
        @(negedge clk);
        d_req = 1'b1;
        i_req = 1'b1;
        #1;
        check("data first from idle", mem_addr, 32'h0000_0100);

        if (errors == 0) begin
            $display("PASS tb_interconnect: %0d checks", checks);
        end else begin
            $display("FAIL tb_interconnect: %0d of %0d checks failed", errors, checks);
        end
        $finish;
    end
endmodule
