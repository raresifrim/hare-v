`include "buffers.svh"
`timescale 1ns / 1ps

module skid_buffer_tb;

    localparam int DATA_WIDTH = 8;

    logic clk;
    logic rst;
    logic i_clear;

    //upstream interface
    handshakeIf #(.DATA_T(bit[DATA_WIDTH-1:0])) hsup();

    //downstream interface
    handshakeIf #(.DATA_T(bit[DATA_WIDTH-1:0])) hsdown();

    skid_buffer dut(.*);

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, skid_buffer_tb);
        #0 clk = '0;
        forever #5 clk = ~clk;
    end

    initial begin
        #0 rst = '1;
        //Test some single burst writes and reads
        #10; rst = '0;

        //make some back-to-back transactions
        for(int i=0;i<16;i++) begin
            hsup.data = 8'(i+1);
            hsup.valid = 1'b1;
            hsdown.ready = 1'b1;
            #10;
        end

        //then set downstream as busy and try to make some back-to-back transactions again
        for(int i=16;i<19;i++) begin
            hsup.data = 8'(i+1);
            hsup.valid = 1'b1;
            hsdown.ready = 1'b0;
            #10;
        end
        //then make the downstream module ready again
        hsdown.ready = 1'b1;
        hsup.valid = 1'b0;
        #30;
        $finish;
    end

endmodule