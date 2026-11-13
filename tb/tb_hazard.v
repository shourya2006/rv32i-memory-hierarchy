`timescale 1ns / 1ps
// Directed tests for the hazard unit: forwarding priority and the
// load-use stall.
module tb_hazard;
    reg       id_valid = 1'b1;
    reg [4:0] id_rs1 = 5'd0;
    reg [4:0] id_rs2 = 5'd0;
    reg       id_uses_rs1 = 1'b1;
    reg       id_uses_rs2 = 1'b1;
    reg       ex_valid = 1'b1;
    reg       ex_mem_read = 1'b0;
    reg [4:0] ex_rd = 5'd0;
    reg [4:0] ex_rs1 = 5'd0;
    reg [4:0] ex_rs2 = 5'd0;
    reg       mem_valid = 1'b0;
    reg       mem_reg_write = 1'b0;
    reg [4:0] mem_rd = 5'd0;
    reg       wb_valid = 1'b0;
    reg       wb_reg_write = 1'b0;
    reg [4:0] wb_rd = 5'd0;

    wire       load_use_stall;
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    hazard_unit dut (
        .id_valid(id_valid), .id_rs1(id_rs1), .id_rs2(id_rs2),
        .id_uses_rs1(id_uses_rs1), .id_uses_rs2(id_uses_rs2),
        .ex_valid(ex_valid), .ex_mem_read(ex_mem_read), .ex_rd(ex_rd), .ex_rs1(ex_rs1), .ex_rs2(ex_rs2),
        .mem_valid(mem_valid), .mem_reg_write(mem_reg_write), .mem_rd(mem_rd),
        .wb_valid(wb_valid), .wb_reg_write(wb_reg_write), .wb_rd(wb_rd),
        .load_use_stall(load_use_stall), .forward_a(forward_a), .forward_b(forward_b)
    );

    integer checks = 0;
    integer errors = 0;

    task check(input [8*28-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s: got %0d, expected %0d", name, got, expected);
            end
        end
    endtask

    initial begin
        // add x5 (MEM) -> sub uses x5 as rs1 in EX
        ex_rs1 = 5'd5; ex_rs2 = 5'd6;
        mem_valid = 1'b1; mem_reg_write = 1'b1; mem_rd = 5'd5;
        #1 check("forward A from EX/MEM", forward_a, 2'b10);
        #1 check("B not forwarded", forward_b, 2'b00);

        // Producer two back (WB) for rs2
        wb_valid = 1'b1; wb_reg_write = 1'b1; wb_rd = 5'd6;
        #1 check("forward B from MEM/WB", forward_b, 2'b01);

        // Both stages write x5: the younger one (EX/MEM) wins.
        wb_rd = 5'd5;
        #1 check("newest value wins", forward_a, 2'b10);

        // Writes to x0, stores (no reg write) and bubbles never forward.
        mem_rd = 5'd0; ex_rs1 = 5'd0; wb_rd = 5'd0;
        #1 check("x0 never forwarded", forward_a, 2'b00);
        ex_rs1 = 5'd5; mem_rd = 5'd5; mem_reg_write = 1'b0;
        #1 check("no forward from a store", forward_a, 2'b00);
        mem_reg_write = 1'b1; mem_valid = 1'b0;
        #1 check("no forward from a bubble", forward_a, 2'b00);

        // lw x7 in EX, add uses x7 in ID: stall one cycle.
        ex_mem_read = 1'b1; ex_rd = 5'd7; id_rs1 = 5'd7; id_rs2 = 5'd1;
        #1 check("load-use on rs1", load_use_stall, 1'b1);
        id_rs1 = 5'd1; id_rs2 = 5'd7;
        #1 check("load-use on rs2", load_use_stall, 1'b1);
        id_uses_rs2 = 1'b0;
        #1 check("no stall: rs2 not used", load_use_stall, 1'b0);
        id_uses_rs2 = 1'b1; ex_rd = 5'd0; id_rs2 = 5'd0;
        #1 check("no stall: load to x0", load_use_stall, 1'b0);
        ex_rd = 5'd7; id_rs2 = 5'd7; ex_mem_read = 1'b0;
        #1 check("no stall: not a load", load_use_stall, 1'b0);
        ex_mem_read = 1'b1; id_valid = 1'b0;
        #1 check("no stall: bubble in ID", load_use_stall, 1'b0);

        if (errors == 0) begin
            $display("PASS tb_hazard: %0d checks", checks);
        end else begin
            $display("FAIL tb_hazard: %0d of %0d checks failed", errors, checks);
        end
        $finish;
    end
endmodule
