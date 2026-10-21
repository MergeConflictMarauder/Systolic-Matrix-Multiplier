`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// 8x8 FP8 E3M4 matrix multiplier testbench.
// Select +TEST=ones (default) or +TEST=random. Random mode runs 10 back-to-back
// matrix pairs without PE reset; set +SEED=<n> (default 1).
// Checks all 64 outputs and exception flags against an FP8 reference model
// (round-to-nearest, ties-to-even). RAM words pack four lanes, lane 0 low.
// Reports PASS/FAIL. Define FSDB_DUMP to write <test>_fp8.fsdb for Verdi.
//////////////////////////////////////////////////////////////////////////
module matmul_tb;

    reg        clk;
    reg        resetn;
    reg        pe_resetn;
    reg        start;
    wire       done;
    wire [4:0] exception_flags;

    localparam T_ONES = 0, T_RANDOM = 1;
    localparam NUM_RANDOM_RUNS = 10;

    integer          test_id;
    integer          seed;
    reg [8*16-1:0]   test_name;

    reg  [7:0] mat_a [0:7][0:7];                // A[row][k]
    reg  [7:0] mat_b [0:7][0:7];                // B[k][col]
    reg  [7:0] exp_c [0:7][0:7];                // Expected C[row][col]
    reg  [4:0] exp_flags;                       // Expected exception flags

    integer runs, errors;

    //////////////////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////////////////
    matrix_multiplication_8x8 u_matmul (
        .clk              (clk),
        .resetn           (resetn),
        .pe_resetn        (pe_resetn),
        .address_mat_a    (10'd0),
        .address_mat_b    (10'd0),
        .address_mat_c    (10'd0),
        .address_stride_a (8'd1),
        .address_stride_b (8'd1),
        .address_stride_c (8'd1),
        .start            (start),
        .done             (done),
        .exception_flags  (exception_flags),

        // External RAM ports are unused: the RAMs are loaded and read hierarchically
        .bram_addr_a0_ext (10'b0), .bram_wdata_a0_ext(32'b0), .bram_we_a0_ext(4'b0), .bram_rdata_a0_ext(),
        .bram_addr_a1_ext (10'b0), .bram_wdata_a1_ext(32'b0), .bram_we_a1_ext(4'b0), .bram_rdata_a1_ext(),
        .bram_addr_b0_ext (10'b0), .bram_wdata_b0_ext(32'b0), .bram_we_b0_ext(4'b0), .bram_rdata_b0_ext(),
        .bram_addr_b1_ext (10'b0), .bram_wdata_b1_ext(32'b0), .bram_we_b1_ext(4'b0), .bram_rdata_b1_ext(),
        .bram_addr_c0_ext (10'b0), .bram_wdata_c0_ext(32'b0), .bram_we_c0_ext(4'b0), .bram_rdata_c0_ext(),
        .bram_addr_c1_ext (10'b0), .bram_wdata_c1_ext(32'b0), .bram_we_c1_ext(4'b0), .bram_rdata_c1_ext()
    );

    //////////////////////////////////////////////////////////////////////
    // Clock generation (20 ns period)
    //////////////////////////////////////////////////////////////////////
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    //////////////////////////////////////////////////////////////////////
    // FP8 E3M4 reference model (shared with part_1, see ../fp8_ref_model.vh)
    //////////////////////////////////////////////////////////////////////
`include "fp8_ref_model.vh"

    // Expected C and flags, accumulating in the same order as the PEs
    task compute_expected;
        integer   i, j, k;
        reg [7:0] product, sum;
        reg [4:0] mult_flags, add_flags;
        begin
            exp_flags = 5'b00000;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    sum = 8'h00;
                    for (k = 0; k < 8; k = k + 1) begin
                        ref_mult(mat_a[i][k], mat_b[k][j], product, mult_flags);
                        ref_add(product, sum, sum, add_flags);
                        exp_flags = exp_flags | mult_flags | add_flags;
                    end
                    exp_c[i][j] = sum;
                end
            end
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Test matrices
    //////////////////////////////////////////////////////////////////////
    // All elements of A and B are 1.0
    task set_ones_matrices;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    mat_a[i][j] = 8'h30;    // 1.0
                    mat_b[i][j] = 8'h30;
                end
            end
        end
    endtask

    // Random finite FP8 value.
    //   mode 0: any finite value
    //   mode 1: |x| < 1 (exponent 0-2), so sums stay finite and most results need rounding
    //   mode 2: sparse, one value in four is zero and the rest have |x| < 2
    task rand_fp8;
        input  integer mode;
        output [7:0]   x;
        reg    [31:0]  r;
        reg    [2:0]   e;
        begin
            r = $random(seed);
            case (mode)
                0:       e = r[14:12] % 7;
                1:       e = r[14:12] % 3;
                default: e = r[14:12] % 4;
            endcase
            x = {r[7], e, r[3:0]};
            if (mode == 2 && r[21:20] == 2'b00) x = 8'h00;
        end
    endtask

    task set_random_matrices;
        input integer mode;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    rand_fp8(mode, mat_a[i][j]);
                    rand_fp8(mode, mat_b[i][j]);
                end
            end
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Load the RAMs, run one multiplication and check C
    //////////////////////////////////////////////////////////////////////
    task load_rams;
        integer    k, lane;
        reg [31:0] word_a0, word_a1, word_b0, word_b1;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    word_a0[8*lane +: 8] = mat_a[lane][k];
                    word_a1[8*lane +: 8] = mat_a[lane + 4][k];
                    word_b0[8*lane +: 8] = mat_b[k][lane];
                    word_b1[8*lane +: 8] = mat_b[k][lane + 4];
                end
                u_matmul.matrix_A0.ram[k] = word_a0;
                u_matmul.matrix_A1.ram[k] = word_a1;
                u_matmul.matrix_B0.ram[k] = word_b0;
                u_matmul.matrix_B1.ram[k] = word_b1;

                // Sentinel, so a missing C write is detected
                u_matmul.matrix_C0.ram[k] = 32'hDEADBEEF;
                u_matmul.matrix_C1.ram[k] = 32'hDEADBEEF;
            end
        end
    endtask

    task run_matmul;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            // Wait for the multiplication to complete, then let the last C write
            // finish and the control FSM return to idle
            @(posedge done);
            repeat (3) @(negedge clk);
            runs = runs + 1;
        end
    endtask

    task check_result;
        input      show_c;      // Print every column of C
        integer    i, j;
        reg [31:0] word_c0, word_c1;
        reg [7:0]  observed;
        begin
            for (j = 0; j < 8; j = j + 1) begin
                word_c0 = u_matmul.matrix_C0.ram[j];
                word_c1 = u_matmul.matrix_C1.ram[j];
                if (show_c)
                    $display("C col %0d: C0 = %h  C1 = %h", j, word_c0, word_c1);
                for (i = 0; i < 8; i = i + 1) begin
                    observed = (i < 4) ? word_c0[8*i +: 8] : word_c1[8*(i - 4) +: 8];
                    if (observed !== exp_c[i][j]) begin
                        if (errors < 10)
                            $display("  MISMATCH (run %0d): C[%0d][%0d] = %h, expected %h",
                                     runs, i, j, observed, exp_c[i][j]);
                        errors = errors + 1;
                    end
                end
            end
            if (exception_flags !== exp_flags) begin
                if (errors < 10)
                    $display("  MISMATCH (run %0d): exception_flags = %b, expected %b",
                             runs, exception_flags, exp_flags);
                errors = errors + 1;
            end
        end
    endtask

    task write_test_name;
        if (test_id == T_ONES) $write("ones");
        else                   $write("random");
    endtask

    //////////////////////////////////////////////////////////////////////
    // Main sequence
    //////////////////////////////////////////////////////////////////////
    integer run;

    initial begin
        resetn    = 1'b0;
        pe_resetn = 1'b0;
        start     = 1'b0;
        runs      = 0;
        errors    = 0;

        if (!$value$plusargs("TEST=%s", test_name)) test_name = "ones";
        if (!$value$plusargs("SEED=%d", seed))      seed = 1;

        if      (test_name == "ones")   test_id = T_ONES;
        else if (test_name == "random") test_id = T_RANDOM;
        else begin
            $display("FAIL: unknown test, use +TEST=ones or random");
            $finish;
        end

`ifdef FSDB_DUMP
        if (test_id == T_ONES) $fsdbDumpfile("ones_fp8.fsdb");
        else                   $fsdbDumpfile("random_fp8.fsdb");
        $fsdbDumpvars(0, matmul_tb, "+all");
        $fsdbDumpMDA;
`endif

        $display("--------------------------------------------------");
        $write("8x8 FP8 MATRIX MULTIPLICATION - TEST: ");
        write_test_name;
        $display("");

        // Hold reset for several clocks to clear the PE pipelines and control state
        repeat (5) @(negedge clk);
        resetn    = 1'b1;
        pe_resetn = 1'b1;

        if (test_id == T_RANDOM) begin
            $display("seed = %0d, %0d runs", seed, NUM_RANDOM_RUNS);
            for (run = 0; run < NUM_RANDOM_RUNS; run = run + 1) begin
                set_random_matrices(run % 3);
                compute_expected;
                load_rams;
                run_matmul;
                check_result(1'b0);
            end
        end else begin
            set_ones_matrices;
            compute_expected;
            load_rams;
            run_matmul;
            check_result(1'b1);
        end

        $display("%0d run(s), %0d mismatches, exception_flags = %b", runs, errors, exception_flags);
        $display("--------------------------------------------------");
        if (errors == 0 && runs > 0) $write("PASS: ");
        else                         $write("FAIL: ");
        write_test_name;
        $display("");
        $finish;
    end

    // Guard against a controller that never asserts done
    initial begin
        #1_000_000;
        $display("FAIL: timeout, done was not asserted");
        $finish;
    end

endmodule
