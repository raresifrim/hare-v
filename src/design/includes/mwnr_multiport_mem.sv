//live value table (LVT) approach of implementing a multi-port memory
//reference: Composing Multi-Ported Memories on FPGAs by LAFOREST (2014) - https://people.csail.mit.edu/ml/pubs/trets_multiport.pdf
module mwnr_multiport_mem#(
        parameter int NUM_WRITE = 4,
        parameter int NUM_READ = 8,
        parameter type DATA_T = bit[31:0],
        parameter int ADDR_WIDTH = 5,
        parameter string RAMSTYLE = "block"
    )(
        input logic                  clk,
        input logic                  rst,
        input logic                  ce,
        input logic                  i_we    [NUM_WRITE],
        input logic [ADDR_WIDTH-1:0] i_waddr [NUM_WRITE],
        input logic [ADDR_WIDTH-1:0] i_raddr [NUM_READ],
        input  DATA_T                i_wdata [NUM_WRITE],
        output DATA_T                o_rdata [NUM_READ]
    );

    generate
        if (NUM_WRITE == 1) //no need for live-value table with a single write port
            ram_1wnr_bank #(
                .DATA_T(DATA_T),
                .ADDR_WIDTH(ADDR_WIDTH),
                .RAMSTYLE(RAMSTYLE),
                .NUM_READ(NUM_READ)
            ) bank_inst(
                .clk(clk),
                .ce(ce),
                .i_we(i_we[0]),
                .i_waddr(i_waddr[0]),
                .i_wdata(i_wdata[0]),
                .i_raddr(i_raddr),
                .o_rdata(o_rdata)
            );
        else begin

            //live value table
            logic [$clog2(NUM_WRITE)-1:0] w_rmux [NUM_READ];
            live_value_table#(
                .NUM_WRITE(NUM_WRITE),
                .NUM_READ(NUM_READ),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) lvt_inst(
                .clk(clk),
                .rst(rst),
                .ce(ce),
                .i_we(i_we),
                .i_waddr(i_waddr),
                .i_raddr(i_raddr),
                .o_rmux(w_rmux)
            );

            //memory banks
            DATA_T w_rdata [NUM_WRITE][NUM_READ];
            genvar i,j;
            for(i=0; i < NUM_WRITE; i++) begin
                ram_1wnr_bank #(
                    .DATA_T(DATA_T),
                    .ADDR_WIDTH(ADDR_WIDTH),
                    .RAMSTYLE(RAMSTYLE),
                    .NUM_READ(NUM_READ)
                ) bank_inst(
                    .clk(clk),
                    .ce(ce),
                    .i_we(i_we[i]),
                    .i_waddr(i_waddr[i]),
                    .i_wdata(i_wdata[i]),
                    .i_raddr(i_raddr),
                    .o_rdata(w_rdata[i])
                );
            end

            //switch matrix for final output on read ports
            DATA_T w_sdata [NUM_READ][NUM_WRITE];
            for(i=0;i<NUM_READ;i++) begin
                for(j=0;j<NUM_WRITE;j++)
                    assign w_sdata[i][j] = w_rdata[j][i];
            end
            for(i=0; i < NUM_READ; i++) begin
                n2one_mux#(
                    .DATA_T(DATA_T),
                    .NUM_INPUTS(NUM_WRITE)
                )mux_inst(
                    .i_select_line(w_rmux[i]),
                    .i_data(w_sdata[i]),
                    .o_data(o_rdata[i])
                );
            end
        end
    endgenerate

endmodule

module live_value_table#(
        parameter int NUM_WRITE = 4,
        parameter int NUM_READ = 8,
        parameter int ADDR_WIDTH = 5
    )(
        input logic                          clk,
        (*direct_reset="true"*)input logic   rst,
        (*direct_enable="true"*)input logic  ce,
        input logic                          i_we    [NUM_WRITE],
        input logic  [ADDR_WIDTH-1:0]        i_waddr [NUM_WRITE],
        input logic  [ADDR_WIDTH-1:0]        i_raddr [NUM_READ],
        output logic [$clog2(NUM_WRITE)-1:0] o_rmux  [NUM_READ]
    );

    (*ram_style = "distributed"*)(*rw_addr_collision = "yes" *) logic [$clog2(NUM_WRITE)-1:0] ram [2**ADDR_WIDTH];

    logic                          r_we    [NUM_WRITE];
    logic  [ADDR_WIDTH-1:0]        r_waddr [NUM_WRITE];
    logic  [ADDR_WIDTH-1:0]        r_raddr [NUM_READ];

    always_ff@(posedge clk) begin
        if(rst) begin
            for (int i=0;i<NUM_WRITE;i++) begin
                r_we[i] <= '0;
                r_waddr[i] <= '0;
            end
            for (int i=0;i<NUM_READ;i++) begin
                r_raddr[i] <= '0;
            end
            for (int i=0;i<2**ADDR_WIDTH;i++) begin
                ram[i] <= '0;
            end
        end
        else if(ce) begin
            for(int i=0;i<NUM_WRITE;i++) begin
                r_we[i] <= i_we[i];
                r_waddr[i] <= i_waddr[i];
            end
            for (int i=0;i<NUM_READ;i++) begin
                r_raddr[i] <= i_raddr[i];
            end
            for (int i=0;i<NUM_WRITE;i++) begin
                if(r_we[i])
                    ram[r_waddr[i]] <= i;
            end
            for (int i=0;i<NUM_READ;i++) begin
                o_rmux[i] <= ram[r_raddr[i]];
            end
        end
    end

endmodule

module ram_1wnr_bank#(
        parameter type DATA_T = bit[31:0],
        parameter int ADDR_WIDTH = 5,
        parameter int NUM_READ = 8,
        parameter string RAMSTYLE = "block"
    )(
        input logic                   clk,
        input  logic                  ce,
        input  logic                  i_we,
        input  logic [ADDR_WIDTH-1:0] i_waddr,
        input  logic [ADDR_WIDTH-1:0] i_raddr [NUM_READ],
        input  DATA_T                 i_wdata,
        output DATA_T                 o_rdata [NUM_READ]
    );

    generate
        genvar i;
        for(i=0; i < NUM_READ; i++) begin
           ram_sdp_wf #(
            .DATA_T(DATA_T),
            .ADDR_WIDTH(ADDR_WIDTH),
            .RAMSTYLE(RAMSTYLE)
           ) ram_1w1r_bank (
            .clk(clk),
            .ce(ce),
            .i_we(i_we),
            .i_waddr(i_waddr),
            .i_raddr(i_raddr[i]),
            .i_wdata(i_wdata),
            .o_rdata(o_rdata[i])
           );
        end
    endgenerate

endmodule


// Simple Dual-Port Block RAM with One Clock
// File: simple_dual_one_clock.v
//reference: https://docs.amd.com/r/en-US/ug901-vivado-synthesis/Simple-Dual-Port-Block-RAM-Examples
module ram_sdp_wf#(
        parameter type DATA_T = bit[31:0],
        parameter int ADDR_WIDTH = 5,
        parameter string RAMSTYLE = "block"
    )(
        input logic                   clk,
        input  logic                  ce,
        input  logic                  i_we,
        input  logic [ADDR_WIDTH-1:0] i_waddr,
        input  logic [ADDR_WIDTH-1:0] i_raddr,
        input  DATA_T                 i_wdata,
        output DATA_T                 o_rdata
    );

        //infer a WRITE_FIRST memory of the provided style (block, distributed, etc)
        (*ram_style = RAMSTYLE*)(*rw_addr_collision = "yes" *) DATA_T ram [2**ADDR_WIDTH];

        //register address and inputs for better timing
        logic [ADDR_WIDTH-1:0] r_waddr, r_raddr;
        DATA_T r_data;
        logic r_we;

        always_ff @(posedge clk) begin
            if (ce) begin
                r_data <= i_wdata;
                r_waddr <= i_waddr;
                r_raddr <= i_raddr;
                r_we <= i_we;
                if (r_we)
                    ram[r_waddr] <= r_data;
                o_rdata <= ram[r_raddr];
            end
        end

endmodule


module n2one_mux#(
        parameter type DATA_T = bit[31:0],
        parameter int NUM_INPUTS = 8,
        localparam SELECT_WIDTH = $clog2(NUM_INPUTS)
    )(
        input  [SELECT_WIDTH-1:0] i_select_line,
        input  DATA_T             i_data [NUM_INPUTS],
        output DATA_T             o_data
    );

    always_comb begin
        o_data = i_data[i_select_line];
    end

endmodule

