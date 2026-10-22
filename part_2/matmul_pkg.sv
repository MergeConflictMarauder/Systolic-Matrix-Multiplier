//////////////////////////////////////////////////////////////////////////
// Shared parameters and types for the systolic matrix multiplier.
// Compile this package before matmul.sv and matmul_with_ram.sv.
//////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

package matmul_pkg;
    localparam int DWIDTH             = 8;
    localparam int AWIDTH             = 10;
    localparam int MEM_SIZE           = 1024;

    localparam int MAT_MUL_SIZE       = 4;
    localparam int MASK_WIDTH         = 4;
    localparam int LOG2_MAT_MUL_SIZE  = 2;

    localparam int BB_MAT_MUL_SIZE    = MAT_MUL_SIZE;
    localparam int NUM_CYCLES_IN_MAC  = 3;
    localparam int MEM_ACCESS_LATENCY = 1;
    localparam int ADDR_STRIDE_WIDTH  = 8;
    localparam int MAX_BITS_POOL      = 3;

    typedef logic [DWIDTH-1:0]                   data_t;  // one matrix element
    typedef logic [MAT_MUL_SIZE-1:0][DWIDTH-1:0] vec_t;   // one row/column of elements, element 0 in the LSBs
    typedef vec_t [MAT_MUL_SIZE-1:0]             mat_t;   // MAT_MUL_SIZE vectors
endpackage
