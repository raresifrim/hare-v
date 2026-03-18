`include "buffers.svh"
`timescale 1ns / 1ps

module sync_fifo_tb;

    localparam DATA_WIDTH = 16;
    localparam DEPTH = 8;

    logic                  clk;
    logic                  rst;
    logic                  i_clear;
    logic                  i_wr_en; // Write enable
    logic                  i_rd_en; // Read enable
    logic [DATA_WIDTH-1:0] i_data;  // Data written into FIFO
    logic [DATA_WIDTH-1:0] o_data;  // Data read from FIFO
    logic                  o_empty; // FIFO is empty when high
    logic                  o_full;   // FIFO is full when high
    logic                  stop, start;
    logic [DATA_WIDTH-1:0] rdata;

    sync_fifo #(.DATA_T(logic[DATA_WIDTH-1:0])) dut_sync_fifo (.*);

    always #10 clk <= ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, sync_fifo_tb);
        clk = 0;
        rst = 1;
        i_clear = 1'b0;
        i_wr_en = 0;
        i_rd_en = 0;
        start = 0; stop = 0;
        #50 rst <= 0;

        @(posedge clk);

       //fill fifo enterely
       for (int i = 0; i < DEPTH; i = i+1) begin
        i_wr_en = 1'b1;
        i_data = $random;
        $display("[%0t] clk i=%0d wr_en=%0d din=0x%0h ", $time, i, i_wr_en, i_data);
        // Wait for next clock edge
        @(posedge clk);
       end

       i_wr_en = 1'b0;
       //empty fifo enterely
       for (int i = 0; i < DEPTH; i = i+1) begin
        // Sample new values from FIFO at random pace
        i_rd_en <= '1;
        @(posedge clk);
        rdata <= o_data;
        $display("[%0t] clk rd_en=%0d rdata=0x%0h ", $time, i_rd_en, rdata);
       end
       i_rd_en = 1'b0;
       start = '1; //start random test
  end

  initial begin

    while(!start) begin
      @(posedge clk);
    end

    for (int i = 0; i < 20; i = i+1) begin
      // Wait until there is space in fifo
      while (o_full) begin
        @(posedge clk);
        $display("[%0t] FIFO is full, wait for reads to happen", $time);
      end;

      // Drive new values into FIFO
      i_wr_en = $random;
      i_data = $random;
      $display("[%0t] clk i=%0d wr_en=%0d din=0x%0h ", $time, i, i_wr_en, i_data);

      // Wait for next clock edge
      @(posedge clk);
    end

    stop = 1;
  end

  initial begin

    while(!start) begin
      @(posedge clk);
    end

    while (!stop) begin
      // Wait until there is data in fifo
      while (o_empty) begin
        i_rd_en <= 0;
        $display("[%0t] FIFO is empty, wait for writes to happen", $time);
        @(posedge clk);
      end;

      // Sample new values from FIFO at random pace
      i_rd_en <= $random;
      @(posedge clk);
      rdata <= o_data;
      $display("[%0t] clk rd_en=%0d rdata=0x%0h ", $time, i_rd_en, rdata);
    end

    #500 $finish;
  end
endmodule