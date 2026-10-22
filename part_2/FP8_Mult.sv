`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
// Module Name:    FP8_Mult
// Project Name:   Systolic Matrix Multiplier
// Based on:       FPMult (DSP48E1-FP-master/src/FPMult) by Fredrik Brosser
//
// Description:    Combinational multiplier for FP8 E3M4 numbers.
//                 Same stage breakdown as the 32-bit FPMult (Prep, Execute,
//                 Normalize, Round, Exception), with the pipeline registers removed.
//
// FP8 E3M4 format: [7] sign | [6:4] exponent (bias 3) | [3:0] mantissa
//                  exponent 000      : zero (mantissa 0) or denormal, 0.mmmm x 2^-2
//                  exponent 001..110 : normal number, 1.mmmm x 2^(exponent-3), 0.25 .. 15.5
//                  exponent 111      : infinity (mantissa 0) or NaN (mantissa != 0)
//
// Rounding:       Round to nearest, tie to even. Results that round above 15.5
//                 become infinity. Denormal inputs and results are supported.
//                 NaN inputs are treated as quiet NaNs; every NaN result is 8'h7F.
//
// Inputs:
//                 a (8 bits)          : FP8 E3M4 number
//                 b (8 bits)          : FP8 E3M4 number
//
// Outputs:
//                 result (8 bits)     : Product, FP8 E3M4 number
//                 flags (5 bits)      : Flags indicating exceptions:
//                                          Bit 4: Overflow
//                                          Bit 3: Underflow (tiny and inexact)
//                                          Bit 2: Divide by Zero (always 0)
//                                          Bit 1: Invalid (zero x infinity)
//                                          Bit 0: Inexact
//
//////////////////////////////////////////////////////////////////////////////////

module FP8_Mult (
    input  logic [7:0] a,           // Input A, an FP8 E3M4 number
    input  logic [7:0] b,           // Input B, an FP8 E3M4 number
    output logic [7:0] result,      // Product, result of the operation
    output logic [4:0] flags        // Flags indicating exceptions according to IEEE754
);

    // Internal signals
    logic        Sa;                // A's sign
    logic        Sb;                // B's sign
    logic        Sp;                // Product sign
    logic [2:0]  Ea, Eb;            // Effective exponents (zero/denormal use 1)
    logic [4:0]  Ma, Mb;            // Significands {hidden bit, mantissa}
    logic [4:0]  InputExc;          // Exceptions in inputs
    logic [3:0]  Ep;                // Product exponent
    logic [9:0]  Mp;                // Product significand
    logic [3:0]  NormM;             // Normalized mantissa
    logic [3:0]  NormE;             // Normalized exponent (0 for denormal results)
    logic        ZeroProd;          // Product is exactly zero
    logic        Tiny;              // Nonzero result below the smallest normal number
    logic        G, R, S;           // Guard (half ulp), round and sticky bits
    logic [7:0]  Z;                 // Rounded result before exception handling
    logic        EOF;               // Exponent overflow

    // Take the inputs apart and check them for exceptions
    FP8_Mult_PrepModule PrepModule (.*);

    // Perform (unsigned) significand multiplication, sign and exponent calculation
    FP8_Mult_ExecuteModule ExecuteModule (.*);

    // Normalize the product and compute the bits used in rounding
    FP8_Mult_NormalizeModule NormalizeModule (.*);

    // Round result and put it together
    FP8_Mult_RoundModule RoundModule (.*);

    // Handle special values and set the exception flags
    FP8_Mult_ExceptionModule ExceptionModule (.*, .P(result), .Flags(flags));

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Preparation: take the inputs apart and check them for exceptions
//////////////////////////////////////////////////////////////////////////////////
module FP8_Mult_PrepModule (
    input  logic [7:0] a,           // Input A, an FP8 E3M4 number
    input  logic [7:0] b,           // Input B, an FP8 E3M4 number
    output logic       Sa,          // A's sign
    output logic       Sb,          // B's sign
    output logic [2:0] Ea,          // A's effective exponent
    output logic [2:0] Eb,          // B's effective exponent
    output logic [4:0] Ma,          // A's significand {hidden bit, mantissa}
    output logic [4:0] Mb,          // B's significand {hidden bit, mantissa}
    output logic [4:0] InputExc     // Input numbers are exceptions
);

    // Internal signals              // If signal is high...
    logic ANaN;                      // A is a NaN
    logic BNaN;                      // B is a NaN
    logic AInf;                      // A is infinity
    logic BInf;                      // B is infinity

    assign ANaN = &a[6:4] &  |a[3:0];   // All one exponent and not all zero mantissa - NaN
    assign BNaN = &b[6:4] &  |b[3:0];   // All one exponent and not all zero mantissa - NaN
    assign AInf = &a[6:4] & ~|a[3:0];   // All one exponent and all zero mantissa - Infinity
    assign BInf = &b[6:4] & ~|b[3:0];   // All one exponent and all zero mantissa - Infinity

    // Check for any exceptions and put all flags into exception vector
    assign InputExc = {(ANaN | BNaN | AInf | BInf), ANaN, BNaN, AInf, BInf};

    // Take input numbers apart
    assign Sa = a[7];
    assign Sb = b[7];

    // Zero and denormals (exponent 000) have no hidden bit and the same scale as exponent 001
    assign Ea = (a[6:4] == 3'b000) ? 3'b001 : a[6:4];
    assign Eb = (b[6:4] == 3'b000) ? 3'b001 : b[6:4];
    assign Ma = {|a[6:4], a[3:0]};
    assign Mb = {|b[6:4], b[3:0]};

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Execution: significand multiplication, sign and exponent
//////////////////////////////////////////////////////////////////////////////////
module FP8_Mult_ExecuteModule (
    input  logic [4:0] Ma,          // A's significand
    input  logic [4:0] Mb,          // B's significand
    input  logic [2:0] Ea,          // A's effective exponent
    input  logic [2:0] Eb,          // B's effective exponent
    input  logic       Sa,          // A's sign
    input  logic       Sb,          // B's sign
    output logic       Sp,          // Product sign
    output logic [3:0] Ep,          // Product exponent, for a hidden bit one place above Mp[9]
    output logic [9:0] Mp           // Product significand (exact, 5 x 5 bits)
);

    assign Sp = Sa ^ Sb;            // Equal signs give a positive product

    assign Mp = Ma * Mb;

    // Mp is a 2.8 fixed-point number, so A x B = Mp/2^8 x 2^(Ea+Eb-6).
    // Read as 1.10 with the hidden bit one place above Mp[9], the biased
    // exponent is Ea + Eb - 1 (adjusting for double bias).
    assign Ep = {1'b0, Ea} + {1'b0, Eb} - 4'd1;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Normalization: shift the product so its leading one becomes the hidden bit,
// and compute the bits used in rounding
//////////////////////////////////////////////////////////////////////////////////
module FP8_Mult_NormalizeModule (
    input  logic [9:0] Mp,          // Product significand
    input  logic [3:0] Ep,          // Product exponent
    output logic [3:0] NormM,       // Normalized mantissa
    output logic [3:0] NormE,       // Normalized exponent
    output logic       ZeroProd,    // Zero flag
    output logic       Tiny,        // Nonzero result below the smallest normal number
    output logic       G,           // Guard bit (half an ulp)
    output logic       R,           // Round bit
    output logic       S            // Sticky bit
);

    logic [10:0] P;                 // Product with the hidden-bit position at P[10]
    logic [10:0] PS;                // P after normalization shift
    logic [3:0]  LZ;                // Leading zeros in P
    logic [3:0]  Shift;             // Number of steps to shift P left

    // The spare bit on top means the product only ever needs a left shift: for the
    // smallest exponents (Ea = Eb = 1, Ep = 1) it is already at the denormal scale
    assign P = {1'b0, Mp};

    always_comb begin
        LZ = 4'd11;
        for (int i = 0; i <= 10; i++)
            if (P[i]) LZ = 4'(10 - i);
    end

    // Move the leading one up to P[10], but stop once the exponent reaches 1:
    // if the leading one does not reach P[10], the result is denormal
    assign Shift = (LZ > Ep - 4'd1) ? Ep - 4'd1 : LZ;
    assign PS    = P << Shift;

    assign ZeroProd = ~|Mp;
    assign Tiny     = ~PS[10] & ~ZeroProd;

    assign NormE = PS[10] ? (Ep - Shift) : 4'd0;
    assign NormM = PS[9:6];

    assign G = PS[5];
    assign R = PS[4];
    assign S = |PS[3:0];

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Rounding: round to nearest, tie to even, and put the result together
//////////////////////////////////////////////////////////////////////////////////
module FP8_Mult_RoundModule (
    input  logic [3:0] NormM,       // Normalized mantissa
    input  logic [3:0] NormE,       // Normalized exponent
    input  logic       Sp,          // Product sign
    input  logic       G,           // Guard bit
    input  logic       R,           // Round bit
    input  logic       S,           // Sticky bit
    output logic [7:0] Z,           // Final product
    output logic       EOF          // Exponent overflow
);

    logic       RoundUp;            // Flag indicating that the product should be rounded up
    logic [7:0] RoundEM;            // {exponent, mantissa} after rounding

    // Round up if above half an ulp, or exactly half an ulp and the mantissa is odd
    assign RoundUp = G & (R | S | NormM[0]);

    // Adding one to {exponent, mantissa} carries a mantissa overflow into the exponent
    // (post-rounding normalization). This also turns a denormal 0.1111 that rounds up
    // into the smallest normal number.
    assign RoundEM = {NormE, NormM} + 8'(RoundUp);

    // An exponent of 111 or more does not fit in a finite FP8 number
    assign EOF = (RoundEM[7:4] >= 4'd7);

    assign Z = {Sp, RoundEM[6:0]};  // Putting the pieces together

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Exceptions: handle special values and set the exception flags
//////////////////////////////////////////////////////////////////////////////////
module FP8_Mult_ExceptionModule (
    input  logic [7:0] Z,           // Rounded product
    input  logic       Sp,          // Product sign
    input  logic       ZeroProd,    // Product significand is zero (an input is zero)
    input  logic       Tiny,        // Nonzero result below the smallest normal number
    input  logic       G,           // Guard bit
    input  logic       R,           // Round bit
    input  logic       S,           // Sticky bit
    input  logic [4:0] InputExc,    // Exceptions in inputs A and B: {any, ANaN, BNaN, AInf, BInf}
    input  logic       EOF,         // Exponent overflow
    output logic [7:0] P,           // The product
    output logic [4:0] Flags        // Exception flags
);

    localparam logic [7:0] QNAN = 8'h7F;  // NaN produced by this module
    localparam logic [6:0] INF  = 7'h70;  // Infinity without sign

    // Internal signals
    logic Overflow;                 // Overflow flag
    logic Underflow;                // Underflow flag
    logic DivideByZero;             // Divide-by-Zero flag (always 0 in Mult)
    logic Invalid;                  // Invalid operation
    logic Inexact;                  // Result is inexact because of rounding
    logic Finite;                   // Both inputs are finite
    logic NaNOut;                   // Result is NaN
    logic InfOut;                   // Result is infinity because an input is infinity

    assign Finite = ~InputExc[4];

    // Zero times infinity is invalid (the significand of infinity is nonzero,
    // so a zero product significand means the other input is zero)
    assign Invalid = (InputExc[1] | InputExc[0]) & ZeroProd;

    assign NaNOut = InputExc[3] | InputExc[2] | Invalid;
    assign InfOut = ~NaNOut & (InputExc[1] | InputExc[0]);

    // Result is too big to be represented
    assign Overflow = Finite & EOF;

    // Result is too small to be represented exactly
    assign Underflow = Finite & Tiny & (G | R | S);

    assign DivideByZero = 1'b0;

    // Inexact answer due to rounding or overflow
    assign Inexact = Finite & (G | R | S | EOF);

    // Put pieces together to form final result
    always_comb begin
        if (NaNOut)                 P = QNAN;
        else if (InfOut | Overflow) P = {Sp, INF};
        else                        P = Z;
    end

    // Collect exception flags
    assign Flags = {Overflow, Underflow, DivideByZero, Invalid, Inexact};

endmodule
