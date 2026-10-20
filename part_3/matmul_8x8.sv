`timescale 1ns/1ps
// Lab 3, Part 3: An 8x8 E3M4 matrix multiplier
// matmul_4x4_systolic blocks in ../matmul.sv.
//
//                B0 (cols 0..3)    B1 (cols 4..7)
//                |                |
//    A0 --> [TL (0,0)] ----A----> [TR (0,1)]
//                | B              | B
//                v                v
//    A1 --> [BL (1,0)] ----A----> [BR (1,1)]
//
// On output, each right tile shifts four C columns to its left neighbor.
// TL and BL each produce 8 successive 32-bit output columns, one per row bank.
//
// NOTE: The 4x4 tiles' done_mat_mul pulse is hardcoded for 4x4. Their output
// latch time *does* depend on final_mat_mul_size. We intentionally IGNORE
// tile done and terminate after the 8th actual C RAM write. Likewise, we
// generate the C write address ourselves because the early tile-done pulse
// disturbs the tile-internal c_addr prior to the 8x8 latch event.
module matmul_8x8_systolic
    import matmul_pkg::*;
(
    input  logic                         clk,
    input  logic                         reset,
    input  logic                         pe_reset,
    input  logic                         start_mat_mul,
    output logic                         done_mat_mul,
    output logic [4:0]                   exception_flags,
    input  logic [AWIDTH-1:0]            address_mat_a, address_mat_b, address_mat_c,
    input  logic [ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c,
    input  vec_t                         a_data_0, a_data_1,
    input  vec_t                         b_data_0, b_data_1,
    output vec_t                         c_data_0, c_data_1,
    output logic [AWIDTH-1:0]            a_addr_0, a_addr_1,
    output logic [AWIDTH-1:0]            b_addr_0, b_addr_1,
    output logic [AWIDTH-1:0]            c_addr_0, c_addr_1,
    output logic                         c_data_available
);
    // Systolic operand propagation: A moves right, B moves down.
    vec_t a_tl_tr, a_bl_br;
    vec_t b_tl_bl, b_tr_br;
    // Output C moves left: right-hand tile feeds the left-hand tile.
    vec_t c_tr_tl, c_br_bl;

    logic [4:0] flags_tl, flags_tr, flags_bl, flags_br;
    logic [4:0] flags_cycle;
    logic c_available_tl, c_available_bl;
    logic running_d;
    logic [3:0] c_write_count;  // valid values 0..8
    logic [AWIDTH-1:0] c_write_address;
    logic write_c;

    assign flags_cycle = flags_tl | flags_tr | flags_bl | flags_br;

    // A 4x4 tile asserts its native done too early for an 8x8 computation.
    // All tile done and tile c_addr signals are therefore left unconnected.
    // Shared address, stride and mask inputs are IDENTICAL on all four tiles.
    matmul_4x4_systolic u_tl (
        .clk(clk), .reset(reset), .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul), .done_mat_mul(),
        .exception_flags(flags_tl),
        .address_mat_a(address_mat_a), .address_mat_b(address_mat_b),
        .address_mat_c(address_mat_c),
        .address_stride_a(address_stride_a), .address_stride_b(address_stride_b),
        .address_stride_c(address_stride_c),
        .a_data(a_data_0), .b_data(b_data_0),
        .a_data_in('0), .b_data_in('0), .c_data_in(c_tr_tl),
        .a_data_out(a_tl_tr), .b_data_out(b_tl_bl), .c_data_out(c_data_0),
        .a_addr(a_addr_0), .b_addr(b_addr_0), .c_addr(),
        .c_data_available(c_available_tl),
        .validity_mask_a_rows('1), .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd8), .a_loc(8'd0), .b_loc(8'd0)
    );

    matmul_4x4_systolic u_tr (
        .clk(clk), .reset(reset), .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul), .done_mat_mul(),
        .exception_flags(flags_tr),
        .address_mat_a(address_mat_a), .address_mat_b(address_mat_b),
        .address_mat_c(address_mat_c),
        .address_stride_a(address_stride_a), .address_stride_b(address_stride_b),
        .address_stride_c(address_stride_c),
        .a_data('0), .b_data(b_data_1),
        .a_data_in(a_tl_tr), .b_data_in('0), .c_data_in('0),
        .a_data_out(), .b_data_out(b_tr_br), .c_data_out(c_tr_tl),
        .a_addr(), .b_addr(b_addr_1), .c_addr(),
        .c_data_available(),
        .validity_mask_a_rows('1), .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd8), .a_loc(8'd0), .b_loc(8'd1)
    );

    matmul_4x4_systolic u_bl (
        .clk(clk), .reset(reset), .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul), .done_mat_mul(),
        .exception_flags(flags_bl),
        .address_mat_a(address_mat_a), .address_mat_b(address_mat_b),
        .address_mat_c(address_mat_c),
        .address_stride_a(address_stride_a), .address_stride_b(address_stride_b),
        .address_stride_c(address_stride_c),
        .a_data(a_data_1), .b_data('0),
        .a_data_in('0), .b_data_in(b_tl_bl), .c_data_in(c_br_bl),
        .a_data_out(a_bl_br), .b_data_out(), .c_data_out(c_data_1),
        .a_addr(a_addr_1), .b_addr(), .c_addr(),
        .c_data_available(c_available_bl),
        .validity_mask_a_rows('1), .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd8), .a_loc(8'd1), .b_loc(8'd0)
    );

    matmul_4x4_systolic u_br (
        .clk(clk), .reset(reset), .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul), .done_mat_mul(),
        .exception_flags(flags_br),
        .address_mat_a(address_mat_a), .address_mat_b(address_mat_b),
        .address_mat_c(address_mat_c),
        .address_stride_a(address_stride_a), .address_stride_b(address_stride_b),
        .address_stride_c(address_stride_c),
        .a_data('0), .b_data('0),
        .a_data_in(a_bl_br), .b_data_in(b_tr_br), .c_data_in('0),
        .a_data_out(), .b_data_out(), .c_data_out(c_br_bl),
        .a_addr(), .b_addr(), .c_addr(),
        .c_data_available(),
        .validity_mask_a_rows('1), .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd8), .a_loc(8'd1), .b_loc(8'd1)
    );

    // Use exactly EIGHT output writes, one C column per cycle per row bank.
    // Both output banks share the base/stride and their read/write schedule.
    assign write_c          = start_mat_mul && c_available_tl && c_available_bl
                              && (c_write_count < 4'd8);
    assign c_data_available = write_c;
    assign c_addr_0         = c_write_address;
    assign c_addr_1         = c_write_address;

    always_ff @(posedge clk) begin
        if (reset) begin
            running_d       <= 1'b0;
            c_write_count   <= '0;
            c_write_address <= '0;
            done_mat_mul    <= 1'b0;
            exception_flags <= '0;
        end else begin
            running_d    <= start_mat_mul;
            done_mat_mul <= 1'b0;
            if (!start_mat_mul) begin
                c_write_count   <= '0;
                c_write_address <= address_mat_c;
                // Preserve exception_flags for post-operation software reads.
            end else begin
                // Clear only when a NEW operation begins. Accumulate across
                // all tiles and all cycles so transitory faults are preserved.
                if (!running_d) exception_flags <= flags_cycle;
                else            exception_flags <= exception_flags | flags_cycle;

                if (write_c) begin
                    c_write_count   <= c_write_count + 1'b1;
                    c_write_address <= c_write_address + address_stride_c;
                    if (c_write_count == 4'd7)
                        done_mat_mul <= 1'b1; // eighth write completed
                end
            end
        end
    end
endmodule
