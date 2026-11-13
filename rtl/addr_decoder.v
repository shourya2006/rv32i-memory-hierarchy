// Address decoder. All four systems use the same memory map, so the same
// program image runs on each of them:
//
//   0x0000_0000 - 0x0000_3FFF   code   (16 KB)
//   0x1000_0000 - 0x1000_3FFF   data   (16 KB, stack at the top)
//   0x2000_0000 - 0x2000_0FFF   I/O    (a store here is the output port)
//   anything else               unmapped -> bus error
module addr_decoder (
    input  wire [31:0] addr,
    output wire        sel_code,
    output wire        sel_data,
    output wire        sel_io,
    output wire        unmapped
);
    assign sel_code = (addr[31:14] == 18'h00000);
    assign sel_data = (addr[31:14] == 18'h04000);   // 0x1000_0000 >> 14
    assign sel_io   = (addr[31:12] == 20'h20000);
    assign unmapped = ~(sel_code | sel_data | sel_io);
endmodule
