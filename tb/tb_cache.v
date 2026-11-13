`timescale 1ns / 1ps
// Directed tests for the cache in front of main memory (2 wait states):
// miss and refill, hits, dirty eviction to the same set, flush, and the
// memory's wait-state timing.
module tb_cache;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg         cpu_req = 1'b0;
    reg         cpu_we = 1'b0;
    reg  [31:0] cpu_addr = 32'd0;
    reg  [31:0] cpu_wdata = 32'd0;
    reg  [3:0]  cpu_wstrb = 4'b1111;
    wire        cpu_ready;
    wire [31:0] cpu_rdata;
    reg         flush_req = 1'b0;
    wire        flush_done;

    wire        mem_req;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_ready;
    wire [31:0] mem_rdata;

    // 4 sets x 16 bytes = 64-byte cache: addresses 64 bytes apart share a set.
    cache #(.SETS(4)) dut (
        .clk(clk), .rst(rst),
        .cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_wstrb(cpu_wstrb), .cpu_ready(cpu_ready), .cpu_rdata(cpu_rdata),
        .flush_req(flush_req), .flush_done(flush_done),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata)
    );

    main_memory #(.WORDS(256), .WAIT(2)) memory (
        .clk(clk), .rst(rst),
        .req(mem_req), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata), .wstrb(4'b1111),
        .ready(mem_ready), .rdata(mem_rdata)
    );

    integer checks = 0;
    integer errors = 0;
    integer cycles_taken;
    integer i;

    task check(input [8*24-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %08h, expected %08h", name, got, expected);
            end
        end
    endtask

    // One CPU access, held until ready, the way the core does it.
    task access(input write, input [31:0] address, input [31:0] value, output [31:0] read_value);
        begin
            @(negedge clk);
            cpu_req = 1'b1;
            cpu_we = write;
            cpu_addr = address;
            cpu_wdata = value;
            cycles_taken = 1;
            #1;
            while (!cpu_ready) begin
                @(negedge clk);
                cycles_taken = cycles_taken + 1;
                #1;
            end
            read_value = cpu_rdata;
            @(posedge clk);
            #1;
            cpu_req = 1'b0;
            cpu_we = 1'b0;
        end
    endtask

    reg [31:0] value;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            memory.mem[i] = 32'h1000_0000 + i;      // word i holds 0x1000_0000 + i
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Read miss: refill 4 words, each 2 wait states + 1 = 3 cycles, then the hit.
        access(1'b0, 32'h0000_0008, 0, value);
        check("read miss data", value, 32'h1000_0002);
        check("read miss cycles", cycles_taken, 14);
        access(1'b0, 32'h0000_000C, 0, value);
        check("read hit data", value, 32'h1000_0003);
        check("read hit cycles", cycles_taken, 1);

        // Write hit, then evict the dirty line by touching 64 bytes further on (same set).
        access(1'b1, 32'h0000_0004, 32'hAAAA_0001, value);
        check("write hit cycles", cycles_taken, 1);
        check("memory not yet written", memory.mem[1], 32'h1000_0001);
        access(1'b0, 32'h0000_0044, 0, value);
        check("conflict miss data", value, 32'h1000_0011);
        check("write-back + refill cycles", cycles_taken, 26);
        check("dirty line written back", memory.mem[1], 32'hAAAA_0001);

        // Write miss to a line that is now resident elsewhere: allocate, write, read back.
        access(1'b1, 32'h0000_0048, 32'hBBBB_0002, value);
        access(1'b0, 32'h0000_0004, 0, value);       // evicts the dirty 0x40 line
        check("reload after eviction", value, 32'hAAAA_0001);
        check("second write-back", memory.mem[18], 32'hBBBB_0002);
        access(1'b0, 32'h0000_0048, 0, value);
        check("write miss allocated", value, 32'hBBBB_0002);

        // Byte write into a cached word
        cpu_wstrb = 4'b0100;
        access(1'b1, 32'h0000_0048, 32'h00CC_0000, value);
        cpu_wstrb = 4'b1111;
        access(1'b0, 32'h0000_0048, 0, value);
        check("byte write merged", value, 32'hBBCC_0002);

        // Flush: dirty lines reach memory, every line is invalid afterwards.
        @(negedge clk);
        flush_req = 1'b1;
        while (!flush_done) @(negedge clk);
        flush_req = 1'b0;
        check("flush wrote dirty word", memory.mem[18], 32'hBBCC_0002);
        memory.mem[18] = 32'h1234_5678;              // change memory behind the cache
        access(1'b0, 32'h0000_0048, 0, value);
        check("line invalid after flush", value, 32'h1234_5678);
        check("refetch after flush is a miss", cycles_taken, 14);

        if (errors == 0) begin
            $display("PASS tb_cache: %0d checks", checks);
        end else begin
            $display("FAIL tb_cache: %0d of %0d checks failed", errors, checks);
        end
        $finish;
    end
endmodule
