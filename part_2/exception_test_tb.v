`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////
// Exception FP8 matrix multiplication test
//
// Loads two 4x4 FP8 E3M4 matrices that include an 8.0 x 8.0 multiplication.
// The product (64.0) exceeds the largest finite FP8 E3M4 value (15.5), so it
// overflows.
//
// Expected behavior:
//   - At least one exception flag is raised during the computation,
//     so exception_seen becomes 1.
//   - C[0][0] becomes +infinity (8'h70).
//
// FP8 values used:
//   0.0 = 8'h00    0.5 = 8'h20    1.0 = 8'h30    8.0 = 8'h60
//
// Matrix A:                  Matrix B:
//   [8.0  1.0  0.0  0.0]       [8.0  0.0  0.0  0.0]
//   [0.0  1.0  0.5  0.0]       [0.0  1.0  1.0  0.0]
//   [0.0  0.0  1.0  1.0]       [0.0  0.5  1.0  0.0]
//   [0.5  0.0  0.0  1.0]       [0.0  0.0  0.5  1.0]
//////////////////////////////////////////////////////////////////////////
module matmul_tb;

    reg        clk;
    reg        resetn;
    reg        pe_resetn;
    reg        start;
    wire       done;
    wire [4:0] exception_flags;
    reg        exception_seen;      // Set once any exception flag is raised

    // Expected matrix C: each RAM address holds one column of C,
    // with the row-0 element in the least-significant byte.
    localparam [31:0] EXPECTED_C0 = 32'h50000070;
    localparam [31:0] EXPECTED_C1 = 32'h00203430;
    localparam [31:0] EXPECTED_C2 = 32'h20383830;
    localparam [31:0] EXPECTED_C3 = 32'h30300000;

    //////////////////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////////////////
    matrix_multiplication u_matmul (
        .clk             (clk),
        .resetn          (resetn),
        .pe_resetn       (pe_resetn),
        .address_mat_a   (10'b0),
        .address_mat_b   (10'b0),
        .address_mat_c   (10'b0),
        .address_stride_a(8'd1),
        .address_stride_b(8'd1),
        .address_stride_c(8'd1),

        // External RAM ports are unused in this testbench
        .bram_addr_a_ext (10'b0),
        .bram_rdata_a_ext(),
        .bram_wdata_a_ext(32'b0),
        .bram_we_a_ext   (4'b0),

        .bram_addr_b_ext (10'b0),
        .bram_rdata_b_ext(),
        .bram_wdata_b_ext(32'b0),
        .bram_we_b_ext   (4'b0),

        .bram_addr_c_ext (10'b0),
        .bram_rdata_c_ext(),
        .bram_wdata_c_ext(32'b0),
        .bram_we_c_ext   (4'b0),

        .start           (start),
        .done            (done),
        .exception_flags (exception_flags)
    );

    //////////////////////////////////////////////////////////////////////
    // Remember whether any exception occurs during the multiplication
    //////////////////////////////////////////////////////////////////////
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            exception_seen <= 1'b0;
        else if (exception_flags != 5'b00000)
            exception_seen <= 1'b1;
    end

    //////////////////////////////////////////////////////////////////////
    // Clock generation (20 ns period)
    //////////////////////////////////////////////////////////////////////
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    //////////////////////////////////////////////////////////////////////
    // Reset
    //////////////////////////////////////////////////////////////////////
    initial begin
        resetn    = 1'b0;
        pe_resetn = 1'b0;
        #55;
        resetn    = 1'b1;
        pe_resetn = 1'b1;
    end

    //////////////////////////////////////////////////////////////////////
    // Load matrices A and B
    //////////////////////////////////////////////////////////////////////
    initial begin
        // Matrix A: each RAM address holds one column of A,
        // with the row-0 element in the least-significant byte.
        u_matmul.matrix_A.ram[0] = 32'h20000060;
        u_matmul.matrix_A.ram[1] = 32'h00003030;
        u_matmul.matrix_A.ram[2] = 32'h00302000;
        u_matmul.matrix_A.ram[3] = 32'h30300000;

        // Matrix B: each RAM address holds one row of B,
        // with the column-0 element in the least-significant byte.
        u_matmul.matrix_B.ram[0] = 32'h00000060;
        u_matmul.matrix_B.ram[1] = 32'h00303000;
        u_matmul.matrix_B.ram[2] = 32'h00302000;
        u_matmul.matrix_B.ram[3] = 32'h30200000;
    end

    //////////////////////////////////////////////////////////////////////
    // Start the multiplication and check the result
    //////////////////////////////////////////////////////////////////////
    initial begin
        start = 1'b0;

        // Wait until reset has been released
        wait (resetn == 1'b1 && pe_resetn == 1'b1);

        // Pulse start on falling edges to avoid races with the DUT
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        // Wait for the matrix multiplication to complete,
        // then allow the final RAM write to finish
        @(posedge done);
        repeat (2) @(posedge clk);

        $display("--------------------------------------------------");
        $display("MATRIX MULTIPLICATION - EXCEPTION TEST");
        $display("C RAM[0] = %h  Expected = %h", u_matmul.matrix_C.ram[0], EXPECTED_C0);
        $display("C RAM[1] = %h  Expected = %h", u_matmul.matrix_C.ram[1], EXPECTED_C1);
        $display("C RAM[2] = %h  Expected = %h", u_matmul.matrix_C.ram[2], EXPECTED_C2);
        $display("C RAM[3] = %h  Expected = %h", u_matmul.matrix_C.ram[3], EXPECTED_C3);
        $display("exception_flags now = %b", exception_flags);
        $display("exception_seen      = %b", exception_seen);
        $display("--------------------------------------------------");

        if ((u_matmul.matrix_C.ram[0] === EXPECTED_C0) &&
            (u_matmul.matrix_C.ram[1] === EXPECTED_C1) &&
            (u_matmul.matrix_C.ram[2] === EXPECTED_C2) &&
            (u_matmul.matrix_C.ram[3] === EXPECTED_C3) &&
            (exception_seen === 1'b1))
            $display("EXCEPTION MATRIX TEST PASSED");
        else
            $display("EXCEPTION MATRIX TEST FAILED");

        #40;
        $finish;
    end

    //////////////////////////////////////////////////////////////////////
    // Waveform dump (Verdi FSDB)
    //////////////////////////////////////////////////////////////////////
    initial begin
        $fsdbDumpfile("exception_fp8.fsdb");
        $fsdbDumpvars(0, matmul_tb, "+all");
        $fsdbDumpMDA;
    end

endmodule
