`timescale 1ns / 1ps
// Directed tests for rw_control: store byte lanes and load extension.
module tb_rw_control;
    reg  [2:0]  funct3;
    reg  [1:0]  byte_offset;
    reg  [31:0] store_data;
    reg  [31:0] mem_rdata;
    wire [3:0]  wstrb;
    wire [31:0] wdata;
    wire [31:0] load_data;

    rw_control dut (
        .funct3(funct3),
        .byte_offset(byte_offset),
        .store_data(store_data),
        .mem_rdata(mem_rdata),
        .wstrb(wstrb),
        .wdata(wdata),
        .load_data(load_data)
    );

    integer checks = 0;
    integer errors = 0;

    // Checks the strobe and the bytes on the lanes it enables.
    task store_case(input [2:0] f3, input [1:0] offset, input [3:0] expected_strobe, input [31:0] expected_lanes);
        reg [31:0] lane_mask;
        begin
            funct3 = f3;
            byte_offset = offset;
            #1;
            lane_mask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
            checks = checks + 1;
            if (wstrb !== expected_strobe || (wdata & lane_mask) !== expected_lanes) begin
                errors = errors + 1;
                $display("FAIL store funct3=%b offset=%0d: wstrb=%b lanes=%08h, expected %b %08h",
                         f3, offset, wstrb, wdata & lane_mask, expected_strobe, expected_lanes);
            end
        end
    endtask

    task load_case(input [2:0] f3, input [1:0] offset, input [31:0] expected);
        begin
            funct3 = f3;
            byte_offset = offset;
            #1;
            checks = checks + 1;
            if (load_data !== expected) begin
                errors = errors + 1;
                $display("FAIL load funct3=%b offset=%0d: got %08h, expected %08h", f3, offset, load_data, expected);
            end
        end
    endtask

    initial begin
        store_data = 32'hCAFE_BABE;
        mem_rdata  = 32'h0000_0000;
        store_case(3'b000, 2'd0, 4'b0001, 32'h0000_00BE);   // SB
        store_case(3'b000, 2'd1, 4'b0010, 32'h0000_BE00);
        store_case(3'b000, 2'd2, 4'b0100, 32'h00BE_0000);
        store_case(3'b000, 2'd3, 4'b1000, 32'hBE00_0000);
        store_case(3'b001, 2'd0, 4'b0011, 32'h0000_BABE);   // SH
        store_case(3'b001, 2'd2, 4'b1100, 32'hBABE_0000);
        store_case(3'b010, 2'd0, 4'b1111, 32'hCAFE_BABE);   // SW

        mem_rdata = 32'h8091_A2B3;                          // every byte negative
        load_case(3'b000, 2'd0, 32'hFFFF_FFB3);             // LB
        load_case(3'b000, 2'd1, 32'hFFFF_FFA2);
        load_case(3'b000, 2'd2, 32'hFFFF_FF91);
        load_case(3'b000, 2'd3, 32'hFFFF_FF80);
        load_case(3'b100, 2'd0, 32'h0000_00B3);             // LBU
        load_case(3'b100, 2'd3, 32'h0000_0080);
        load_case(3'b001, 2'd0, 32'hFFFF_A2B3);             // LH
        load_case(3'b001, 2'd2, 32'hFFFF_8091);
        load_case(3'b101, 2'd0, 32'h0000_A2B3);             // LHU
        load_case(3'b101, 2'd2, 32'h0000_8091);
        load_case(3'b010, 2'd0, 32'h8091_A2B3);             // LW

        mem_rdata = 32'h1234_567F;                          // positive bytes: no sign fill
        load_case(3'b000, 2'd0, 32'h0000_007F);
        load_case(3'b001, 2'd2, 32'h0000_1234);

        if (errors == 0) begin
            $display("PASS tb_rw_control: %0d checks", checks);
        end else begin
            $display("FAIL tb_rw_control: %0d of %0d checks failed", errors, checks);
        end
        $finish;
    end
endmodule
