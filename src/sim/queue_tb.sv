`include "buffers.svh"
`include "interfaces.svh"
`timescale 1ns/1ps

module queue_tb;

    // Parameters
    parameter int DEPTH = 8;
    parameter int DATA_WIDTH = 32;
    parameter int CLK_PERIOD = 10;

    // Signals
    logic clk;
    logic rst;
    logic i_clear;

    // Interface Instantiations
    handshakeIf #(.DATA_T(logic [DATA_WIDTH-1:0])) upstream_if(clk);
    handshakeIf #(.DATA_T(logic [DATA_WIDTH-1:0])) downstream_if(clk);

    // DUT Instantiation
    queue #(
        .DEPTH(DEPTH),
        .DEBUG(1),
        .QUEUE_NAME("TEST")
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .i_clear (i_clear),
        .hsup    (upstream_if.Upstream),
        .hsdown  (downstream_if.Downstream)
    );

    // Clock Generation
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0,queue_tb);
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Test Sequence ---
    initial begin
        // Initialize signals
        rst = 1;
        i_clear = 0;
        upstream_if.valid = 0;
        upstream_if.data = 0;
        downstream_if.ready = 0;

        // Reset Pulse
        repeat(2) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("\n--- Starting Test: Push until Full ---");
        for (int i = 0; i <= DEPTH; i++) begin
            upstream_if.push_data(i + 32'hA0);
        end
        
        // Check if ready dropped after being full
        @(posedge clk);
        if (upstream_if.ready === 0) 
            $display("[STATUS] Queue is FULL as expected.");
        else
            $error("[ERROR] Queue should be FULL but ready is still high!");

        $display("\n--- Starting Test: Pop until Empty ---");
        for (int i = 0; i <= DEPTH; i++) begin
            logic [DATA_WIDTH-1:0] rdata;
            downstream_if.pop_data(rdata);
        end

        // Check if valid dropped after being empty
        @(posedge clk);
        if (downstream_if.valid === 0)
            $display("[STATUS] Queue is EMPTY as expected.");
        else
            $error("[ERROR] Queue should be EMPTY but valid is still high!");

        $display("\n--- Starting Test: Simultaneous Push/Pop ---");
        fork
            // Producer Thread
            begin
                for(int i = 0; i < 5; i++) upstream_if.push_data(i + 32'hF0);
            end
            // Consumer Thread (delayed slightly)
            begin
                #CLK_PERIOD;
                for(int i = 0; i < 5; i++) begin
                    logic [DATA_WIDTH-1:0] rdata;
                    downstream_if.pop_data(rdata);
                end
            end
        join

        #50;
        $display("\n--- Simulation Finished ---");
        $finish;
    end

endmodule