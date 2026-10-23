`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////
// Demo testbench: one short simulation that walks through all four parts.
//
//   Phase 1  Part 1      FP8 adder/subtractor and multiplier: 5 input pairs
//                        covering normal results, subtraction, rounding,
//                        overflow, denormals/underflow and infinity/NaN.
//   Phase 2  Parts 2-4   8x8 matmul (four 4x4 tiles) controlled by a CPU over
//                        APB: write addresses/strides, write START, poll DONE,
//                        read FLAGS. The data includes 8.0 x 8.0, which
//                        overflows inside a PE, so the exception flags reach
//                        the top level (part 2) and FLAGS reports them over
//                        APB (part 4).
//
// demo_phase holds the name of the current phase (show it in ASCII radix).
// Every result is checked against values worked out by hand, and at the end
// the testbench prints a timeline of when each step happened, to place
// waveform cursors. Define FSDB_DUMP to write demo.fsdb for Verdi.
//////////////////////////////////////////////////////////////////////////
module demo_tb;

    reg            clk;
    reg            reset;                       // Active high
    reg [8*24-1:0] demo_phase;                  // Name of the current phase

    //////////////////////////////////////////////////////////////////////
    // Part 1: FP8 adder/subtractor and multiplier
    //////////////////////////////////////////////////////////////////////
    reg  [7:0] fp_a, fp_b;
    reg        fp_op;                           // 0: a + b, 1: a - b
    wire [7:0] add_result, mult_result;
    wire [4:0] add_flags, mult_flags;           // {Overflow, Underflow, DivByZero, Invalid, Inexact}

    FP8_AddSub u_fp8_add  (.a(fp_a), .b(fp_b), .operation(fp_op), .result(add_result), .flags(add_flags));
    FP8_Mult   u_fp8_mult (.a(fp_a), .b(fp_b), .result(mult_result), .flags(mult_flags));

    //////////////////////////////////////////////////////////////////////
    // Parts 2-4: 8x8 matmul controlled over APB
    //////////////////////////////////////////////////////////////////////
    reg  [`REG_ADDRWIDTH-1:0] PADDR;
    reg                       PWRITE;
    reg                       PSEL;
    reg                       PENABLE;
    reg  [`REG_DATAWIDTH-1:0] PWDATA;
    wire [`REG_DATAWIDTH-1:0] PRDATA;
    wire                      PREADY;

    reg  [`REG_DATAWIDTH-1:0] rdata;            // Last value read over APB
    reg  [4:0]                flags_read;       // FLAGS register read after DONE
    reg                       done;
    integer                   polls;

    // 8x8 matrices, expected results, RAM addresses/strides and the shared
    // load/check tasks (see header_tb/matmul_8x8_test_utils.vh)
`include "matmul_8x8_test_utils.vh"

    matrix_multiplication_8x8_apb u_matmul (
        .PCLK    (clk),
        .PRESETn (~reset),
        .PADDR   (PADDR),
        .PWRITE  (PWRITE),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
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
    // Phase 1: apply one input pair to both FP8 units and check both
    // results one clock later (each pair is held for two clocks, 40 ns)
    //////////////////////////////////////////////////////////////////////
    task fp8_check;
        input [7:0] a, b;
        input       op;
        input [7:0] exp_add;
        input [4:0] exp_add_flags;
        input [7:0] exp_mult;
        input [4:0] exp_mult_flags;
        begin
            @(negedge clk);
            fp_a  = a;
            fp_b  = b;
            fp_op = op;
            @(negedge clk);
            $display("  %h %s %h = %h (flags %b)    %h x %h = %h (flags %b)",
                     a, op ? "-" : "+", b, add_result, add_flags, a, b, mult_result, mult_flags);
            if (add_result !== exp_add || add_flags !== exp_add_flags) begin
                $display("  MISMATCH: add/sub expected %h (flags %b)", exp_add, exp_add_flags);
                errors = errors + 1;
            end
            if (mult_result !== exp_mult || mult_flags !== exp_mult_flags) begin
                $display("  MISMATCH: mult expected %h (flags %b)", exp_mult, exp_mult_flags);
                errors = errors + 1;
            end
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Phase 2: APB write and read tasks, as provided in examples/example_tb.v
    //////////////////////////////////////////////////////////////////////
    task write(input [`REG_ADDRWIDTH-1:0] addr, input [`REG_DATAWIDTH-1:0] data);
        begin
            @(negedge clk);
            PSEL   = 1;
            PWRITE = 1;
            PADDR  = addr;
            PWDATA = data;
            @(negedge clk);
            PENABLE = 1;
            @(negedge clk);
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;
            PADDR   = 0;
            PWDATA  = 0;
            $display("%t: PADDR %h, PWDATA %h", $time, addr, data);
        end
    endtask

    task read(input [`REG_ADDRWIDTH-1:0] addr, output [`REG_DATAWIDTH-1:0] data);
        begin
            @(negedge clk);
            PSEL   = 1;
            PWRITE = 0;
            PADDR  = addr;
            @(negedge clk);
            PENABLE = 1;
            @(negedge clk);
            PSEL    = 0;
            PENABLE = 0;
            data    = PRDATA;
            PADDR   = 0;
            $display("%t: PADDR %h, PRDATA %h", $time, addr, data);
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Phase 2: 8x8 matrices, A and B all 1.0 except A[0][0] = B[0][0] = 8.0
    //   C[0][0]            = 8.0 x 8.0 + 7 x 1.0 = +inf (8'h70): 64 overflows FP8
    //   rest of row/col 0  = 8.0 x 1.0 + 7 x 1.0 = 15.0 (8'h6E)
    //   all other elements = 8 x 1.0 = 8.0 (8'h60)
    //   FLAGS              = 10001 (Overflow, Inexact)
    // A, B and C are placed at addresses 16, 32, 64 with strides 1, 2, 3.
    //////////////////////////////////////////////////////////////////////
    task run_8x8_apb;
        integer i, j;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    mat_a[i][j] = 8'h30;            // 1.0
                    mat_b[i][j] = 8'h30;
                    exp_c[i][j] = 8'h60;            // 8.0
                end
            end
            mat_a[0][0] = 8'h60;                    // 8.0
            mat_b[0][0] = 8'h60;
            for (i = 1; i < 8; i = i + 1) begin
                exp_c[0][i] = 8'h6E;                // 15.0
                exp_c[i][0] = 8'h6E;
            end
            exp_c[0][0] = 8'h70;                    // +inf
            exp_flags   = 5'b10001;                 // Overflow, Inexact
            addr_a = 10'd16;  stride_a = 8'd1;
            addr_b = 10'd32;  stride_b = 8'd2;
            addr_c = 10'd64;  stride_c = 8'd3;
            load_rams;

            $display("  1) Write the addresses and strides");
            write(`REG_MATA_ADDR, addr_a);
            write(`REG_MATB_ADDR, addr_b);
            write(`REG_MATC_ADDR, addr_c);
            write(`REG_STRA_ADDR, stride_a);
            write(`REG_STRB_ADDR, stride_b);
            write(`REG_STRC_ADDR, stride_c);

            $display("  2) Write START");
            write(`REG_STRT_ADDR, 16'h0001);

            $display("  3) Poll DONE");
            polls = 0;
            done  = 1'b0;
            while (!done) begin
                read(`REG_DONE_ADDR, rdata);
                done  = rdata[15];
                polls = polls + 1;
            end
            $display("  DONE after %0d polls", polls);

            $display("  4) Read FLAGS");
            read(`REG_FLAG_ADDR, rdata);
            flags_read = rdata[4:0];
            runs = runs + 1;

            check_c(1'b1);
            $display("  FLAGS read over APB = %b, expected %b", flags_read, exp_flags);
            check_flags(flags_read);
        end
    endtask

    //////////////////////////////////////////////////////////////////////
    // Timeline: record when each step first happens, to place cursors.
    // Design signals are sampled mid-cycle (falling edge), APB transfers on
    // the rising edge where the slave accepts them.
    //////////////////////////////////////////////////////////////////////
    integer t_p1, t_p2, t_cfg, t_start_wr, t_read, t_tile_ab, t_flag, t_tile_c,
            t_write, t_done, t_flags_rd, t_end;

    always @(negedge clk) begin
        if (t_read    < 0 && u_matmul.start_mat_mul && u_matmul.matrix_A0.addr0 == addr_a) t_read = $time;
        if (t_tile_ab < 0 && u_matmul.u_matmul_8x8.a_tl_tr != 32'b0)  t_tile_ab = $time;
        if (t_flag    < 0 && u_matmul.exception_flags != 5'b0)        t_flag    = $time;
        if (t_tile_c  < 0 && u_matmul.u_matmul_8x8.c_tr_tl != 32'b0)  t_tile_c  = $time;
        if (t_write   < 0 && u_matmul.matrix_C0.we0 != 4'b0)          t_write   = $time;
        if (t_done    < 0 && u_matmul.done_mat_mul)                   t_done    = $time;
    end

    always @(posedge clk) begin
        if (t_cfg      < 0 && PSEL && PENABLE &&  PWRITE && PADDR == `REG_MATA_ADDR) t_cfg      = $time;
        if (t_start_wr < 0 && PSEL && PENABLE &&  PWRITE && PADDR == `REG_STRT_ADDR) t_start_wr = $time;
        if (t_flags_rd < 0 && PSEL && PENABLE && !PWRITE && PADDR == `REG_FLAG_ADDR) t_flags_rd = $time;
    end

    //////////////////////////////////////////////////////////////////////
    // Main sequence
    //////////////////////////////////////////////////////////////////////
    initial begin
        reset      = 1'b1;
        demo_phase = "RESET";
        fp_a       = 8'h00;
        fp_b       = 8'h00;
        fp_op      = 1'b0;
        PSEL       = 0;
        PENABLE    = 0;
        PWRITE     = 0;
        PADDR      = 0;
        PWDATA     = 0;
        runs       = 0;
        errors     = 0;
        addr_a     = 10'd0;  addr_b   = 10'd0;  addr_c   = 10'd0;
        stride_a   = 8'd1;   stride_b = 8'd1;   stride_c = 8'd1;
        t_p1 = -1; t_p2 = -1; t_cfg = -1; t_start_wr = -1; t_read = -1; t_tile_ab = -1;
        t_flag = -1; t_tile_c = -1; t_write = -1; t_done = -1; t_flags_rd = -1; t_end = -1;

`ifdef FSDB_DUMP
        $fsdbDumpfile("demo.fsdb");
        $fsdbDumpvars(0, demo_tb, "+all");
        $fsdbDumpMDA;
`endif

        repeat (3) @(negedge clk);
        reset = 1'b0;

        //------------------------------------------------------------------
        $display("==================== PART 1: FP8 ADDER AND MULTIPLIER ====================");
        demo_phase = "PART1 FP8 ADD/MULT";
        t_p1 = $time;
        //         a      b      op    add    flags     mult   flags
        fp8_check(8'h38, 8'h40, 1'b0, 8'h4C, 5'b00000, 8'h48, 5'b00000); // 1.5, 2.0: 3.5 and 3.0
        fp8_check(8'h30, 8'h50, 1'b1, 8'hC8, 5'b00000, 8'h50, 5'b00000); // 1.0 - 4.0 = -3.0; 1.0 x 4.0 = 4.0
        fp8_check(8'h6F, 8'h18, 1'b0, 8'h70, 5'b10001, 8'h57, 5'b00001); // 15.5 + 0.375 overflows; x rounds to 5.75
        fp8_check(8'h0F, 8'h01, 1'b0, 8'h10, 5'b00000, 8'h00, 5'b01001); // denormals: sum 0.25; product underflows
        fp8_check(8'h00, 8'h70, 1'b0, 8'h70, 5'b00000, 8'h7F, 5'b00010); // 0 + inf = inf; 0 x inf = NaN

        //------------------------------------------------------------------
        $display("==================== PARTS 2-4: 8x8 MATMUL OVER APB, WITH FLAGS =========");
        demo_phase = "PART2-4 8x8 APB + FLAGS";
        t_p2 = $time;
        run_8x8_apb;

        demo_phase = "DONE";
        t_end = $time;

        //------------------------------------------------------------------
        $display("==================== DEMO TIMELINE (ns, for waveform cursors) ============");
        $display("  Part 1     FP8 units, 5 input pairs, 40 ns each : %0d - %0d", t_p1, t_p2);
        $display("  Parts 2-4  APB: first address register write    : %0d", t_cfg);
        $display("             APB: START written                   : %0d", t_start_wr);
        $display("             RAM -> array reads begin             : %0d", t_read);
        $display("             exception flag reaches the top level : %0d", t_flag);
        $display("             A/B pass between tiles (TL -> TR)    : %0d", t_tile_ab);
        $display("             C shifts between tiles (TR -> TL)    : %0d", t_tile_c);
        $display("             first C write to RAM                 : %0d", t_write);
        $display("             done (DONE register set)             : %0d", t_done);
        $display("             APB: FLAGS read                      : %0d", t_flags_rd);
        $display("  End of demo                                     : %0d", t_end);

        $display("==========================================================================");
        if (errors == 0 && runs > 0) $display("DEMO PASS: all parts behaved as expected");
        else                         $display("DEMO FAIL: %0d mismatches", errors);

        #100;
        $finish;
    end

    // Guard against a design that never finishes
    initial begin
        #200_000;
        $display("DEMO FAIL: timeout");
        $finish;
    end

endmodule
