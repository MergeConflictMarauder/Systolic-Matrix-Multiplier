`timescale 1ns/1ns

//////////////////////////////////////////////////////////////////////////
// Normal FP8 matrix multiplication test
//
// Loads two 4x4 FP8 E3M4 matrices, runs one matrix multiplication and
// checks matrix C. Every product and partial sum is exactly representable
// in FP8, so no exception flag may be raised.
//
// FP8 values used:
//   0.0 = 8'h00    0.5 = 8'h20    1.0 = 8'h30    1.5 = 8'h38    2.0 = 8'h40
//
// Matrix A:                  Matrix B:
//   [1.0  0.5  2.0  1.0]       [0.5  1.0  0.0  1.5]
//   [0.5  1.0  1.5  0.0]       [1.0  0.5  1.5  0.0]
//   [2.0  1.0  0.5  1.5]       [0.0  1.0  0.5  1.0]
//   [1.5  0.0  1.0  0.5]       [1.5  0.0  1.0  0.5]
//////////////////////////////////////////////////////////////////////////
module matmul_tb;

    reg        clk;
    reg        resetn;
    reg        pe_resetn;
    reg        start;
    wire       done;
    wire [4:0] exception_flags;

    // Expected matrix C: each RAM address holds one column of C,
    // with the row-0 element in the least-significant byte.
    localparam [31:0] EXPECTED_C0 = 32'h38513444;
    localparam [31:0] EXPECTED_C1 = 32'h4448444A;
    localparam [31:0] EXPECTED_C2 = 32'h304A4246;
    localparam [31:0] EXPECTED_C3 = 32'h4C514250;

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
        u_matmul.matrix_A.ram[0] = 32'h38402030;
        u_matmul.matrix_A.ram[1] = 32'h00303020;
        u_matmul.matrix_A.ram[2] = 32'h30203840;
        u_matmul.matrix_A.ram[3] = 32'h20380030;

        // Matrix B: each RAM address holds one row of B,
        // with the column-0 element in the least-significant byte.
        u_matmul.matrix_B.ram[0] = 32'h38003020;
        u_matmul.matrix_B.ram[1] = 32'h00382030;
        u_matmul.matrix_B.ram[2] = 32'h30203000;
        u_matmul.matrix_B.ram[3] = 32'h20300038;
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
        $display("MATRIX MULTIPLICATION - NORMAL MATRIX TEST");
        $display("C RAM[0] = %h  Expected = %h", u_matmul.matrix_C.ram[0], EXPECTED_C0);
        $display("C RAM[1] = %h  Expected = %h", u_matmul.matrix_C.ram[1], EXPECTED_C1);
        $display("C RAM[2] = %h  Expected = %h", u_matmul.matrix_C.ram[2], EXPECTED_C2);
        $display("C RAM[3] = %h  Expected = %h", u_matmul.matrix_C.ram[3], EXPECTED_C3);
        $display("exception_flags = %b", exception_flags);
        $display("--------------------------------------------------");

        if ((u_matmul.matrix_C.ram[0] === EXPECTED_C0) &&
            (u_matmul.matrix_C.ram[1] === EXPECTED_C1) &&
            (u_matmul.matrix_C.ram[2] === EXPECTED_C2) &&
            (u_matmul.matrix_C.ram[3] === EXPECTED_C3) &&
            (exception_flags === 5'b00000))
            $display("NORMAL MATRIX TEST PASSED");
        else
            $display("NORMAL MATRIX TEST FAILED");

        #40;
        $finish;
    end

    //////////////////////////////////////////////////////////////////////
    // Waveform dump (Verdi FSDB)
    //////////////////////////////////////////////////////////////////////
    initial begin
        $fsdbDumpfile("normal_fp8.fsdb");
        $fsdbDumpvars(0, matmul_tb, "+all");
        $fsdbDumpMDA;
    end

endmodule
