// Main memory with a configurable number of wait states.
//
// Bus handshake (used by every memory port in the project): the master
// holds req, we, addr, wdata and wstrb steady until the cycle in which
// ready is high; that cycle completes the transfer. Here ready comes after
// WAIT idle cycles, so each word costs WAIT + 1 cycles. If the master
// changes the address before ready (a fetch abandoned after a branch), the
// wait starts again for the new address.
//
// WAIT = 0 gives an asynchronous read (zero-wait-state SRAM). WAIT >= 1
// registers the read data, which lets synthesis use block RAM.
module main_memory #(
    parameter WORDS     = 4096,     // 16 KB
    parameter WAIT      = 0,
    parameter INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        req,
    input  wire        we,
    input  wire [31:0] addr,         // byte address; bits [1:0] are handled by rw_control
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output wire        ready,
    output wire [31:0] rdata
);
    localparam INDEX_BITS = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    wire [INDEX_BITS-1:0] index = addr[INDEX_BITS+1:2];

    // Wait-state counter
    reg        waiting;              // the same request was already here last cycle
    reg [31:0] waiting_addr;
    reg        waiting_we;
    reg [7:0]  waited;

    wire       same_request = waiting && req && (addr == waiting_addr) && (we == waiting_we);
    wire [7:0] wait_count   = same_request ? waited : 8'd0;

    assign ready = req && (wait_count == WAIT);

    always @(posedge clk) begin
        if (rst) begin
            waiting <= 1'b0;
        end else begin
            waiting      <= req && !ready;
            waiting_addr <= addr;
            waiting_we   <= we;
            waited       <= wait_count + 8'd1;
        end
    end

    always @(posedge clk) begin
        if (req && we && ready) begin
            if (wstrb[0]) mem[index][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[index][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[index][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[index][31:24] <= wdata[31:24];
        end
    end

    generate
        if (WAIT == 0) begin : async_read
            assign rdata = mem[index];
        end else begin : sync_read
            reg [31:0] rdata_q;
            always @(posedge clk) begin
                rdata_q <= mem[index];
            end
            assign rdata = rdata_q;
        end
    endgenerate
endmodule
