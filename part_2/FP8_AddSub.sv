`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
//
// Description:    Combinational adder/subtractor for FP8 E3M4 numbers.
//                 The split shift stages (AlignShift1/2, NormalizeShift1/2) 
//                 are merged since an 8-bit shift is one level.
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
//                 operation (1 bit)   : Single control bit. 0/Addition, 1/Subtraction
//
// Outputs:
//                 result (8 bits)     : Result of the operation, FP8 E3M4 number
//                 flags (5 bits)      : Flags indicating exceptions:
//                                          Bit 4: Overflow
//                                          Bit 3: Underflow (tiny and inexact)
//                                          Bit 2: Divide by Zero (always 0)
//                                          Bit 1: Invalid (infinity - infinity)
//                                          Bit 0: Inexact
//
//////////////////////////////////////////////////////////////////////////////////

module FP8_AddSub (
    input  logic [7:0] a,           // Input A, an FP8 E3M4 number
    input  logic [7:0] b,           // Input B, an FP8 E3M4 number
    input  logic       operation,   // Operation select signal: 0/Addition, 1/Subtraction
    output logic [7:0] result,      // Result of the operation
    output logic [4:0] flags        // Flags indicating exceptions according to IEEE754
);

    // Internal wires between modules
    logic        Sa;                // A's sign
    logic        Sb;                // B's effective sign (B's sign flipped for subtraction)
    logic [2:0]  Ea, Eb;            // Effective exponents (zero/denormal use 1)
    logic [4:0]  Ma, Mb;            // Significands {hidden bit, mantissa}
    logic [4:0]  InputExc;          // Input numbers are exceptions
    logic        MaxAB;             // Indicates the larger of A and B (0/A, 1/B)
    logic [2:0]  CExp;              // Common exponent
    logic [2:0]  Shift;             // Number of steps to shift smaller significand right (align)
    logic [4:0]  Mmax;              // Larger significand
    logic [4:0]  MminP;             // Smaller significand before alignment
    logic [9:0]  Mmin;              // Smaller significand after alignment
    logic [10:0] Sum;               // [10] carry, [9] hidden bit, [8:5] mantissa, [4:0] bits below
    logic        PSgn;              // Sign of the larger operand
    logic        Opr;               // Effective (performed) operation: 0/Add, 1/Sub
    logic [3:0]  NormShift;         // Number of steps to shift sum left (normalize)
    logic [3:0]  NormM;             // Normalized mantissa
    logic [3:0]  NormE;             // Normalized exponent (0 for denormal results)
    logic        ZeroSum;           // Sum is exactly zero
    logic        Tiny;              // Nonzero result below the smallest normal number
    logic        G, R, S;           // Guard (half ulp), round and sticky bits
    logic [7:0]  Z;                 // Rounded result before exception handling
    logic        EOF;               // Exponent overflow

    // Take the inputs apart and check them for exceptions
    FP8_AddSub_PrealignModule PrealignModule (.*, .A(a), .B(b));

    // Determine the larger operand, the common exponent and the alignment shift
    FP8_AddSub_AlignModule AlignModule (.*, .A(a[6:0]), .B(b[6:0]), .Mmin(MminP));

    // Alignment shift of the smaller significand
    FP8_AddSub_AlignShift AlignShift (.*);

    // Perform significand addition
    FP8_AddSub_ExecutionModule ExecutionModule (.*);

    // Determine the normalization shift amount
    FP8_AddSub_NormalizeModule NormalizeModule (.*, .Shift(NormShift));

    // Normalization shift, normalized exponent and the bits used in rounding
    FP8_AddSub_NormalizeShift NormalizeShift (.*, .Shift(NormShift));

    // Round and put result together
    FP8_AddSub_RoundModule RoundModule (.*);

    // Handle special values and set the exception flags
    FP8_AddSub_ExceptionModule ExceptionModule (.*, .P(result), .Flags(flags));

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Pre-alignment: take the inputs apart and check them for exceptions
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_PrealignModule (
    input  logic [7:0] A,           // Input A, an FP8 E3M4 number
    input  logic [7:0] B,           // Input B, an FP8 E3M4 number
    input  logic       operation,   // 0/Addition, 1/Subtraction
    output logic       Sa,          // A's sign bit
    output logic       Sb,          // B's effective sign bit
    output logic [2:0] Ea,          // A's effective exponent
    output logic [2:0] Eb,          // B's effective exponent
    output logic [4:0] Ma,          // A's significand {hidden bit, mantissa}
    output logic [4:0] Mb,          // B's significand {hidden bit, mantissa}
    output logic [4:0] InputExc     // Input numbers are exceptions
);

    // Internal signals              // If signal is high...
    logic ANaN;                      // A is a NaN (Not-a-Number)
    logic BNaN;                      // B is a NaN
    logic AInf;                      // A is infinity
    logic BInf;                      // B is infinity

    assign ANaN = &A[6:4] &  |A[3:0];   // All one exponent and not all zero mantissa - NaN
    assign BNaN = &B[6:4] &  |B[3:0];   // All one exponent and not all zero mantissa - NaN
    assign AInf = &A[6:4] & ~|A[3:0];   // All one exponent and all zero mantissa - Infinity
    assign BInf = &B[6:4] & ~|B[3:0];   // All one exponent and all zero mantissa - Infinity

    // Put all flags into exception vector
    assign InputExc = {(ANaN | BNaN | AInf | BInf), ANaN, BNaN, AInf, BInf};

    assign Sa = A[7];
    assign Sb = B[7] ^ operation;       // Subtraction is addition of -B

    // Zero and denormals (exponent 000) have no hidden bit and the same scale as exponent 001
    assign Ea = (A[6:4] == 3'b000) ? 3'b001 : A[6:4];
    assign Eb = (B[6:4] == 3'b000) ? 3'b001 : B[6:4];
    assign Ma = {|A[6:4], A[3:0]};
    assign Mb = {|B[6:4], B[3:0]};

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Alignment: determine the larger operand and set the significands, shift and
// common exponent accordingly
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_AlignModule (
    input  logic [6:0] A,           // A without sign
    input  logic [6:0] B,           // B without sign
    input  logic [2:0] Ea,          // A's effective exponent
    input  logic [2:0] Eb,          // B's effective exponent
    input  logic [4:0] Ma,          // A's significand
    input  logic [4:0] Mb,          // B's significand
    output logic [2:0] CExp,        // Common exponent
    output logic       MaxAB,       // Indicates larger of A and B (0/A, 1/B)
    output logic [2:0] Shift,       // Number of steps to shift smaller significand right
    output logic [4:0] Mmin,        // Smaller significand
    output logic [4:0] Mmax         // Larger significand
);

    // The magnitude order of FP8 numbers (denormals included) is the integer order of their lower 7 bits
    assign MaxAB = (A < B);

    assign Shift = MaxAB ? (Eb - Ea) : (Ea - Eb);
    assign Mmin  = MaxAB ? Ma : Mb;
    assign Mmax  = MaxAB ? Mb : Ma;
    assign CExp  = MaxAB ? Eb : Ea;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Alignment shift of the smaller significand
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_AlignShift (
    input  logic [4:0] MminP,       // Smaller significand
    input  logic [2:0] Shift,       // Shift amount
    output logic [9:0] Mmin         // [9:5] aligned significand, [4:0] bits shifted out
);

    // Finite exponents are 1..6, so the shift is at most 5 and no bits are lost:
    // the shifted-out bits are kept so that rounding is exact
    assign Mmin = {MminP, 5'b00000} >> Shift;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Execution: add or subtract the significands
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_ExecutionModule (
    input  logic [4:0]  Mmax,       // The larger significand
    input  logic [9:0]  Mmin,       // The smaller significand, aligned
    input  logic        Sa,         // A's sign bit
    input  logic        Sb,         // B's effective sign bit
    input  logic        MaxAB,      // Indicates the larger number (0/A, 1/B)
    output logic [10:0] Sum,        // The result of the operation
    output logic        PSgn,       // The sign for the result
    output logic        Opr         // The effective (performed) operation
);

    assign Opr = Sa ^ Sb;           // Resolve signs to determine operation

    // Perform effective operation (Mmax >= Mmin, so the difference is never negative)
    assign Sum = Opr ? ({1'b0, Mmax, 5'b00000} - {1'b0, Mmin})
                     : ({1'b0, Mmax, 5'b00000} + {1'b0, Mmin});

    // The result takes the sign of the larger operand
    assign PSgn = MaxAB ? Sb : Sa;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Normalization: determine the normalization shift amount
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_NormalizeModule (
    input  logic [10:0] Sum,        // Significand sum
    input  logic [2:0]  CExp,       // Common exponent
    output logic [3:0]  Shift       // Number of steps to shift the sum left
);

    logic [3:0] LZ;                 // Leading zeros in the sum

    always_comb begin
        LZ = 4'd11;
        for (int i = 0; i <= 10; i++)
            if (Sum[i]) LZ = 4'(10 - i);
    end

    // Move the leading one up to Sum[10], but stop once the exponent reaches 1:
    // if the leading one does not reach Sum[10], the result is denormal
    assign Shift = (LZ > {1'b0, CExp}) ? {1'b0, CExp} : LZ;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Normalization shift: calculate post-normalization mantissa and exponent, as
// well as the bits used in rounding
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_NormalizeShift (
    input  logic [10:0] Sum,        // The pre-shift sum
    input  logic [2:0]  CExp,       // Common exponent
    input  logic [3:0]  Shift,      // Amount to be shifted
    output logic [3:0]  NormM,      // Normalized mantissa
    output logic [3:0]  NormE,      // Adjusted exponent
    output logic        ZeroSum,    // Zero flag
    output logic        Tiny,       // Nonzero result below the smallest normal number
    output logic        G,          // Guard bit (half an ulp)
    output logic        R,          // Round bit
    output logic        S           // Sticky bit
);

    logic [10:0] PSSum;             // [10] hidden bit, [9:6] mantissa, [5:0] bits below the mantissa

    assign PSSum   = Sum << Shift;
    assign ZeroSum = ~|Sum;
    assign Tiny    = ~PSSum[10] & ~ZeroSum;

    // A leading one at PSSum[10] gives exponent CExp - Shift + 1, otherwise the result is denormal (exponent 000)
    assign NormE = PSSum[10] ? ({1'b0, CExp} - Shift + 4'd1) : 4'd0;
    assign NormM = PSSum[9:6];

    assign G = PSSum[5];
    assign R = PSSum[4];
    assign S = |PSSum[3:0];

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Rounding: round to nearest, tie to even, and put the result together
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_RoundModule (
    input  logic       ZeroSum,     // Sum is zero
    input  logic [3:0] NormE,       // Normalized exponent
    input  logic [3:0] NormM,       // Normalized mantissa
    input  logic       G,           // Guard bit
    input  logic       R,           // Round bit
    input  logic       S,           // Sticky bit
    input  logic       Sa,          // A's sign bit
    input  logic       Sb,          // B's effective sign bit
    input  logic       PSgn,        // Sign of the larger operand
    output logic [7:0] Z,           // Final result
    output logic       EOF          // Exponent overflow
);

    logic       RoundUp;            // Flag indicating that the sum should be rounded up
    logic [7:0] RoundEM;            // {exponent, mantissa} after rounding
    logic       FSgn;               // Final sign

    // The cases where we need to round upwards (= adding one) in Round to nearest, tie to even
    assign RoundUp = G & (R | S | NormM[0]);

    // Adding one to {exponent, mantissa} carries a mantissa overflow into the exponent.
    // This also turns a denormal 0.1111 that rounds up into the smallest normal number.
    assign RoundEM = {NormE, NormM} + 8'(RoundUp);

    // An exponent of 111 or more does not fit in a finite FP8 number
    assign EOF = (RoundEM[7:4] >= 4'd7);

    // An exact zero sum is +0, except (-0) + (-0) = -0
    assign FSgn = ZeroSum ? (Sa & Sb) : PSgn;

    assign Z = {FSgn, RoundEM[6:0]};

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Exceptions: handle special values and set the exception flags
//////////////////////////////////////////////////////////////////////////////////
module FP8_AddSub_ExceptionModule (
    input  logic [7:0] Z,           // Rounded result
    input  logic       Sa,          // A's sign bit
    input  logic       Sb,          // B's effective sign bit
    input  logic       Opr,         // Effective operation (0/Add, 1/Sub)
    input  logic       Tiny,        // Nonzero result below the smallest normal number
    input  logic       G,           // Guard bit
    input  logic       R,           // Round bit
    input  logic       S,           // Sticky bit
    input  logic [4:0] InputExc,    // Exceptions in inputs A and B: {any, ANaN, BNaN, AInf, BInf}
    input  logic       EOF,         // Exponent overflow
    output logic [7:0] P,           // Final result
    output logic [4:0] Flags        // Exception flags
);

    localparam logic [7:0] QNAN = 8'h7F;  // NaN produced by this module
    localparam logic [6:0] INF  = 7'h70;  // Infinity without sign

    // Internal signals
    logic Overflow;                 // Overflow flag
    logic Underflow;                // Underflow flag
    logic DivideByZero;             // Divide-by-Zero flag (always 0 in Add/Sub)
    logic Invalid;                  // Invalid operation
    logic Inexact;                  // Result is inexact because of rounding
    logic Finite;                   // Both inputs are finite
    logic NaNOut;                   // Result is NaN
    logic InfOut;                   // Result is infinity because an input is infinity

    assign Finite = ~InputExc[4];

    // Infinity minus infinity is invalid
    assign Invalid = InputExc[1] & InputExc[0] & Opr;

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
        if (NaNOut)        P = QNAN;
        else if (InfOut)   P = {InputExc[1] ? Sa : Sb, INF};
        else if (Overflow) P = {Z[7], INF};
        else               P = Z;
    end

    // Collect exception flags
    assign Flags = {Overflow, Underflow, DivideByZero, Invalid, Inexact};

endmodule
