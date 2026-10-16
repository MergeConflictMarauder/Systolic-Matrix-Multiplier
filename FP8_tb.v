`timescale 1ns / 1ps

// Tests FP8_AddSub and FP8_Mult with five directed cases each, using inputs
// from fp8_e3m4_three_tables.csv.
// Define EXHAUSTIVE (e.g. +define+EXHAUSTIVE) to test all input pairs against
// an exact FP8 reference model with ties rounded to even.
module FP8_tb;

    reg  [7:0] a, b;
    reg        operation;
    wire [7:0] addsub_result, mult_result;
    wire [4:0] addsub_flags, mult_flags;

    FP8_AddSub u_addsub (.a(a), .b(b), .operation(operation), .result(addsub_result), .flags(addsub_flags));
    FP8_Mult   u_mult   (.a(a), .b(b), .result(mult_result), .flags(mult_flags));

    function is_nan;
        input [7:0] x;
        is_nan = (x[6:4] == 3'b111) && (x[3:0] != 4'd0);
    endfunction

    function is_inf;
        input [7:0] x;
        is_inf = (x[6:4] == 3'b111) && (x[3:0] == 4'd0);
    endfunction

    function is_zero;
        input [7:0] x;
        is_zero = (x[6:0] == 7'd0);
    endfunction

    // Magnitude of a finite FP8 number. Every finite FP8 value is a whole number of 1/64ths.
    function real magnitude;
        input [6:0] x;
        integer m, e;
        begin
            m = x[3:0];
            e = x[6:4];
            if (e == 0) magnitude = m / 64.0;                       // denormal: 0.mmmm x 2^-2
            else        magnitude = ((16 + m) << (e - 1)) / 64.0;   // normal:   1.mmmm x 2^(e-3)
        end
    endfunction

    function real value;
        input [7:0] x;
        value = x[7] ? -magnitude(x[6:0]) : magnitude(x[6:0]);
    endfunction

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
    localparam [7:0] QNAN       = 8'h7F;            // NaN produced by the designs
    localparam [6:0] INF        = 7'h70;            // Infinity without sign
    localparam [6:0] MAX_FINITE = 7'h6F;            // 15.5
    localparam real  OVERFLOW_THRESHOLD = 15.75;    // exact results at or above this round to infinity
    localparam real  MIN_NORMAL         = 0.25;

    // Flag bits
    localparam OVERFLOW = 4, UNDERFLOW = 3, INVALID = 1, INEXACT = 0;

    // Round a nonzero exact result to FP8 and compute the overflow, underflow and inexact flags
    task round_fp8;
        input  real  r;
        output [7:0] res;
        output [4:0] flags;
        real         mag, best_err, err;
        reg          sign;
        reg    [6:0] best;
        integer      x;
        begin
            mag   = (r < 0.0) ? -r : r;
            sign  = (r < 0.0);
            flags = 5'b00000;
            if (mag >= OVERFLOW_THRESHOLD) begin
                res = {sign, INF};
                flags[OVERFLOW] = 1'b1;
                flags[INEXACT]  = 1'b1;
            end else begin
                best     = 7'd0;
                best_err = mag;
                for (x = 1; x <= MAX_FINITE; x = x + 1) begin
                    err = magnitude(x[6:0]) - mag;
                    if (err < 0.0) err = -err;
                    if (err < best_err || (err == best_err && x[0] == 1'b0)) begin
                        best     = x[6:0];
                        best_err = err;
                    end
                end
                res = {sign, best};
                flags[INEXACT]   = (best_err != 0.0);
                flags[UNDERFLOW] = (best_err != 0.0) && (mag < MIN_NORMAL);
            end
        end
    endtask

    task ref_addsub;
        input  [7:0] x;
        input  [7:0] y;
        input        op;
        output [7:0] res;
        output [4:0] flags;
        reg          sy;        // effective sign of y
        real         r;
        begin
            sy    = y[7] ^ op;
            flags = 5'b00000;
            if (is_nan(x) || is_nan(y)) begin
                res = QNAN;
            end else if (is_inf(x) && is_inf(y) && (x[7] != sy)) begin
                res = QNAN;
                flags[INVALID] = 1'b1;
            end else if (is_inf(x)) begin
                res = {x[7], INF};
            end else if (is_inf(y)) begin
                res = {sy, INF};
            end else begin
                r = value(x) + (sy ? -magnitude(y[6:0]) : magnitude(y[6:0]));
                if (r == 0.0) res = {x[7] & sy, 7'h00};    // exact zero is +0, except (-0) + (-0)
                else          round_fp8(r, res, flags);
            end
        end
    endtask

    task ref_mult;
        input  [7:0] x;
        input  [7:0] y;
        output [7:0] res;
        output [4:0] flags;
        reg          sp;
        real         r;
        begin
            sp    = x[7] ^ y[7];
            flags = 5'b00000;
            if (is_nan(x) || is_nan(y)) begin
                res = QNAN;
            end else if ((is_inf(x) && is_zero(y)) || (is_zero(x) && is_inf(y))) begin
                res = QNAN;
                flags[INVALID] = 1'b1;
            end else if (is_inf(x) || is_inf(y)) begin
                res = {sp, INF};
            end else begin
                r = value(x) * value(y);
                if (r == 0.0) res = {sp, 7'h00};
                else          round_fp8(r, res, flags);
            end
        end
    endtask

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

                        ref_addsub(a, b, operation, exp_res, exp_flags);
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
