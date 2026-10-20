`timescale 1ns/1ps
// Three independently selectable cases:
//   +TEST=ones     : every result must be 8.0 (FP8 8'h60)
//   +TEST=identity : A = I, C must equal a distinct-valued B
//   +TEST=overflow : BR tile multiplies 8.0 * 8.0 and raises overflow
//
// RAM A banks are organized by
// shared-dimension COLUMN k; RAM B banks by shared-dimension ROW k;
// RAM C banks by output COLUMN j. Lanes are ordered from the LSB upward.
module tb_matmul_8x8;
    import matmul_pkg::*;

    logic clk = 1'b0;
    always #10 clk = ~clk;   // 20 ns period, same as the Part II tests.

    logic resetn, pe_resetn, start;
    logic done;
    logic [4:0] exception_flags;
    string test_case;

    // The accelerator reads from A/B internal RAM ports and writes C internal
    // RAM ports. Host ports are deliberately idle (preloaded hierarchically).
    matrix_multiplication_8x8 u_matmul (
        .clk(clk), .resetn(resetn), .pe_resetn(pe_resetn),
        .address_mat_a(10'd0), .address_mat_b(10'd0), .address_mat_c(10'd0),
        .address_stride_a(8'd1), .address_stride_b(8'd1), .address_stride_c(8'd1),
        .start(start), .done(done), .exception_flags(exception_flags),
        .bram_addr_a0_ext('0), .bram_addr_a1_ext('0),
        .bram_wdata_a0_ext('0), .bram_wdata_a1_ext('0),
        .bram_we_a0_ext('0), .bram_we_a1_ext('0),
        .bram_rdata_a0_ext(), .bram_rdata_a1_ext(),
        .bram_addr_b0_ext('0), .bram_addr_b1_ext('0),
        .bram_wdata_b0_ext('0), .bram_wdata_b1_ext('0),
        .bram_we_b0_ext('0), .bram_we_b1_ext('0),
        .bram_rdata_b0_ext(), .bram_rdata_b1_ext(),
        .bram_addr_c0_ext('0), .bram_addr_c1_ext('0),
        .bram_wdata_c0_ext('0), .bram_wdata_c1_ext('0),
        .bram_we_c0_ext('0), .bram_we_c1_ext('0),
        .bram_rdata_c0_ext(), .bram_rdata_c1_ext()
    );

    function automatic logic [7:0] b_pattern(input int row, input int col);
        // Distinct EXACT FP8 numbers; each should survive identity multiplication.
        case ((row * 3 + col) % 8)
            0: b_pattern = 8'h10; // 0.25
            1: b_pattern = 8'h20; // 0.5
            2: b_pattern = 8'h30; // 1.0
            3: b_pattern = 8'h38; // 1.5
            4: b_pattern = 8'h40; // 2.0
            5: b_pattern = 8'h48; // 3.0
            6: b_pattern = 8'h50; // 4.0
            default: b_pattern = 8'h58; // 6.0
        endcase
    endfunction

    function automatic logic [7:0] a_input(input int row, input int col);
        if (test_case == "ones")
            return 8'h30;
        if (test_case == "identity")
            return (row == col) ? 8'h30 : 8'h00;
        // For overflow, the only nonzero element of A is A[6][3].
        return ((row == 6) && (col == 3)) ? 8'h60 : 8'h00;
    endfunction

    function automatic logic [7:0] b_input(input int row, input int col);
        if (test_case == "ones")
            return 8'h30;
        if (test_case == "identity")
            return b_pattern(row, col);
        // For overflow, the only nonzero element of B is B[3][7].
        return ((row == 3) && (col == 7)) ? 8'h60 : 8'h00;
    endfunction

    function automatic logic [7:0] expected_c(input int row, input int col);
        if (test_case == "ones")
            return 8'h60;                  // 8 terms of 1.0
        if (test_case == "identity")
            return b_pattern(row, col);     // I x B = B
        return ((row == 6) && (col == 7)) ? 8'h70 : 8'h00;
    endfunction

    task automatic preload_matrices;
        // A0/A1 contain four rows each, one 32-bit vector per k = 0..7.
        // B0/B1 contain four columns each, one 32-bit vector per k = 0..7.
        // C0/C1 are intentionally initialized to a sentinel to detect no write.
        for (int k = 0; k < 8; k++) begin
            u_matmul.matrix_A0.ram[k] = '0;
            u_matmul.matrix_A1.ram[k] = '0;
            u_matmul.matrix_B0.ram[k] = '0;
            u_matmul.matrix_B1.ram[k] = '0;
            u_matmul.matrix_C0.ram[k] = 32'hDEADBEEF;
            u_matmul.matrix_C1.ram[k] = 32'hDEADBEEF;
            for (int lane = 0; lane < 4; lane++) begin
                u_matmul.matrix_A0.ram[k][8*lane +: 8] = a_input(lane, k);
                u_matmul.matrix_A1.ram[k][8*lane +: 8] = a_input(lane + 4, k);
                u_matmul.matrix_B0.ram[k][8*lane +: 8] = b_input(k, lane);
                u_matmul.matrix_B1.ram[k][8*lane +: 8] = b_input(k, lane + 4);
            end
        end
    endtask

    task automatic check_result;
        logic [7:0] observed, expected;
        int checked;
        checked = 0;
        for (int col = 0; col < 8; col++) begin
            $display("C col %0d: C0=%h C1=%h", col,
                     u_matmul.matrix_C0.ram[col], u_matmul.matrix_C1.ram[col]);
            for (int row = 0; row < 8; row++) begin
                if (row < 4)
                    observed = u_matmul.matrix_C0.ram[col][8*row +: 8];
                else
                    observed = u_matmul.matrix_C1.ram[col][8*(row-4) +: 8];
                expected = expected_c(row, col);
                if (observed !== expected)
                    $fatal(1, "FAIL %s: C[%0d][%0d]=%h, expected %h",
                           test_case, row, col, observed, expected);
                checked++;
            end
        end
        if (test_case == "overflow") begin
            if (exception_flags[4] !== 1'b1)
                $fatal(1, "FAIL: expected sticky overflow bit[4], got %b", exception_flags);
        end else if (exception_flags !== 5'b00000) begin
            $fatal(1, "FAIL: unexpected exceptions %b for %s", exception_flags, test_case);
        end
        $display("PASS: %s -- %0d/64 exact FP8 output bytes, flags=%b",
                 test_case, checked, exception_flags);
    endtask

    // Guard against a broken controller that never asserts done.
    initial begin
        #20000;
        $fatal(1, "TIMEOUT: done did not arrive for TEST=%s", test_case);
    end

    initial begin
        resetn = 1'b0;
        pe_resetn = 1'b0;
        start = 1'b0;
        if (!$value$plusargs("TEST=%s", test_case)) test_case = "ones";
        if ((test_case != "ones") && (test_case != "identity") &&
            (test_case != "overflow"))
            $fatal(1, "Unknown TEST=%s; choose ones, identity, or overflow", test_case);
`ifdef FSDB_DUMP
        $fsdbDumpfile({test_case, "_fp8.fsdb"});
        $fsdbDumpvars(0, tb_matmul_8x8, "+all");
        $fsdbDumpMDA;
`endif
        preload_matrices();
        // Reset on several rising edges to clear PE pipelines and local state.
        repeat (5) @(negedge clk);
        resetn    = 1'b1;
        pe_resetn = 1'b1;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        @(posedge done);
        // RAM writes use nonblocking assignment, so give the eighth write time
        // to settle, and allow the main FSM to bring start_mat_mul low.
        repeat (3) @(negedge clk);
        check_result();
        $finish;
    end
endmodule
