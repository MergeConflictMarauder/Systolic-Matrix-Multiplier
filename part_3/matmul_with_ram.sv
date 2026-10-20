`timescale 1ns/1ps
// Part 3 top-level, retaining the Part II start/done control interface.
// The six RAM banks are 32-bit dual-port memories of four FP8 lanes each.
// Port 0 is used by the accelerator, port 1 by an external host/testbench.
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

    logic [AWIDTH-1:0] addr_a0, addr_a1, addr_b0, addr_b1, addr_c0, addr_c1;
    vec_t rdata_a0, rdata_a1, rdata_b0, rdata_b1;
    vec_t wdata_c0, wdata_c1;
    logic c_data_available;
    logic [MASK_WIDTH-1:0] we_c;
    assign we_c = {MASK_WIDTH{c_data_available}};

    ram matrix_A0 (
        .clk(clk), .addr0(addr_a0), .d0('0), .we0('0), .q0(rdata_a0),
        .addr1(bram_addr_a0_ext), .d1(bram_wdata_a0_ext),
        .we1(bram_we_a0_ext), .q1(bram_rdata_a0_ext)
    );
    ram matrix_A1 (
        .clk(clk), .addr0(addr_a1), .d0('0), .we0('0), .q0(rdata_a1),
        .addr1(bram_addr_a1_ext), .d1(bram_wdata_a1_ext),
        .we1(bram_we_a1_ext), .q1(bram_rdata_a1_ext)
    );
    ram matrix_B0 (
        .clk(clk), .addr0(addr_b0), .d0('0), .we0('0), .q0(rdata_b0),
        .addr1(bram_addr_b0_ext), .d1(bram_wdata_b0_ext),
        .we1(bram_we_b0_ext), .q1(bram_rdata_b0_ext)
    );
    ram matrix_B1 (
        .clk(clk), .addr0(addr_b1), .d0('0), .we0('0), .q0(rdata_b1),
        .addr1(bram_addr_b1_ext), .d1(bram_wdata_b1_ext),
        .we1(bram_we_b1_ext), .q1(bram_rdata_b1_ext)
    );
    ram matrix_C0 (
        .clk(clk), .addr0(addr_c0), .d0(wdata_c0), .we0(we_c), .q0(),
        .addr1(bram_addr_c0_ext), .d1(bram_wdata_c0_ext),
        .we1(bram_we_c0_ext), .q1(bram_rdata_c0_ext)
    );
    ram matrix_C1 (
        .clk(clk), .addr0(addr_c1), .d0(wdata_c1), .we0(we_c), .q0(),
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

    matmul_8x8_systolic u_matmul_8x8 (
        .clk(clk), .reset(reset), .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul), .done_mat_mul(done_mat_mul),
        .exception_flags(exception_flags),
        .address_mat_a(address_mat_a), .address_mat_b(address_mat_b),
        .address_mat_c(address_mat_c),
        .address_stride_a(address_stride_a), .address_stride_b(address_stride_b),
        .address_stride_c(address_stride_c),
        .a_data_0(rdata_a0), .a_data_1(rdata_a1),
        .b_data_0(rdata_b0), .b_data_1(rdata_b1),
        .c_data_0(wdata_c0), .c_data_1(wdata_c1),
        .a_addr_0(addr_a0), .a_addr_1(addr_a1),
        .b_addr_0(addr_b0), .b_addr_1(addr_b1),
        .c_addr_0(addr_c0), .c_addr_1(addr_c1),
        .c_data_available(c_data_available)
    );
endmodule

// Identical dual-port synchronous-read RAM model from the supplied Part II.
module ram
    import matmul_pkg::*;
(
    input  logic                  clk,
    input  logic [AWIDTH-1:0]     addr0, addr1,
    input  vec_t                  d0, d1,
    input  logic [MASK_WIDTH-1:0] we0, we1,
    output vec_t                  q0, q1
);

    // The testbench preloads this array through hierarchical references
    // (e.g. u_matmul.matrix_A.ram[i] = ...). Both ports can write it, so it has
    // multiple writers. Using plain always blocks avoids the always_ff restriction.
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
