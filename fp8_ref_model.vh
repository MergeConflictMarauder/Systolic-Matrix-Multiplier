//////////////////////////////////////////////////////////////////////////
// FP8 E3M4 reference model, shared by the part_1 and part_3 testbenches.
//
// Include this file inside a testbench module:
//     `include "fp8_ref_model.vh"
// and compile with +incdir+.. from the part_N folder.
//
// The model decodes FP8 values to real numbers, computes the exact result
// and rounds it by searching all finite FP8 values for the nearest one
// (ties to even). It shares no logic with the FP8_AddSub / FP8_Mult designs.
//
//   ref_add (x, y, res, flags) : res = x + y   (for x - y, flip the sign bit of y)
//   ref_mult(x, y, res, flags) : res = x * y
//   flags = {Overflow, Underflow, DivideByZero, Invalid, Inexact}
//////////////////////////////////////////////////////////////////////////

localparam [7:0] QNAN       = 8'h7F;            // NaN produced by the designs
localparam [6:0] INF        = 7'h70;            // Infinity without sign
localparam [6:0] MAX_FINITE = 7'h6F;            // 15.5
localparam real  OVERFLOW_THRESHOLD = 15.75;    // Exact results at or above this round to infinity
localparam real  MIN_NORMAL         = 0.25;

// Flag bits
localparam OVERFLOW = 4, UNDERFLOW = 3, INVALID = 1, INEXACT = 0;

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
        if (e == 0) magnitude = m / 64.0;                       // Denormal: 0.mmmm x 2^-2
        else        magnitude = ((16 + m) << (e - 1)) / 64.0;   // Normal:   1.mmmm x 2^(e-3)
    end
endfunction

function real value;
    input [7:0] x;
    value = x[7] ? -magnitude(x[6:0]) : magnitude(x[6:0]);
endfunction

// Round a nonzero exact result to the nearest FP8 value (ties to even)
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

task ref_add;
    input  [7:0] x;
    input  [7:0] y;
    output [7:0] res;
    output [4:0] flags;
    real         r;
    begin
        flags = 5'b00000;
        if (is_nan(x) || is_nan(y)) begin
            res = QNAN;
        end else if (is_inf(x) && is_inf(y) && (x[7] != y[7])) begin
            res = QNAN;                                 // Infinity minus infinity
            flags[INVALID] = 1'b1;
        end else if (is_inf(x)) begin
            res = x;
        end else if (is_inf(y)) begin
            res = y;
        end else begin
            r = value(x) + value(y);
            if (r == 0.0) res = {x[7] & y[7], 7'h00};   // Exact zero is +0, except (-0) + (-0)
            else          round_fp8(r, res, flags);
        end
    end
endtask

task ref_mult;
    input  [7:0] x;
    input  [7:0] y;
    output [7:0] res;
    output [4:0] flags;
    real         r;
    begin
        flags = 5'b00000;
        if (is_nan(x) || is_nan(y)) begin
            res = QNAN;
        end else if ((is_inf(x) && is_zero(y)) || (is_zero(x) && is_inf(y))) begin
            res = QNAN;                                 // Zero times infinity
            flags[INVALID] = 1'b1;
        end else if (is_inf(x) || is_inf(y)) begin
            res = {x[7] ^ y[7], INF};
        end else begin
            r = value(x) * value(y);
            if (r == 0.0) res = {x[7] ^ y[7], 7'h00};
            else          round_fp8(r, res, flags);
        end
    end
endtask
