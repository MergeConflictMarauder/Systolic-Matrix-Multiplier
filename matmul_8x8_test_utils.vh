//////////////////////////////////////////////////////////////////////////
// Testbench code shared by the 8x8 matrix multiplier testbenches
// (part_3/matmul_with_ram_tb.v and part_4/matmul_apb_tb.v).
//
// Include this file inside a testbench module (plain Verilog-2001), before
// the DUT instance, and compile with +incdir+.. from the part_N folder:
//     `include "matmul_8x8_test_utils.vh"
// The DUT instance must be named u_matmul and contain the six RAMs
// matrix_A0/A1, matrix_B0/B1 and matrix_C0/C1, as both 8x8 top levels do.
//
// RAM layout (each word holds four FP8 lanes, lane 0 in the low byte):
//   A0 / A1: rows 0-3 / 4-7 of A.     Address addr_a + k*stride_a holds column k.
//   B0 / B1: columns 0-3 / 4-7 of B.  Address addr_b + k*stride_b holds row k.
//   C0 / C1: rows 0-3 / 4-7 of C.     Address addr_c + j*stride_c holds column j.
//
//   load_rams           Write mat_a and mat_b into the RAMs, and a DEADBEEF
//                       sentinel into C so a missing write is detected
//   check_c(show_c)     Compare all 64 elements of C with exp_c
//   check_flags(flags)  Compare observed exception flags with exp_flags
// Every mismatch increments errors; the first 10 are printed.
//////////////////////////////////////////////////////////////////////////

reg  [7:0] mat_a [0:7][0:7];                // A[row][k]
reg  [7:0] mat_b [0:7][0:7];                // B[k][col]
reg  [7:0] exp_c [0:7][0:7];                // Expected C[row][col]
reg  [4:0] exp_flags;                       // Expected exception flags

reg  [9:0] addr_a, addr_b, addr_c;          // Base addresses of A, B and C
reg  [7:0] stride_a, stride_b, stride_c;    // Address steps of A, B and C

integer runs;                               // Multiplications completed so far
integer errors;                             // Mismatches found so far

task load_rams;
    integer    k, lane;
    reg [9:0]  wa, wb, wc;
    reg [31:0] word_a0, word_a1, word_b0, word_b1;
    begin
        for (k = 0; k < 8; k = k + 1) begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                word_a0[8*lane +: 8] = mat_a[lane][k];
                word_a1[8*lane +: 8] = mat_a[lane + 4][k];
                word_b0[8*lane +: 8] = mat_b[k][lane];
                word_b1[8*lane +: 8] = mat_b[k][lane + 4];
            end
            wa = addr_a + k * stride_a;
            wb = addr_b + k * stride_b;
            wc = addr_c + k * stride_c;
            u_matmul.matrix_A0.ram[wa] = word_a0;
            u_matmul.matrix_A1.ram[wa] = word_a1;
            u_matmul.matrix_B0.ram[wb] = word_b0;
            u_matmul.matrix_B1.ram[wb] = word_b1;
            u_matmul.matrix_C0.ram[wc] = 32'hDEADBEEF;
            u_matmul.matrix_C1.ram[wc] = 32'hDEADBEEF;
        end
    end
endtask

task check_c;
    input      show_c;                      // Print every column of C
    integer    i, j;
    reg [9:0]  wc;
    reg [31:0] word_c0, word_c1;
    reg [7:0]  observed;
    begin
        for (j = 0; j < 8; j = j + 1) begin
            wc      = addr_c + j * stride_c;
            word_c0 = u_matmul.matrix_C0.ram[wc];
            word_c1 = u_matmul.matrix_C1.ram[wc];
            if (show_c)
                $display("C col %0d (address %0d): C0 = %h  C1 = %h", j, wc, word_c0, word_c1);
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
    end
endtask

task check_flags;
    input [4:0] flags;
    begin
        if (flags !== exp_flags) begin
            if (errors < 10)
                $display("  MISMATCH (run %0d): exception flags = %b, expected %b",
                         runs, flags, exp_flags);
            errors = errors + 1;
        end
    end
endtask
