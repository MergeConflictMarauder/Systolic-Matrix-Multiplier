`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// 8x8 FP8 matrix multiplier with an APB control interface (part 4).
//
// Same datapath and RAMs as part 3's matrix_multiplication_8x8 (root
// matmul_with_ram.sv). The start/done control FSM and the control and status
// ports (start, done, exception_flags, address_mat_*, address_stride_*) are
// replaced by apb_slave: a CPU writes the addresses, strides and START over
// APB, polls DONE and reads FLAGS. The register map is in apb_slave.sv.
//
//   APB bus ---> apb_slave ---start_mat_mul, address_mat_*, address_stride_*---> matmul_8x8_systolic
//                    ^                                                                 |
//                    +-------------------done_mat_mul, exception_flags-----------------+
//
// The six RAMs keep their external port 1, so the host side can load A and B
// and read C. PCLK clocks the whole design and PRESETn resets it. The 8x8
// array clears its PE accumulators at every start, so no separate PE reset port is needed.
//
// Compile after matmul_pkg.sv, the FP8 units, matmul.sv, part_3/matmul_8x8.sv,
// ../matmul_with_ram.sv (with +define+MATMUL_8X8, for the ram module) and apb_slave.sv.
//////////////////////////////////////////////////////////////////////////
module matrix_multiplication_8x8_apb
    import matmul_pkg::*;
(
    // APB interface (16-bit registers)
    input  logic                         PCLK,
    input  logic                         PRESETn,
    input  logic [`REG_ADDRWIDTH-1:0]    PADDR,
    input  logic                         PWRITE,
    input  logic                         PSEL,
    input  logic                         PENABLE,
    input  logic [`REG_DATAWIDTH-1:0]    PWDATA,
    output logic [`REG_DATAWIDTH-1:0]    PRDATA,
    output logic                         PREADY,
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
    logic clk, reset, pe_reset;
    assign clk      = PCLK;
    assign reset    = ~PRESETn;
    assign pe_reset = reset;

    logic [AWIDTH-1:0] a_addr_0, a_addr_1, b_addr_0, b_addr_1, c_addr_0, c_addr_1;
    vec_t a_data_0, a_data_1, b_data_0, b_data_1;
    vec_t c_data_0, c_data_1;
    logic c_data_available;
    logic [MASK_WIDTH-1:0] we_c;
    assign we_c = {MASK_WIDTH{c_data_available}};

    //////////////////////////////////////////////////////////////////////
    // RAMs, unchanged from part 3
    //////////////////////////////////////////////////////////////////////
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

    //////////////////////////////////////////////////////////////////////
    // APB slave: replaces part 3's IDLE/START/WAIT_DONE control FSM.
    // Its START register drives start_mat_mul directly and stays high until
    // done_mat_mul, which is what the FSM did.
    //////////////////////////////////////////////////////////////////////
    logic                         start_mat_mul, done_mat_mul;
    logic [4:0]                   exception_flags;
    logic [AWIDTH-1:0]            address_mat_a, address_mat_b, address_mat_c;
    logic [ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c;

    apb_slave u_apb (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .PADDR            (PADDR),
        .PWRITE           (PWRITE),
        .PSEL             (PSEL),
        .PENABLE          (PENABLE),
        .PWDATA           (PWDATA),
        .PRDATA           (PRDATA),
        .PREADY           (PREADY),
        .start            (start_mat_mul),
        .address_mat_a    (address_mat_a),
        .address_mat_b    (address_mat_b),
        .address_mat_c    (address_mat_c),
        .address_stride_a (address_stride_a),
        .address_stride_b (address_stride_b),
        .address_stride_c (address_stride_c),
        .done             (done_mat_mul),
        .flags            (exception_flags)
    );

    // Every port of the 8x8 array has a signal of the same name here
    matmul_8x8_systolic u_matmul_8x8 (.*);
endmodule
