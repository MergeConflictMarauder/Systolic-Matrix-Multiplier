`timescale 1ns/1ns

//Design with memories
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

    logic [AWIDTH-1:0]     bram_addr_a, bram_addr_b, bram_addr_c;
    vec_t                  bram_rdata_a, bram_rdata_b, bram_wdata_c;
    logic [MASK_WIDTH-1:0] bram_we_c;

    // Port 0 connects to the matmul; port 1 connects to the external interface.
    // addr, d, we, and q are the address, write data, write enable, and read data.
    // The matmul only reads RAMs A and B, so their port-0 write inputs are tied low.
    // It writes RAM C through port 0 when c_data is available.
    ////////////////////////////////////////////////////////////////
    // RAM matrix A
    ////////////////////////////////////////////////////////////////
    ram matrix_A (.clk, .addr0(bram_addr_a), .d0('0), .we0('0), .q0(bram_rdata_a),
                  .addr1(bram_addr_a_ext), .d1(bram_wdata_a_ext), .we1(bram_we_a_ext), .q1(bram_rdata_a_ext));

    ////////////////////////////////////////////////////////////////
    // RAM matrix B
    ////////////////////////////////////////////////////////////////
    ram matrix_B (.clk, .addr0(bram_addr_b), .d0('0), .we0('0), .q0(bram_rdata_b),
                  .addr1(bram_addr_b_ext), .d1(bram_wdata_b_ext), .we1(bram_we_b_ext), .q1(bram_rdata_b_ext));

    ////////////////////////////////////////////////////////////////
    // RAM matrix C
    ////////////////////////////////////////////////////////////////
    ram matrix_C (.clk, .addr0(bram_addr_c), .d0(bram_wdata_c), .we0(bram_we_c), .q0(),
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
        .*,  //clk, reset, pe_reset, start_mat_mul, done_mat_mul, address_mat_*, address_stride_*, c_data_available
        .a_data(bram_rdata_a),
        .b_data(bram_rdata_b),
        .a_data_in('0),  //not used: this matmul is the only block (a_loc = b_loc = 0)
        .b_data_in('0),
        .c_data_in('0),
        .c_data_out(bram_wdata_c),
        .a_data_out(),
        .b_data_out(),
        .a_addr(bram_addr_a),
        .b_addr(bram_addr_b),
        .c_addr(bram_addr_c),
        .validity_mask_a_rows('1),
        .validity_mask_a_cols_b_rows('1),
        .validity_mask_b_cols('1),
        .final_mat_mul_size(8'd4),
        .a_loc(8'd0),
        .b_loc(8'd0)
    );

endmodule

//////////////////////////////////
//Dual port RAM
//////////////////////////////////
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
