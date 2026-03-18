`timescale 1ns/1ps

module mwnr_multiport_mem_tb;

    // Parameters
    localparam int NUM_WRITE  = 4;
    localparam int NUM_READ   = 8;
    localparam int ADDR_WIDTH = 6; // 2^6 = 64 entries
    typedef bit [31:0] data_t;

    // DUT Signals
    logic              clk;
    logic              rst;
    logic              ce;
    logic              i_we    [NUM_WRITE];
    logic [ADDR_WIDTH-1:0] i_waddr [NUM_WRITE];
    logic [ADDR_WIDTH-1:0] i_raddr [NUM_READ];
    data_t             i_wdata [NUM_WRITE];
    data_t             o_rdata [NUM_READ];

    // Instantiate DUT
    mwnr_multiport_mem #(
        .NUM_WRITE(NUM_WRITE),
        .NUM_READ(NUM_READ),
        .DATA_T(data_t),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (.*);

    // Clock Generation
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0,mwnr_multiport_mem_tb);
        clk = 0;
    end
    always #5 clk = ~clk;

    // Task to clear inputs
    task automatic clear_inputs();
        ce = 0;
        for (int i=0; i<NUM_WRITE; i++) begin
            i_we[i]    = 0;
            i_waddr[i] = 0;
            i_wdata[i] = 32'h0;
        end
        for (int i=0; i<NUM_READ; i++) begin
            i_raddr[i] = 0;
        end
    endtask

    // Test Sequence
    initial begin
        clear_inputs();
        rst = 1;
        repeat(2) @(posedge clk);
        rst = 0;
        ce = 1;
        @(posedge clk);

        // --- TEST 1: Parallel Writes to Unique Addresses ---
        $display("[%0t] Test 1: Writing unique values to ports 0-3", $time);
        for (int i=0; i<NUM_WRITE; i++) begin
            i_we[i]    = 1;
            i_waddr[i] = i;        // Addresses 0, 1, 2, 3
            i_wdata[i] = 32'hAAAA_0000 + i;
        end
        @(posedge clk);
        clear_inputs();
        ce = 1;
        
        // Wait for 2-cycle write latency
        repeat(2) @(posedge clk);

        // --- TEST 2: Parallel Read Collision (Same Address) ---
        // All 8 read ports look at address 2
        $display("[%0t] Test 2: Multi-port Read Collision on Address 2", $time);
        for (int i=0; i<NUM_READ; i++) begin
            i_raddr[i] = 2; 
        end
        
        repeat(2) @(posedge clk); // Pipeline delay
        $display("[%0t] Port 0 Read Data: %h (Expected AAAA0002)", $time, o_rdata[0]);
        $display("[%0t] Port 7 Read Data: %h (Expected AAAA0002)", $time, o_rdata[7]);

        // --- TEST 3: Simultaneous Write and Read (Same Address) ---
        // Writing new data to Address 10, while reading Address 10.
        // Expectation: Read returns old data (or X) due to 2-cycle latency 
        // unless internal bypassing exists.
        $display("[%0t] Test 3: Simultaneous Write/Read Collision on Address 10", $time);
        
        // Write to Addr 10
        i_we[0]    = 1;
        i_waddr[0] = 10;
        i_wdata[0] = 32'hBEEF_CAFE;
        
        // Read from Addr 10 on all ports
        for (int i=0; i<NUM_READ; i++) i_raddr[i] = 10;
        
        @(posedge clk);
        clear_inputs();
        ce = 1;

        repeat(2) @(posedge clk);
        $display("[%0t] Read Result during write: %h", $time, o_rdata[0]);
        
        // Now read again to see if the write finished
        for (int i=0; i<NUM_READ; i++) i_raddr[i] = 10;
        repeat(2) @(posedge clk);
        $display("[%0t] Read Result after 2 cycles: %h (Expected BEEFCAFE)", $time, o_rdata[0]);

        #50 $finish;
    end

endmodule