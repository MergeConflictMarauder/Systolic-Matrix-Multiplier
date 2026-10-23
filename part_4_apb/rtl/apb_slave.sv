`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// APB slave with the control/status registers (CSRs) of the 8x8 FP8 matmul.
// Completes the provided apb_slave.sv skeleton (part 4). A CPU on the APB bus
// writes the addresses and strides, writes START, polls DONE and reads FLAGS.
//
// Register map. Every register is 16 bits wide and PADDR is the register index.
//   PADDR  Name       Bits    Access  Description
//   1      START      [0]     R/W1S   Write 1 to start an operation. Stays 1 while the
//                                     matmul runs (it drives start_mat_mul) and is
//                                     cleared by hardware when the operation is done.
//                                     Writing 0, or writing 1 while busy, has no effect.
//   2      DONE       [15]    R       Set when an operation finishes. Cleared when the
//                                     next operation is started.
//   3      FLAGS      [4:0]   R       Exception flags of the current or last operation:
//                                     {Overflow, Underflow, DivideByZero, Invalid, Inexact}
//   4      ADDR_A     [9:0]   R/W     RAM address of the first column of A
//   5      ADDR_B     [9:0]   R/W     RAM address of the first row of B
//   6      ADDR_C     [9:0]   R/W     RAM address of the first column of C
//   7      STRIDE_A   [7:0]   R/W     Address step between columns of A (reset value 1)
//   8      STRIDE_B   [7:0]   R/W     Address step between rows of B    (reset value 1)
//   9      STRIDE_C   [7:0]   R/W     Address step between columns of C (reset value 1)
// Unused bits and unmapped indices read as 0, and writes to them are ignored.
//
// Bus timing. PREADY is always 1, so every transfer is one setup cycle
// (PSEL=1, PENABLE=0) followed by one access cycle (PSEL=1, PENABLE=1).
//   Write: the register is updated at the end of the access cycle.
//   Read:  PRDATA is registered at the end of the setup cycle, so it is valid
//          during the whole access cycle and is held until the next read.
//////////////////////////////////////////////////////////////////////////

`define REG_ADDRWIDTH 10
`define REG_DATAWIDTH 16
`define REG_STRT_ADDR 1
`define REG_DONE_ADDR 2
`define REG_FLAG_ADDR 3
`define REG_MATA_ADDR 4
`define REG_MATB_ADDR 5
`define REG_MATC_ADDR 6
`define REG_STRA_ADDR 7
`define REG_STRB_ADDR 8
`define REG_STRC_ADDR 9

module apb_slave
    import matmul_pkg::*;
(
    input  logic                         PCLK,
    input  logic                         PRESETn,
    input  logic [`REG_ADDRWIDTH-1:0]    PADDR,
    input  logic                         PWRITE,
    input  logic                         PSEL,
    input  logic                         PENABLE,
    input  logic [`REG_DATAWIDTH-1:0]    PWDATA,
    output logic [`REG_DATAWIDTH-1:0]    PRDATA,
    output logic                         PREADY,
    // Control signals to the matmul (CPU writes these)
    output logic                         start,
    output logic [AWIDTH-1:0]            address_mat_a, address_mat_b, address_mat_c,
    output logic [ADDR_STRIDE_WIDTH-1:0] address_stride_a, address_stride_b, address_stride_c,
    // Status signals from the matmul (CPU reads these)
    input  logic                         done,      // One-cycle pulse after the last C write
    input  logic [4:0]                   flags      // Held after the operation, cleared at the next start
);

    // The slave never inserts wait states
    assign PREADY = 1'b1;

    // DONE register: holds the one-cycle done pulse until the next start
    logic done_reg;

    //////////////////////////////////////////////////////////////////////
    // Read data multiplexer, indexed by PADDR
    //////////////////////////////////////////////////////////////////////
    logic [`REG_DATAWIDTH-1:0] read_data;

    always_comb begin
        read_data = '0;
        case (PADDR)
            `REG_STRT_ADDR: read_data[0]                     = start;
            `REG_DONE_ADDR: read_data[15]                    = done_reg;
            `REG_FLAG_ADDR: read_data[4:0]                   = flags;
            `REG_MATA_ADDR: read_data[AWIDTH-1:0]            = address_mat_a;
            `REG_MATB_ADDR: read_data[AWIDTH-1:0]            = address_mat_b;
            `REG_MATC_ADDR: read_data[AWIDTH-1:0]            = address_mat_c;
            `REG_STRA_ADDR: read_data[ADDR_STRIDE_WIDTH-1:0] = address_stride_a;
            `REG_STRB_ADDR: read_data[ADDR_STRIDE_WIDTH-1:0] = address_stride_b;
            `REG_STRC_ADDR: read_data[ADDR_STRIDE_WIDTH-1:0] = address_stride_c;
            default:        read_data = '0;
        endcase
    end

    //////////////////////////////////////////////////////////////////////
    // APB state machine and registers
    //   IDLE:         no transfer. A setup cycle (PSEL=1, PENABLE=0) moves to
    //                 WRITE_ACCESS or READ_ACCESS; for a read, PRDATA is loaded here.
    //   WRITE_ACCESS: access cycle of a write. The addressed register is written.
    //   READ_ACCESS:  access cycle of a read. PRDATA already holds the data.
    // Both access states return to IDLE after one cycle because PREADY is 1.
    //////////////////////////////////////////////////////////////////////
    typedef enum logic [1:0] {IDLE, READ_ACCESS, WRITE_ACCESS} state_t;
    state_t State;

    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            State            <= IDLE;
            PRDATA           <= '0;
            start            <= 1'b0;
            done_reg         <= 1'b0;
            address_mat_a    <= '0;
            address_mat_b    <= '0;
            address_mat_c    <= '0;
            address_stride_a <= 'd1;
            address_stride_b <= 'd1;
            address_stride_c <= 'd1;
        end else begin
            // The operation finished: release start_mat_mul and remember it in DONE
            if (done) begin
                start    <= 1'b0;
                done_reg <= 1'b1;
            end

            case (State)
                IDLE: begin
                    if (PSEL && !PENABLE) begin
                        if (PWRITE) begin
                            State <= WRITE_ACCESS;
                        end else begin
                            State  <= READ_ACCESS;
                            PRDATA <= read_data;
                        end
                    end
                end

                WRITE_ACCESS: begin
                    if (PSEL && PWRITE && PENABLE) begin
                        case (PADDR)
                            // Start only from idle, so the matmul sees a new rising edge
                            `REG_STRT_ADDR: if (PWDATA[0] && !start) begin
                                start    <= 1'b1;
                                done_reg <= 1'b0;
                            end
                            `REG_MATA_ADDR: address_mat_a    <= PWDATA[AWIDTH-1:0];
                            `REG_MATB_ADDR: address_mat_b    <= PWDATA[AWIDTH-1:0];
                            `REG_MATC_ADDR: address_mat_c    <= PWDATA[AWIDTH-1:0];
                            `REG_STRA_ADDR: address_stride_a <= PWDATA[ADDR_STRIDE_WIDTH-1:0];
                            `REG_STRB_ADDR: address_stride_b <= PWDATA[ADDR_STRIDE_WIDTH-1:0];
                            `REG_STRC_ADDR: address_stride_c <= PWDATA[ADDR_STRIDE_WIDTH-1:0];
                            default: ;  // DONE, FLAGS and unmapped indices are read-only
                        endcase
                    end
                    State <= IDLE;
                end

                READ_ACCESS: State <= IDLE;

                default: State <= IDLE;
            endcase
        end
    end

endmodule
