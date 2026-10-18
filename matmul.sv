`timescale 1ns / 1ps

module matmul_4x4_systolic
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
    input  vec_t                         a_data,
    input  vec_t                         b_data,
    input  vec_t                         a_data_in,  //Data values coming in from previous matmul - systolic connections
    input  vec_t                         b_data_in,
    input  vec_t                         c_data_in,  //Data values coming in from previous matmul - systolic shifting
    output vec_t                         c_data_out, //Data values going out to next matmul - systolic shifting
    output vec_t                         a_data_out,
    output vec_t                         b_data_out,
    output logic [AWIDTH-1:0]            a_addr, b_addr, c_addr,
    output logic                         c_data_available,
    input  logic [MASK_WIDTH-1:0]        validity_mask_a_rows,
    input  logic [MASK_WIDTH-1:0]        validity_mask_a_cols_b_rows,
    input  logic [MASK_WIDTH-1:0]        validity_mask_b_cols,
    //7:0 is okay here. We aren't going to make a matmul larger than 128x128
    //In fact, these will get optimized out by the synthesis tool, because
    //we hardcode them at the instantiation level.
    input  logic [7:0]                   final_mat_mul_size,
    input  logic [7:0]                   a_loc,
    input  logic [7:0]                   b_loc
);

//////////////////////////////////////////////////////////////////////////
// Logic for clock counting and when to assert done
//////////////////////////////////////////////////////////////////////////

    //The 8-bit counter suits expected runtimes; increase its width for larger matmuls.
    //A systolic matmul takes f(N) + P cycles, where f(N) depends on matrix size
    //and P is the number of MAC pipeline stages.
    logic [7:0] clk_cnt;

    //Finding out number of cycles to assert matmul done.
    localparam int CYCLES_FOR_MATMUL = 14;
    localparam int CLK_CNT_FOR_DONE  = CYCLES_FOR_MATMUL + NUM_CYCLES_IN_MAC;

    //done_mat_mul pulses for one cycle when clk_cnt reaches CLK_CNT_FOR_DONE
    always_ff @(posedge clk) begin
        if (reset || !start_mat_mul) begin
            clk_cnt      <= '0;
            done_mat_mul <= 1'b0;
        end else begin
            clk_cnt      <= clk_cnt + 1'b1;
            done_mat_mul <= (clk_cnt == CLK_CNT_FOR_DONE);
        end
    end

//////////////////////////////////////////////////////////////////////////
// Instantiation of systolic data setup (one instance per input matrix)
//////////////////////////////////////////////////////////////////////////
    vec_t a_skewed, b_skewed;

    systolic_data_setup u_systolic_data_setup_a (
        .*,
        .address_mat(address_mat_a), .address_stride(address_stride_a), .loc(a_loc),
        .validity_mask_lanes(validity_mask_a_rows),
        .mem_addr(a_addr), .mem_data(a_data), .data_skewed(a_skewed));

    systolic_data_setup u_systolic_data_setup_b (
        .*,
        .address_mat(address_mat_b), .address_stride(address_stride_b), .loc(b_loc),
        .validity_mask_lanes(validity_mask_b_cols),
        .mem_addr(b_addr), .mem_data(b_data), .data_skewed(b_skewed));

//////////////////////////////////////////////////////////////////////////
// Logic to mux data_in coming from neighboring matmuls
//////////////////////////////////////////////////////////////////////////
    vec_t a_pe, b_pe;

    // b_loc == 0: A comes from memory; otherwise, from the matmul to the left.
    assign a_pe = (b_loc == 0) ? a_skewed : a_data_in;

    // a_loc == 0: B comes from memory; otherwise, from the matmul above.
    assign b_pe = (a_loc == 0) ? b_skewed : b_data_in;

    mat_t c_cols;  //c_cols[j][i] is C[i][j]

//////////////////////////////////////////////////////////////////////////
// Instantiation of the output logic
//////////////////////////////////////////////////////////////////////////
    output_logic u_output_logic (.*);

//////////////////////////////////////////////////////////////////////////
// Instantiations of the actual PEs
//////////////////////////////////////////////////////////////////////////
    systolic_pe_matrix u_systolic_pe_matrix (.*);

endmodule

//////////////////////////////////////////////////////////////////////////
// Output logic
//////////////////////////////////////////////////////////////////////////
module output_logic
    import matmul_pkg::*;
(
    input  logic                         clk,
    input  logic                         reset,
    input  logic                         start_mat_mul,
    input  logic                         done_mat_mul,
    input  logic [AWIDTH-1:0]            address_mat_c,
    input  logic [ADDR_STRIDE_WIDTH-1:0] address_stride_c,
    input  vec_t                         c_data_in,
    output vec_t                         c_data_out, //Data values going out to next matmul - systolic shifting
    output logic [AWIDTH-1:0]            c_addr,
    output logic                         c_data_available,
    input  logic [7:0]                   clk_cnt,
    input  logic [7:0]                   final_mat_mul_size,
    input  mat_t                         c_cols      //c_cols[j][i] is C[i][j], so c_cols[j] is column j
);

//////////////////////////////////////////////////////////////////////////
// Logic to capture matrix C data from the PEs and shift it out
//////////////////////////////////////////////////////////////////////////
    logic row_latch_en;
    assign row_latch_en = (clk_cnt == ((final_mat_mul_size<<2) - final_mat_mul_size - 1 + NUM_CYCLES_IN_MAC));

    logic start_capturing_c_data;
    int   counter;
    vec_t [MAT_MUL_SIZE-1:0] c_shift;  //column shift register; c_shift[0] drives c_data_out

    assign c_data_out = c_shift[0];

    always_ff @(posedge clk) begin
        if (reset || !start_mat_mul) begin
            start_capturing_c_data <= 1'b0;
            c_data_available       <= 1'b0;
            c_addr                 <= address_mat_c - address_stride_c;
            c_shift                <= '0;
            counter                <= 0;
        end else if (row_latch_en) begin
            start_capturing_c_data <= 1'b1;
            c_data_available       <= 1'b1;
            c_addr                 <= c_addr + address_stride_c;
            c_shift                <= c_cols;
            counter                <= counter + 1;
        end else if (done_mat_mul) begin
            start_capturing_c_data <= 1'b0;
            c_data_available       <= 1'b0;
            c_addr                 <= address_mat_c + address_stride_c;
            c_shift                <= '0;
        end else if (counter >= MAT_MUL_SIZE) begin
            c_addr                 <= c_addr + address_stride_c;
            c_shift                <= {c_data_in, c_shift[MAT_MUL_SIZE-1:1]};
        end else if (start_capturing_c_data) begin
            c_data_available       <= 1'b1;
            c_addr                 <= c_addr + address_stride_c;
            counter                <= counter + 1;
            c_shift                <= {c_data_in, c_shift[MAT_MUL_SIZE-1:1]};
        end
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// Systolic data setup for one input matrix
// (instantiated once for A and once for B; the logic is identical)
//////////////////////////////////////////////////////////////////////////
module systolic_data_setup
    import matmul_pkg::*;
(
    input  logic                         clk,
    input  logic                         reset,
    input  logic                         start_mat_mul,
    input  logic [7:0]                   clk_cnt,
    input  logic [7:0]                   final_mat_mul_size,
    input  logic [7:0]                   loc,                         //a_loc for A, b_loc for B
    input  logic [AWIDTH-1:0]            address_mat,
    input  logic [ADDR_STRIDE_WIDTH-1:0] address_stride,
    input  logic [MASK_WIDTH-1:0]        validity_mask_a_cols_b_rows,
    input  logic [MASK_WIDTH-1:0]        validity_mask_lanes,         //validity_mask_a_rows for A, validity_mask_b_cols for B
    output logic [AWIDTH-1:0]            mem_addr,
    input  vec_t                         mem_data,
    output vec_t                         data_skewed                  //lane i is delayed by i cycles
);

//////////////////////////////////////////////////////////////////////////
// Logic to generate addresses to BRAM
//////////////////////////////////////////////////////////////////////////
    logic       mem_access; //flag that tells whether the matmul is trying to access memory or not
    logic [7:0] access_start, access_end;

    assign access_start = loc << LOG2_MAT_MUL_SIZE;
    assign access_end   = access_start + final_mat_mul_size;

    always_ff @(posedge clk) begin
        if (reset || !start_mat_mul || clk_cnt >= access_end) begin
            mem_addr   <= address_mat - address_stride;
            mem_access <= 1'b0;
        end else if (clk_cnt >= access_start) begin
            mem_addr   <= mem_addr + address_stride;
            mem_access <= 1'b1;
        end
    end

//////////////////////////////////////////////////////////////////////////
// Logic to generate valid signals for data coming from BRAM
//////////////////////////////////////////////////////////////////////////
    logic [7:0] mem_access_counter;

    always_ff @(posedge clk) begin
        if (reset || !start_mat_mul || !mem_access) mem_access_counter <= '0;
        else                                         mem_access_counter <= mem_access_counter + 1'b1;
    end

    //flag that tells whether the data from memory is valid:
    //access k+1 is invalid when column/row k of the shared dimension is masked off
    logic data_valid;

    always_comb begin
        data_valid = (mem_access_counter >= MEM_ACCESS_LATENCY);
        for (int k = 0; k < MAT_MUL_SIZE; k++)
            if (!validity_mask_a_cols_b_rows[k] && mem_access_counter == k + 1) data_valid = 1'b0;
    end

//////////////////////////////////////////////////////////////////////////
// Logic to delay certain parts of the data received from BRAM (systolic data setup)
//////////////////////////////////////////////////////////////////////////
//Slice data into chunks and qualify it with whether it is valid or not
    vec_t data_masked;

    always_comb begin
        for (int i = 0; i < MAT_MUL_SIZE; i++)
            data_masked[i] = (data_valid && validity_mask_lanes[i]) ? mem_data[i] : '0;
    end

//dly[d] is data_masked delayed by d cycles. Lane i is taken from dly[i];
//the unused lanes of each stage are optimized away by synthesis.
    vec_t dly [1:MAT_MUL_SIZE-1];

    always_ff @(posedge clk) begin
        if (reset || !start_mat_mul || clk_cnt == 0) begin
            dly <= '{default: '0};
        end else begin
            dly[1] <= data_masked;
            for (int d = 2; d < MAT_MUL_SIZE; d++) dly[d] <= dly[d-1];
        end
    end

    always_comb begin
        data_skewed[0] = data_masked[0];
        for (int i = 1; i < MAT_MUL_SIZE; i++) data_skewed[i] = dly[i][i];
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// Systolically connected PEs
//////////////////////////////////////////////////////////////////////////
module systolic_pe_matrix
    import matmul_pkg::*;
(
    input  logic clk,
    input  logic reset,
    input  logic pe_reset,
    input  vec_t a_pe,       //a_pe[i] enters row i of the mesh from the left
    input  vec_t b_pe,       //b_pe[j] enters column j of the mesh from the top
    output mat_t c_cols,     //c_cols[j][i] is the result of PE(i,j), i.e. C[i][j]
    output vec_t a_data_out, //values leaving the right edge, one per row
    output vec_t b_data_out,  //values leaving the bottom edge, one per column
    output logic [4:0] exception_flags
);

    logic effective_rst;
    assign effective_rst = reset | pe_reset;

    // PE(i,j) is at row i, column j. a_pe enters from the left; b_pe enters from the top.
    // a_h flows right and b_v flows down; their final indices are the mesh outputs.
    // All PEs share the same clock and reset.
    data_t a_h [MAT_MUL_SIZE][MAT_MUL_SIZE+1];
    data_t b_v [MAT_MUL_SIZE+1][MAT_MUL_SIZE];
    // One 5-bit exception vector from each of the PEs. 
    logic [4:0] pe_flags [MAT_MUL_SIZE][MAT_MUL_SIZE];

    for (genvar i = 0; i < MAT_MUL_SIZE; i++) begin : g_row
        assign a_h[i][0]     = a_pe[i];
        assign b_v[0][i]     = b_pe[i];
        assign a_data_out[i] = a_h[i][MAT_MUL_SIZE];
        assign b_data_out[i] = b_v[MAT_MUL_SIZE][i];

        for (genvar j = 0; j < MAT_MUL_SIZE; j++) begin : g_col
            processing_element pe (
                .clk,
                .reset(effective_rst),
                .in_a (a_h[i][j]),
                .in_b (b_v[i][j]),
                .out_a(a_h[i][j+1]),
                .out_b(b_v[i+1][j]),
                .out_c(c_cols[j][i]),
                .flags(pe_flags[i][j]));
        end
    end

    // OR the exception vectors from all the PEs.
    always_comb begin
        exception_flags = '0;
        for (int k = 0; k < MAT_MUL_SIZE; k++)
            for (int l = 0; l < MAT_MUL_SIZE; l++)
                exception_flags |= pe_flags[k][l];
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// Processing element (PE)
//////////////////////////////////////////////////////////////////////////
module processing_element
    import matmul_pkg::*;
(
    input  logic  clk,
    input  logic  reset,
    input  data_t in_a,
    input  data_t in_b,
    output data_t out_a,
    output data_t out_b,
    output data_t out_c,
    output logic [4:0] flags
);

    seq_mac u_mac (.*, .a(in_a), .b(in_b), .out(out_c), .flags(flags));

    always_ff @(posedge clk) begin
        if (reset) {out_a, out_b} <= '0;
        else       {out_a, out_b} <= {in_a, in_b};
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// Multiply-and-accumulate (MAC) block
//////////////////////////////////////////////////////////////////////////
module seq_mac
    import matmul_pkg::*;
(
    input  logic  clk,
    input  logic  reset,
    input  data_t a,
    input  data_t b,
    output data_t out,
    output logic [4:0] flags
);

    data_t a_flop, b_flop, mult;

    // Combinational outputs from the FP8 multiplier and adder.
    data_t      mult_result, add_result;
    logic [4:0] mult_flags, add_flags;

    FP8_Mult   u_fp8_mult (.a(a_flop), .b(b_flop), .result(mult_result), .flags(mult_flags));
    FP8_AddSub u_fp8_add  (.a(mult), .b(out), .operation(1'b0), .result(add_result), .flags(add_flags));

    // Combine exception flags from the multiplier and adder.
    assign flags = mult_flags | add_flags;

    always_ff @(posedge clk) begin
        if (reset) begin
            {out, a_flop, b_flop, mult} <= '0;
        end else begin

            // Stage 1: register incoming FP8 operands
            a_flop <= a;
            b_flop <= b;

            mult <= mult_result;    // Stage 2: register the FP8 multiplier output
            out  <= add_result;     // Stage 3: accumulate the FP8 adder output
        end
    end

endmodule
