
`ifdef verilatorsim
`include "verilog_xilinx.svh";
`endif
`include "interfaces.svh"


/////////////////////////////////////////DELAY LINE/////////////////////////////////////////
module delay_line#(
        parameter WIDTH=17,
        parameter LENGTH=1 
    )(
        input  wire clk, ce, rst,
        input  wire [WIDTH-1:0] DATA_IN,
        output wire [WIDTH-1:0] DATA_OUT
    );

//this module delays a provided input of WIDTH bits by a number of LENGTH cycles
//in order to obtain high frequencies, a resgister is added as the last delay cycle
//this is used to sync the inputs and outputs of the 64bit multiplier modules   

generate

   if(LENGTH == 1) begin//only one delay cycle => we use a register direclty as it is faster

        genvar i;
        for(i=0; i<WIDTH;i=i+1) begin
            FDRE FDRE_inst (
                .Q(DATA_OUT[i]),   // 1-bit output: Data
                .C(clk),   // 1-bit input: Clock
                .CE(ce), // 1-bit input: Clock enable
                .D(DATA_IN[i]),   // 1-bit input: Data
                .R(rst)    // 1-bit input: Synchronous reset
            );
        end

   end
   else begin //else we use a SRL+REG for fast delay line

        wire A3, A2, A1, A0;
        assign {A3, A2, A1, A0} = LENGTH - 2; //we subtract one as last delay cycle will be done through register 
        wire [WIDTH-1:0] SLR_WIRE;            //the second subtract is because the idex starts from 0

        reg [3:0] flush_counter = '0;
        always@(posedge clk) begin
            if(rst)
                flush_counter <= LENGTH;
            else
                flush_counter <= flush_counter != '0 ? flush_counter - 1'b1 : '0;
        end

        genvar i;
        for(i=0; i<WIDTH;i=i+1) begin
            FDRE FDRE_inst (
                .Q(DATA_OUT[i]),   // 1-bit output: Data
                .C(clk),   // 1-bit input: Clock
                .CE(ce), // 1-bit input: Clock enable
                .D(SLR_WIRE[i]),   // 1-bit input: Data
                .R(flush_counter != '0)    // 1-bit input: Synchronous reset
            );
        end

        for(i=0; i<WIDTH;i=i+1) begin
            SRL16E #(
                .INIT(16'h0000),        // Initial contents of shift register
                .IS_CLK_INVERTED(1'b0)  // Optional inversion for CLK
            )
            SRL16E_inst (
                .Q(SLR_WIRE[i]),  // 1-bit output: SRL Data
                .CE(ce),            // 1-bit input: Clock enable
                .CLK(clk),          // 1-bit input: Clock
                .D(flush_counter != '0 ? '0 : DATA_IN[i]),     // 1-bit input: SRL Data
                // Depth Selection inputs: A0-A3 select SRL depth
                .A0(A0),
                .A1(A1),
                .A2(A2),
                .A3(A3) 
            );
        end
   end
endgenerate

endmodule


/////////////////////////////////////////SYNC FIFO/////////////////////////////////////////
module sync_fifo #(
        parameter int DEPTH=8, 
        parameter type DATA_T = logic [31:0],
        parameter string FIFO_NAME = "",
        parameter int DEBUG = 1
    )(
        input  logic                     clk,
        input  logic                     rst,
        input  logic                     i_clear,
        input  logic                     i_wr_en,    // Write enable
        input  logic                     i_rd_en,    // Read enable
        input  DATA_T                    i_data,     // Data written into FIFO
        output DATA_T                    o_data,     // Data read from FIFO
        output logic                     o_empty,    // FIFO is empty when high
        output logic                     o_full     // FIFO is full when high,
    );

    logic [$clog2(DEPTH)-1:0] wptr;
    logic [$clog2(DEPTH)-1:0] rptr;

    logic w_almost_full, w_almost_empty;
    logic r_full, r_empty;
    DATA_T fifo [DEPTH];

    always_ff @(posedge clk) begin
        if (rst || i_clear) begin
            wptr <= 0;
            r_full <= '0;
        end
        else begin
            if (i_wr_en & !o_full) begin
                fifo[wptr] <= i_data;
                wptr <= wptr + 1'b1;
                if(w_almost_full)
                    r_full <= '1;
            end
            else if(o_full && i_rd_en)
                r_full <= '0;
        end
    end

    initial begin
        if (DEBUG)
            $monitor("[%0t] [FIFO %s] wr_en=%0b din=0x%0h rd_en=%0b dout=0x%0h empty=%0b full=%0b", $time, FIFO_NAME, i_wr_en, i_data, i_rd_en, o_data, o_empty, o_full);
    end

    always_ff @(posedge clk) begin
        if (rst || i_clear) begin
            rptr <= 0;
            o_data <= '0;
            r_empty <= '1;
        end
        else begin
            if (i_rd_en & !o_empty) begin
                o_data <= fifo[rptr];
                rptr <= rptr + 1'b1;
                if(w_almost_empty)
                    r_empty <= '1;
            end
            else if(o_empty && i_wr_en)
                r_empty <= '0;
        end
    end

    assign w_almost_full = wptr + 1'b1 == rptr;
    assign w_almost_empty = rptr + 1'b1 == wptr;
    assign o_full  = r_full;
    assign o_empty = r_empty;
endmodule


/////////////////////////////////////////SKID BUFFER/////////////////////////////////////////
module skid_buffer (
    // system signals
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  i_clear,

    //upstream interface
    handshakeIf.Upstream hsup,

    //downstream interface
    handshakeIf.Downstream hsdown
);
    initial assert($bits(hsup.data) == $bits(hsdown.data));
    localparam type data_t = bit [hsup.DATA_WIDTH-1:0];

    // CONTROL PATH -----------------------------

    typedef enum logic [2:0] {
        EMPTY = 3'b001,
        BUSY  = 3'b010,
        FULL  = 3'b100
    } state_t;

    state_t state, next_state;  // state variables
    logic accept, transmit;  // handshake flags on each interface
    data_t buffer;  // the "skid" buffer of type DATA_T

    always_comb begin : next_state_logic
        accept     = hsup.valid && hsup.ready;  // check for input handshake
        transmit   = hsdown.valid && hsdown.ready;  // check for output handshake
        next_state = EMPTY;
        unique case (state)
            EMPTY: begin
                next_state = EMPTY;
                if (accept) next_state = BUSY;
            end
            BUSY: begin
                next_state = BUSY;
                if (accept && !transmit) next_state = FULL;
                else if (!accept && transmit) next_state = EMPTY;
            end
            FULL: begin
                next_state = FULL;
                if (transmit) next_state = BUSY;
            end
            default: next_state = EMPTY;
        endcase
    end : next_state_logic

    always_ff @(posedge clk) begin : update_state_logic
        if (rst || i_clear) begin
            state          <= EMPTY;
            hsup.ready  <= 1'b0;
            hsdown.valid <= 1'b0;
        end else begin
            state          <= next_state;
            hsup.ready  <= next_state != FULL;
            hsdown.valid <= next_state != EMPTY;
        end
    end : update_state_logic

    logic buffer_write_en, o_data_write_en;
    always_comb begin : write_en_logic
        buffer_write_en = state == BUSY && accept && !transmit;
        o_data_write_en = (state == EMPTY && accept && !transmit)
                      || (state == BUSY && accept && transmit)
                      || (state == FULL && !accept && transmit);
    end : write_en_logic

    // END OF CONTROL PATH ----------------------

    // DATA PATH --------------------------------

    always_ff @(posedge clk) begin : o_data_and_buffer_logic
        if (rst || i_clear) begin
            hsdown.data <= '0;
            buffer <= '0;
        end else begin

            if (o_data_write_en) begin
                if (state == FULL) hsdown.data <= buffer;
                else hsdown.data <= hsup.data;
            end

            if (buffer_write_en) begin
                buffer <= hsup.data;
            end

        end
    end : o_data_and_buffer_logic

    // END OF DATA PATH -------------------------

endmodule


/////////////////////////////////////////QUEUE/////////////////////////////////////////
module queue#(
        parameter int DEPTH=8,
        parameter int DEBUG = 1,
        parameter string QUEUE_NAME = ""
    )(
        // system signals
        input  logic                  clk,
        input  logic                  rst,
        input  logic                  i_clear,

        //upstream interface
        handshakeIf.Upstream hsup,

        //downstream interface
        handshakeIf.Downstream hsdown
    );

    initial assert($bits(hsup.data) == $bits(hsdown.data));
    localparam type data_t = bit [hsup.DATA_WIDTH-1:0];

    //1-depth skid_buffer on input
    //full throughput, direct connection and no latency when FIFO is not full
    //skid data when FIFO becomes full to not loose data entry
    data_t data_rg; // Data buffer
    logic bypass_rg  = 1'b1; // Bypass signal to data and data valid muxes
    logic w_ready;

    always_ff@(posedge clk)
        hsup.ready <= bypass_rg;

    always_ff @(posedge clk) begin
        if (rst || i_clear) begin
            data_rg   <= '0;
            bypass_rg <= 1'b1;
        end
        else begin
            if (bypass_rg) begin
                if (!w_ready && hsup.valid) begin
                    data_rg   <= hsup.data; // Data skid happened, store to buffer
                    bypass_rg <= 1'b0;    // To skid mode  
                end
            end
            else begin
                if (w_ready) begin
                    bypass_rg <= 1'b1; // Back to bypass mode
                end
            end
        end
    end

    //data going into the actual FIFO
    data_t w_data;
    logic w_valid, w_full;
    assign w_data  = bypass_rg ? hsup.data  : data_rg ;  // Data mux
    assign w_valid = bypass_rg ? hsup.valid : 1'b1    ;  // Data valid mux
    assign w_ready = ~w_full;

    logic w_empty;
    sync_fifo #(
        .DEPTH(DEPTH),
        .DATA_T(data_t),
        .DEBUG(DEBUG),
        .FIFO_NAME(QUEUE_NAME)
    ) fifo_inst(
        .clk(clk),
        .rst(rst),
        .i_clear(i_clear),
        .i_wr_en(w_valid), // Write enable
        .i_rd_en(hsdown.ready), // Read enable
        .i_data(w_data),  // Data written into FIFO
        .o_data(hsdown.data),  // Data read from FIFO
        .o_empty(w_empty), // FIFO is empty when high
        .o_full(w_full)   // FIFO is full when high
    );

    always_ff@(posedge clk)
        hsdown.valid <= ~w_empty;

endmodule