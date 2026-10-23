`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////
// Matrix multiplier top level with RAMs, shared by part 2 and part 3.
// Only one top level is compiled, chosen by the MATMUL_8X8 define:
//   not defined : matrix_multiplication,     4x4 array, one RAM per matrix  (part 2)
//   defined     : matrix_multiplication_8x8, 8x8 array, two RAMs per matrix (part 3,
//                 compile with +define+MATMUL_8X8 and part_3_8x8/rtl/matmul_8x8.sv)
// The dual-port ram module is compiled in both cases.
// Compile matmul_pkg.sv first.
//////////////////////////////////////////////////////////////////////////

`ifndef MATMUL_8X8
//////////////////////////////////////////////////////////////////////////
// 4x4 matrix multiplication with RAMs (part 2)
//////////////////////////////////////////////////////////////////////////
module matrix_multiplication
    import matmul_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetn,
    input  logic                         pe_resetn,
    input  logic [AWIDTH-1:0]            address_mat_a, address_mat_b, address_mat_c,
    input  logic [ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c,
    input  logic [AWIDTH-1:0]            bram_addr_a_ext,
    output vec_t                         bram_rdata_a_ext,
    input  vec_t                         bram_wdata_a_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_a_ext,
    input  logic [AWIDTH-1:0]            bram_addr_b_ext,
    output vec_t                         bram_rdata_b_ext,
    input  vec_t                         bram_wdata_b_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_b_ext,
    input  logic [AWIDTH-1:0]            bram_addr_c_ext,
    output vec_t                         bram_rdata_c_ext,
    input  vec_t                         bram_wdata_c_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_c_ext,
    input  logic                         start, //starts the matmul operation
    output logic                         done,   //asserts when matmul operation is complete
    output logic [4:0]                   exception_flags
);

    logic [AWIDTH-1:0]     a_addr, b_addr, c_addr;
    vec_t                  a_data, b_data, c_data_out;
    logic [MASK_WIDTH-1:0] bram_we_c;

    // Port 0 serves the matmul; port 1 serves the external interface.
    // addr, d, we, and q denote address, write data, write enable, and read data.
    // The matmul reads A and B and writes C when c_data_available is asserted.
    ////////////////////////////////////////////////////////////////
    // RAM matrix A
    ////////////////////////////////////////////////////////////////
    ram matrix_A (.clk, .addr0(a_addr), .d0('0), .we0('0), .q0(a_data),
                  .addr1(bram_addr_a_ext), .d1(bram_wdata_a_ext), .we1(bram_we_a_ext), .q1(bram_rdata_a_ext));

    ////////////////////////////////////////////////////////////////
    // RAM matrix B
    ////////////////////////////////////////////////////////////////
    ram matrix_B (.clk, .addr0(b_addr), .d0('0), .we0('0), .q0(b_data),
                  .addr1(bram_addr_b_ext), .d1(bram_wdata_b_ext), .we1(bram_we_b_ext), .q1(bram_rdata_b_ext));

    ////////////////////////////////////////////////////////////////
    // RAM matrix C
    ////////////////////////////////////////////////////////////////
    ram matrix_C (.clk, .addr0(c_addr), .d0(c_data_out), .we0(bram_we_c), .q0(),
                  .addr1(bram_addr_c_ext), .d1(bram_wdata_c_ext), .we1(bram_we_c_ext), .q1(bram_rdata_c_ext));

    //fsm to start matmul
    typedef enum logic [3:0] {
        IDLE      = 4'b0000,
        START     = 4'b0001,
        WAIT_DONE = 4'b1010
    } state_t;

    state_t state;
    logic   start_mat_mul, done_mat_mul;

    always_ff @(posedge clk) begin
        if (!resetn) begin
            state         <= IDLE;
            start_mat_mul <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    start_mat_mul <= 1'b0;
                    if (start) state <= START;
                end
                START: begin
                    start_mat_mul <= 1'b1;
                    state         <= WAIT_DONE;
                end
                WAIT_DONE: begin
                    if (done_mat_mul) begin
                        start_mat_mul <= 1'b0;
                        state         <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign done = done_mat_mul;

    logic c_data_available;
    assign bram_we_c = {MASK_WIDTH{c_data_available}};

    logic reset, pe_reset;
    assign reset    = ~resetn;
    assign pe_reset = ~pe_resetn;

//matmul instance
    matmul_4x4_systolic u_matmul_4x4 (
        .*,  // clk, reset, pe_reset, start_mat_mul, done_mat_mul, address_mat_*, address_stride_*,
             // a_data, b_data, c_data_out, a_addr, b_addr, c_addr, c_data_available
        .a_data_in('0),  // not used: this matmul is the only block (a_loc = b_loc = 0)
        .b_data_in('0),
        .c_data_in('0),
        .a_data_out(),
        .b_data_out(),
        .validity_mask_a_rows('1),
        .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd4),
        .a_loc(8'd0),
        .b_loc(8'd0)
    );

endmodule

`else
//////////////////////////////////////////////////////////////////////////
// 8x8 matrix multiplication with RAMs (part 3)
//////////////////////////////////////////////////////////////////////////
// part_3 top level with part_2 start/done control and six dual-port RAM banks.
// Each 32-bit bank holds four FP8 lanes; port 0 serves the accelerator, port 1 the host.
module matrix_multiplication_8x8
    import matmul_pkg::*;
(
    input  logic                         clk,
    input  logic                         resetn, pe_resetn,
    input  logic [AWIDTH-1:0]            address_mat_a, address_mat_b, address_mat_c,
    input  logic [ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c,
    input  logic                         start,
    output logic                         done,
    output logic [4:0]                   exception_flags,
    // External port-1 interface for A0 and A1 (rows 0..3, rows 4..7)
    input  logic [AWIDTH-1:0]            bram_addr_a0_ext, bram_addr_a1_ext,
    input  vec_t                         bram_wdata_a0_ext, bram_wdata_a1_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_a0_ext, bram_we_a1_ext,
    output vec_t                         bram_rdata_a0_ext, bram_rdata_a1_ext,
    // External port-1 interface for B0 and B1 (cols 0..3, cols 4..7)
    input  logic [AWIDTH-1:0]            bram_addr_b0_ext, bram_addr_b1_ext,
    input  vec_t                         bram_wdata_b0_ext, bram_wdata_b1_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_b0_ext, bram_we_b1_ext,
    output vec_t                         bram_rdata_b0_ext, bram_rdata_b1_ext,
    // External port-1 interface for C0 and C1 (rows 0..3, rows 4..7)
    input  logic [AWIDTH-1:0]            bram_addr_c0_ext, bram_addr_c1_ext,
    input  vec_t                         bram_wdata_c0_ext, bram_wdata_c1_ext,
    input  logic [MASK_WIDTH-1:0]        bram_we_c0_ext, bram_we_c1_ext,
    output vec_t                         bram_rdata_c0_ext, bram_rdata_c1_ext
);
    logic reset, pe_reset;
    assign reset    = ~resetn;
    assign pe_reset = ~pe_resetn;

    logic [AWIDTH-1:0] a_addr_0, a_addr_1, b_addr_0, b_addr_1, c_addr_0, c_addr_1;
    vec_t a_data_0, a_data_1, b_data_0, b_data_1;
    vec_t c_data_0, c_data_1;
    logic c_data_available;
    logic [MASK_WIDTH-1:0] we_c;
    assign we_c = {MASK_WIDTH{c_data_available}};

    ram matrix_A0 (
        .clk(clk), .addr0(a_addr_0), .d0('0), .we0('0), .q0(a_data_0),
        .addr1(bram_addr_a0_ext), .d1(bram_wdata_a0_ext),
        .we1(bram_we_a0_ext), .q1(bram_rdata_a0_ext)
    );
    ram matrix_A1 (
        .clk(clk), .addr0(a_addr_1), .d0('0), .we0('0), .q0(a_data_1),
        .addr1(bram_addr_a1_ext), .d1(bram_wdata_a1_ext),
        .we1(bram_we_a1_ext), .q1(bram_rdata_a1_ext)
    );
    ram matrix_B0 (
        .clk(clk), .addr0(b_addr_0), .d0('0), .we0('0), .q0(b_data_0),
        .addr1(bram_addr_b0_ext), .d1(bram_wdata_b0_ext),
        .we1(bram_we_b0_ext), .q1(bram_rdata_b0_ext)
    );
    ram matrix_B1 (
        .clk(clk), .addr0(b_addr_1), .d0('0), .we0('0), .q0(b_data_1),
        .addr1(bram_addr_b1_ext), .d1(bram_wdata_b1_ext),
        .we1(bram_we_b1_ext), .q1(bram_rdata_b1_ext)
    );
    ram matrix_C0 (
        .clk(clk), .addr0(c_addr_0), .d0(c_data_0), .we0(we_c), .q0(),
        .addr1(bram_addr_c0_ext), .d1(bram_wdata_c0_ext),
        .we1(bram_we_c0_ext), .q1(bram_rdata_c0_ext)
    );
    ram matrix_C1 (
        .clk(clk), .addr0(c_addr_1), .d0(c_data_1), .we0(we_c), .q0(),
        .addr1(bram_addr_c1_ext), .d1(bram_wdata_c1_ext),
        .we1(bram_we_c1_ext), .q1(bram_rdata_c1_ext)
    );

    typedef enum logic [1:0] {IDLE, START, WAIT_DONE} state_t;
    state_t state;
    logic start_mat_mul, done_mat_mul;

    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            start_mat_mul <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    start_mat_mul <= 1'b0;
                    if (start) state <= START;
                end
                START: begin
                    start_mat_mul <= 1'b1;
                    state         <= WAIT_DONE;
                end
                WAIT_DONE: if (done_mat_mul) begin
                    start_mat_mul <= 1'b0;
                    state         <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
    assign done = done_mat_mul;

    // Every port of the 8x8 array has a signal of the same name here
    matmul_8x8_systolic u_matmul_8x8 (.*);
endmodule
`endif

//////////////////////////////////////////////////////////////////////////
// Dual-port RAM (shared by both top levels)
//////////////////////////////////////////////////////////////////////////
module ram
    import matmul_pkg::*;
(
    input  logic                  clk,
    input  logic [AWIDTH-1:0]     addr0, addr1,
    input  vec_t                  d0, d1,
    input  logic [MASK_WIDTH-1:0] we0, we1,
    output vec_t                  q0, q1
);

    // Testbenches preload this array through hierarchical references
    // (e.g. u_matmul.matrix_A.ram[i] in part 2, u_matmul.matrix_A0.ram[k] in part 3).
    // Both ports can write it, so it has multiple writers. Using plain always
    // blocks avoids the always_ff restriction.
    vec_t ram [2**AWIDTH-1:0];

    always @(posedge clk) begin
        if (|we0) ram[addr0] <= d0;
        q0 <= ram[addr0];
    end

    always @(posedge clk) begin
        if (|we1) ram[addr1] <= d1;
        q1 <= ram[addr1];
    end

endmodule
