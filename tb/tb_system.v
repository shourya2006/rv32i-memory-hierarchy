`timescale 1ns / 1ps
// System testbench: runs one program on one of the four systems.
//
//   -DTOP=vonneumann_top
//   -DTOP=harvard_top    -DSYS_HARVARD
//   -DTOP=modharvard_top -DSYS_SPLIT_CACHE
//   -DTOP=unicache_top   -DSYS_UNIFIED_CACHE
//
// Parameters (iverilog -P tb_system.NAME=value): MEM_WAIT, CACHE_SETS.
// Plusargs: +CODE=<hex> (required), +DATA=<hex>, +VCD=<file>,
//           +LOG (commit log for the golden-model comparison), +TRACE (pipeline trace).
//
// A program ends when the halt loop "j ." reaches WB.
module tb_system;
    parameter MEM_WAIT   = 1;
    parameter CACHE_SETS = 64;

    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;             // 100 MHz

    wire        out_valid;
    wire [31:0] out_data;
    wire        bus_error;

    `TOP #(.MEM_WAIT(MEM_WAIT), .CACHE_SETS(CACHE_SETS)) dut (
        .clk(clk),
        .rst(rst),
        .out_valid(out_valid),
        .out_data(out_data),
        .bus_error(bus_error)
    );

    // ------------------------------------------------------------------
    // Program loading
    // ------------------------------------------------------------------
    reg [8*1024-1:0] code_file;
    reg [8*1024-1:0] data_file;
    reg [8*1024-1:0] vcd_file;
    reg             log_commits;
    reg             trace;
    integer         i;

    initial begin
        if (!$value$plusargs("CODE=%s", code_file)) begin
            $display("ERROR missing +CODE=<file.hex>");
            $finish;
        end
`ifdef SYS_HARVARD
        for (i = 0; i < 4096; i = i + 1) begin
            dut.u_imem.mem[i] = 32'd0;
            dut.u_dmem.mem[i] = 32'd0;
        end
        $readmemh(code_file, dut.u_imem.mem);
        if ($value$plusargs("DATA=%s", data_file)) $readmemh(data_file, dut.u_dmem.mem);
`else
        for (i = 0; i < 8192; i = i + 1) begin
            dut.u_mem.mem[i] = 32'd0;
        end
        $readmemh(code_file, dut.u_mem.mem);
        if ($value$plusargs("DATA=%s", data_file)) $readmemh(data_file, dut.u_mem.mem, 4096);
`endif
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_system);
        end
        log_commits = $test$plusargs("LOG");
        trace       = $test$plusargs("TRACE");
        repeat (3) @(negedge clk);
        rst = 1'b0;
    end

    // ------------------------------------------------------------------
    // Counters
    // ------------------------------------------------------------------
    integer cycles       = 0;
    integer instret      = 0;
    integer why_reset    = 0;
    integer why_fetch    = 0;
    integer why_load_use = 0;
    integer why_branch   = 0;
    integer why_data     = 0;
    integer why_fence    = 0;
    integer loads        = 0;
    integer stores       = 0;
    integer mem_reads    = 0;
    integer mem_writes   = 0;
    integer i_blocked    = 0;   // cycles the instruction side waited because the data side had the shared port
    integer ic_access    = 0;
    integer ic_miss      = 0;
    integer dc_access    = 0;
    integer dc_miss      = 0;
    integer dc_writeback = 0;

    wire        wb_valid = dut.u_core.mem_wb_valid;
    wire [31:0] wb_instr = dut.u_core.mem_wb_instr;
    wire        halted   = wb_valid && (wb_instr == 32'h0000_006F);

    // Flags an illegal instruction reaching WB (usually: ran off the end of the program).
    wire wb_illegal;
    control_unit u_check (
        .instr(wb_instr),
        .reg_write(), .mem_read(), .mem_write(), .branch(), .jal(), .jalr(), .fence_i(),
        .a_sel(), .b_sel(), .alu_op(), .uses_rs1(), .uses_rs2(),
        .illegal(wb_illegal)
    );

    task report;
        begin
            $display("RESULT cycles=%0d instret=%0d why_reset=%0d why_fetch=%0d why_load_use=%0d why_branch=%0d why_data=%0d why_fence=%0d loads=%0d stores=%0d mem_reads=%0d mem_writes=%0d i_blocked=%0d ic_access=%0d ic_miss=%0d dc_access=%0d dc_miss=%0d dc_writeback=%0d",
                     cycles, instret, why_reset, why_fetch, why_load_use, why_branch, why_data, why_fence,
                     loads, stores, mem_reads, mem_writes, i_blocked,
                     ic_access, ic_miss, dc_access, dc_miss, dc_writeback);
        end
    endtask

    wire d_done = dut.u_core.d_req && dut.u_core.d_ready && !dut.u_core.d_fence;

    always @(posedge clk) begin
        if (!rst) begin
            if (halted) begin
                report;
                $finish;
            end

            // One WB slot per cycle: it either retires an instruction or shows why it is empty.
            cycles = cycles + 1;
            if (wb_valid) begin
                instret = instret + 1;
                if (wb_illegal || ^wb_instr === 1'bx) begin
                    $display("ERROR illegal instruction %08h retired at pc=%08h", wb_instr, dut.u_core.mem_wb_pc);
                    $finish;
                end
                if (log_commits) begin
                    if (dut.u_core.mem_wb_reg_write && dut.u_core.mem_wb_rd != 5'd0) begin
                        $display("C %08h %0d %08h", dut.u_core.mem_wb_pc, dut.u_core.mem_wb_rd, dut.u_core.mem_wb_value);
                    end else begin
                        $display("C %08h 0 00000000", dut.u_core.mem_wb_pc);
                    end
                end
            end else begin
                case (dut.u_core.mem_wb_why)
                    3'd1: why_reset    = why_reset + 1;
                    3'd2: why_fetch    = why_fetch + 1;
                    3'd3: why_load_use = why_load_use + 1;
                    3'd4: why_branch   = why_branch + 1;
                    3'd5: why_data     = why_data + 1;
                    3'd6: why_fence    = why_fence + 1;
                    default: begin
                        $display("ERROR empty WB slot without a reason");
                        $finish;
                    end
                endcase
            end

            if (d_done && !dut.u_core.d_we) loads = loads + 1;
            if (d_done && dut.u_core.d_we) begin
                stores = stores + 1;
                if (log_commits) begin
                    $display("S %08h %1h %08h", dut.u_core.d_addr, dut.u_core.d_wstrb,
                             dut.u_core.d_wdata & {{8{dut.u_core.d_wstrb[3]}}, {8{dut.u_core.d_wstrb[2]}},
                                                   {8{dut.u_core.d_wstrb[1]}}, {8{dut.u_core.d_wstrb[0]}}});
                end
            end

`ifdef SYS_HARVARD
            if (dut.u_imem.req && dut.u_imem.ready) mem_reads = mem_reads + 1;
            if (dut.u_dmem.req && dut.u_dmem.ready) begin
                if (dut.u_dmem.we) mem_writes = mem_writes + 1;
                else               mem_reads  = mem_reads + 1;
            end
`else
            if (dut.u_mem.req && dut.u_mem.ready) begin
                if (dut.u_mem.we) mem_writes = mem_writes + 1;
                else              mem_reads  = mem_reads + 1;
            end
            if (dut.u_arbiter.i_req && !dut.u_arbiter.grant_i) i_blocked = i_blocked + 1;
`endif
`ifdef SYS_SPLIT_CACHE
            if (dut.u_icache.cpu_ready)       ic_access    = ic_access + 1;
            if (dut.u_icache.miss_start)      ic_miss      = ic_miss + 1;
            if (dut.u_dcache.cpu_ready)       dc_access    = dc_access + 1;
            if (dut.u_dcache.miss_start)      dc_miss      = dc_miss + 1;
            if (dut.u_dcache.writeback_start) dc_writeback = dc_writeback + 1;
`endif
`ifdef SYS_UNIFIED_CACHE
            // One cache: its accesses and misses are reported in the D-cache columns.
            if (dut.u_cache.cpu_ready)        dc_access    = dc_access + 1;
            if (dut.u_cache.miss_start)       dc_miss      = dc_miss + 1;
            if (dut.u_cache.writeback_start)  dc_writeback = dc_writeback + 1;
`endif

            if (trace) begin
                $display("T %0d if=%08h ir=%0d id=%0d:%08h ex=%0d:%08h mem=%0d:%08h wb=%0d:%08h why=%0d dreq=%0d drdy=%0d iblk=%0d",
                         cycles, dut.u_core.pc, dut.u_core.i_ready,
                         dut.u_core.if_id_valid, dut.u_core.if_id_pc,
                         dut.u_core.id_ex_valid, dut.u_core.id_ex_pc,
                         dut.u_core.ex_mem_valid, dut.u_core.ex_mem_pc,
                         wb_valid, dut.u_core.mem_wb_pc, dut.u_core.mem_wb_why,
                         dut.u_core.d_req, dut.u_core.d_ready,
`ifdef SYS_HARVARD
                         1'b0);
`else
                         dut.u_arbiter.i_req && !dut.u_arbiter.grant_i);
`endif
            end
            if (out_valid) begin
                $display("OUT %08h", out_data);
            end
            if (bus_error) begin
                $display("BUS_ERROR addr=%08h pc=%08h", dut.u_core.d_addr, dut.u_core.ex_mem_pc);
                report;
                $finish;
            end
            if (cycles > 5000000) begin
                $display("ERROR timeout after %0d cycles", cycles);
                $finish;
            end
        end
    end
endmodule
