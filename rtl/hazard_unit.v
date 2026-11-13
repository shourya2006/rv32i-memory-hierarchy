// Hazard unit: forwarding selects for the EX stage and the load-use stall.
//
//   forward = 2'b10  take the value from EX/MEM (result of the previous instruction)
//   forward = 2'b01  take the value from MEM/WB (result two instructions back)
//   forward = 2'b00  use the value read from the register file in ID
//
// A load's data only exists after MEM, so an instruction that needs it
// right after the load waits one cycle in ID (load-use stall) and then
// gets it from MEM/WB.
module hazard_unit (
    // ID stage
    input  wire       id_valid,
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,
    // EX stage
    input  wire       ex_valid,
    input  wire       ex_mem_read,
    input  wire [4:0] ex_rd,
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    // MEM stage
    input  wire       mem_valid,
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd,
    // WB stage
    input  wire       wb_valid,
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd,

    output wire       load_use_stall,
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);
    wire mem_writes = mem_valid && mem_reg_write && (mem_rd != 5'd0);
    wire wb_writes  = wb_valid && wb_reg_write && (wb_rd != 5'd0);

    always @(*) begin
        if (mem_writes && mem_rd == ex_rs1) begin
            forward_a = 2'b10;
        end else if (wb_writes && wb_rd == ex_rs1) begin
            forward_a = 2'b01;
        end else begin
            forward_a = 2'b00;
        end

        if (mem_writes && mem_rd == ex_rs2) begin
            forward_b = 2'b10;
        end else if (wb_writes && wb_rd == ex_rs2) begin
            forward_b = 2'b01;
        end else begin
            forward_b = 2'b00;
        end
    end

    wire ex_is_load = ex_valid && ex_mem_read && (ex_rd != 5'd0);

    assign load_use_stall = id_valid && ex_is_load &&
                            ((id_uses_rs1 && id_rs1 == ex_rd) || (id_uses_rs2 && id_rs2 == ex_rd));
endmodule
