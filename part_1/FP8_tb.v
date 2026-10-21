`timescale 1ns / 1ps

// Tests FP8_AddSub and FP8_Mult with five directed cases each, using inputs
// from fp8_e3m4_three_tables.csv.
// Define EXHAUSTIVE (e.g. +define+EXHAUSTIVE) to test all input pairs against
// an exact FP8 reference model with ties rounded to even.
module FP8_tb;

    initial begin
        $fsdbDumpfile("FP8_tb.fsdb");
        $fsdbDumpvars(0, FP8_tb);
    end

    reg  [7:0] a, b;
    reg        operation;
    wire [7:0] addsub_result, mult_result;
    wire [4:0] addsub_flags, mult_flags;

    FP8_AddSub u_addsub (.a(a), .b(b), .operation(operation), .result(addsub_result), .flags(addsub_flags));
    FP8_Mult   u_mult   (.a(a), .b(b), .result(mult_result), .flags(mult_flags));

    // FP8 E3M4 reference model (shared with part_3, see ../fp8_ref_model.vh)
`include "fp8_ref_model.vh"

    // Print an FP8 number in hex and decimal, e.g. "0x38 (1.5)"
    task show_fp8;
        input [7:0] x;
        begin
            if (is_nan(x))      $write("0x%h (NaN)", x);
            else if (is_inf(x)) $write("0x%h (%sinf)", x, x[7] ? "-" : "+");
            else                $write("0x%h (%g)", x, value(x));
        end
    endtask

    //////////////////////////////////////////////////////////////////////////////
    // Directed test cases
    //////////////////////////////////////////////////////////////////////////////
    integer tests_addsub, passed_addsub, tests_mult, passed_mult;

    task check_addsub;
        input [7:0] x;
        input [7:0] y;
        input       op;
        input [7:0] exp_res;
        input [4:0] exp_flags;
        begin
            a = x;
            b = y;
            operation = op;
            #10;
            tests_addsub = tests_addsub + 1;
            $write("    A = "); show_fp8(a); $write("  %s  B = ", op ? "-" : "+"); show_fp8(b); $write("\n");
            $write("    Result   = "); show_fp8(addsub_result); $write("  flags = %b\n", addsub_flags);
            $write("    Expected = "); show_fp8(exp_res);       $write("  flags = %b", exp_flags);
            if (addsub_result === exp_res && addsub_flags === exp_flags) begin
                passed_addsub = passed_addsub + 1;
                $display("  -> PASS");
            end else begin
                $display("  -> FAIL");
            end
        end
    endtask

    task check_mult;
        input [7:0] x;
        input [7:0] y;
        input [7:0] exp_res;
        input [4:0] exp_flags;
        begin
            a = x;
            b = y;
            #10;
            tests_mult = tests_mult + 1;
            $write("    A = "); show_fp8(a); $write("  x  B = "); show_fp8(b); $write("\n");
            $write("    Result   = "); show_fp8(mult_result); $write("  flags = %b\n", mult_flags);
            $write("    Expected = "); show_fp8(exp_res);     $write("  flags = %b", exp_flags);
            if (mult_result === exp_res && mult_flags === exp_flags) begin
                passed_mult = passed_mult + 1;
                $display("  -> PASS");
            end else begin
                $display("  -> FAIL");
            end
        end
    endtask

`ifdef EXHAUSTIVE
    //////////////////////////////////////////////////////////////////////////////
    // Exhaustive check against a reference model
    //////////////////////////////////////////////////////////////////////////////
    integer   i, j, op;
    integer   errors_addsub, errors_mult, checks_addsub, checks_mult;
    reg [7:0] exp_res;
    reg [4:0] exp_flags;

    task run_exhaustive;
        begin
            errors_addsub = 0;
            errors_mult   = 0;
            checks_addsub = 0;
            checks_mult   = 0;

            // FP8_AddSub: every input pair, both addition and subtraction
            for (i = 0; i < 256; i = i + 1) begin
                for (j = 0; j < 256; j = j + 1) begin
                    for (op = 0; op < 2; op = op + 1) begin
                        a = i[7:0];
                        b = j[7:0];
                        operation = op[0];
                        #1;

                        // Subtraction is addition of -b
                        ref_add(a, {b[7] ^ operation, b[6:0]}, exp_res, exp_flags);
                        checks_addsub = checks_addsub + 1;
                        if (addsub_result !== exp_res || addsub_flags !== exp_flags) begin
                            if (errors_addsub < 20)
                                $display("ADDSUB MISMATCH: %h %s %h = %h flags %b, expected %h flags %b",
                                         a, operation ? "-" : "+", b, addsub_result, addsub_flags, exp_res, exp_flags);
                            errors_addsub = errors_addsub + 1;
                        end
                    end
                end
            end

            // FP8_Mult: every input pair
            for (i = 0; i < 256; i = i + 1) begin
                for (j = 0; j < 256; j = j + 1) begin
                    a = i[7:0];
                    b = j[7:0];
                    #1;

                    ref_mult(a, b, exp_res, exp_flags);
                    checks_mult = checks_mult + 1;
                    if (mult_result !== exp_res || mult_flags !== exp_flags) begin
                        if (errors_mult < 20)
                            $display("MULT MISMATCH: %h * %h = %h flags %b, expected %h flags %b",
                                     a, b, mult_result, mult_flags, exp_res, exp_flags);
                        errors_mult = errors_mult + 1;
                    end
                end
            end

            $display("Exhaustive FP8_AddSub: %0d cases, %0d mismatches", checks_addsub, errors_addsub);
            $display("Exhaustive FP8_Mult:   %0d cases, %0d mismatches", checks_mult, errors_mult);
        end
    endtask
`endif

    reg all_passed;

    initial begin
        tests_addsub  = 0;
        passed_addsub = 0;
        tests_mult    = 0;
        passed_mult   = 0;
        a = 8'h00;
        b = 8'h00;
        operation = 1'b0;

        $display("FP8 E3M4 testbench. flags = {Overflow, Underflow, DivideByZero, Invalid, Inexact}");
        $display("");
        $display("==================== FP8_AddSub ====================");

        $display("Test 1: Addition of normal numbers, 1.5 + 2.0 = 3.5");
        check_addsub(8'h38, 8'h40, 1'b0, 8'h4C, 5'b00000);

        $display("Test 2: Subtraction with a negative result, 1.0 - 4.0 = -3.0");
        check_addsub(8'h30, 8'h50, 1'b1, 8'hC8, 5'b00000);

        $display("Test 3: Denormal inputs, 0.234375 + 0.015625 = 0.25 (smallest normal number)");
        check_addsub(8'h0F, 8'h01, 1'b0, 8'h10, 5'b00000);

        $display("Test 4: Rounding, 8.0 + 0.25 = 8.25 is halfway between 8.0 and 8.5, ties to even gives 8.0");
        check_addsub(8'h60, 8'h10, 1'b0, 8'h60, 5'b00001);

        $display("Test 5: Overflow, 15.5 + 0.25 = 15.75 is too large for FP8, so the result is +inf");
        check_addsub(8'h6F, 8'h10, 1'b0, 8'h70, 5'b10001);

        $display("");
        $display("===================== FP8_Mult =====================");

        $display("Test 1: Product with a negative input, -1.5 x 2.0 = -3.0");
        check_mult(8'hB8, 8'h40, 8'hC8, 5'b00000);

        $display("Test 2: Rounding, 15.5 x 0.375 = 5.8125, nearest FP8 value is 5.75");
        check_mult(8'h6F, 8'h18, 8'h57, 5'b00001);

        $display("Test 3: Denormal result, 0.375 x 0.234375 = 0.087890625, nearest FP8 value is 0.09375");
        check_mult(8'h18, 8'h0F, 8'h06, 5'b01001);

        $display("Test 4: Overflow, 8.0 x 4.0 = 32 is too large for FP8, so the result is +inf");
        check_mult(8'h60, 8'h50, 8'h70, 5'b10001);

        $display("Test 5: Invalid operation, 0 x inf = NaN");
        check_mult(8'h00, 8'h70, 8'h7F, 5'b00010);

        $display("");
        $display("FP8_AddSub: %0d/%0d test cases passed", passed_addsub, tests_addsub);
        $display("FP8_Mult:   %0d/%0d test cases passed", passed_mult, tests_mult);
        all_passed = (tests_addsub == 5) && (passed_addsub == 5) && (tests_mult == 5) && (passed_mult == 5);

`ifdef EXHAUSTIVE
        $display("");
        run_exhaustive;
        // Also require the full number of cases, so a loop that silently checked nothing cannot pass
        all_passed = all_passed && (errors_addsub == 0) && (errors_mult == 0)
                                && (checks_addsub == 131072) && (checks_mult == 65536);
`endif

        if (all_passed) $display("PASS");
        else            $display("FAIL");
        $finish;
    end

endmodule
