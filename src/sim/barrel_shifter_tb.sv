`include "functional_units.svh"
`timescale 1ns / 1ps

module barrel_shifter_tb;
    localparam int DATA_WIDTH = 32;
    localparam int N = $clog2(DATA_WIDTH);
    logic clk;
    logic  rst;
    logic en;
    logic [DATA_WIDTH-1:0]  i_data;
    logic [N-1:0]           i_shamt;
    shift_op_t          i_shconf;
    logic [DATA_WIDTH-1:0] o_data;
    logic                  o_valid;

    barrel_shifter_N #(.DATA_WIDTH(DATA_WIDTH), .EXTRA_PIPE("TRUE")) uut(.*);

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, barrel_shifter_tb);
        clk = 1'b0;
        rst = 1'b1;
        en = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        #10 rst = 1'b0;
        en = 1'b1;
        for (int i = 0; i < 32; ++i)
            begin
                i_data = 32'h8000_0001; i_shamt = i; i_shconf = ROTL_OP; #10;
            end
        for (int i = 0; i < 32; ++i)
            begin
                i_data = 32'h8000_0001; i_shamt = i; i_shconf = ROTR_OP; #10;
            end
         for (int i = 0; i < 32; ++i)
            begin
                i_data = 32'h800F_000F; i_shamt = i; i_shconf = SLL_OP; #10;
            end
         for (int i = 0; i < 32; ++i)
            begin
                i_data = 32'h800F_000F; i_shamt = i; i_shconf = SRL_OP; #10;
            end
         for (int i = 0; i < 32; ++i)
            begin
                i_data = 32'h800F_000F; i_shamt = i; i_shconf = SRA_OP; #10;
            end
        $stop;
    end

endmodule
