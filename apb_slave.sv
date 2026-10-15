
`define REG_ADDRWIDTH 10
`define REG_DATAWIDTH 5
`define REG_STRT_ADDR 1
`define REG_DONE_ADDR 2

module apb_slave (
    input  logic                      PCLK,
    input  logic                      PRESETn,
    input  logic [`REG_ADDRWIDTH-1:0] PADDR,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    input  logic [`REG_DATAWIDTH-1:0] PWDATA,
    output logic [`REG_DATAWIDTH-1:0] PRDATA,
    output logic                      PREADY,
    output logic                      start,
    // .....
    input  logic                      done
    // .....
);

    typedef enum logic [1:0] {IDLE, SETUP, READ_ACCESS, WRITE_ACCESS} state_t;
    state_t State;

    always_ff @(posedge PCLK) begin
        if (!PRESETn) begin
            State <= IDLE;
            // .....
        end else begin
            case (State)
                // ....

                WRITE_ACCESS: begin
                    if (PWRITE && PENABLE) begin
                        case (PADDR)
                            `REG_STRT_ADDR: start <= PWDATA[0];
                            // .....
                        endcase
                    end
                end

                READ_ACCESS: begin
                    if (!PWRITE && PENABLE) begin
                        case (PADDR)
                            `REG_DONE_ADDR: PRDATA <= {done, 15'b0};
                            // ....
                        endcase
                    end
                end

                // ....
            endcase
        end
    end

endmodule
