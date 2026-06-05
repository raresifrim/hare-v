`timescale 1ns/1ps

// Testbench for mwnr_multiport_mem (LVT-based multi-write / multi-read memory).
//
// Timing model (derived from the RTL):
//   * 2-cycle read latency: address driven at cycle R -> o_rdata valid at R+2.
//   * A read addressed at cycle R reflects writes presented at cycles <= R-1
//     (input registering skews write visibility by one cycle), so a same-cycle
//     write+read to the same address returns the OLD value.
//   * Same-cycle write conflict on one address: highest-numbered write port wins
//     (the LVT records the last port index in a loop).
//   * Across cycles: last write wins (the LVT re-points the read mux).
//
// Scoreboard: a reference memory (associative array) is the golden model.  Each
// cycle every read port's expected value is computed from the model state
// *before* that cycle's writes, pushed through a 2-deep delay line, then
// compared against o_rdata when it emerges.  Writes are applied in port order so
// the highest index wins on a same-cycle, same-address tie.  ce is held high.

module mwnr_multiport_mem_tb;

    localparam int NumWrite  = 4;
    localparam int NumRead   = 8;
    localparam int AddrWidth = 6;          // 64 entries
    localparam int AddrRange = 16;         // constrain stimulus to force collisions
    typedef bit [31:0] data_t;

    logic                 clk, rst, ce;
    logic                 i_we    [NumWrite];
    logic [AddrWidth-1:0] i_waddr [NumWrite];
    logic [AddrWidth-1:0] i_raddr [NumRead];
    data_t                i_wdata [NumWrite];
    data_t                o_rdata [NumRead];

    mwnr_multiport_mem #(
        .NUM_WRITE (NumWrite),
        .NUM_READ  (NumRead),
        .DATA_T    (data_t),
        .ADDR_WIDTH(AddrWidth)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Reference model + 2-deep expectation pipeline
    // -------------------------------------------------------------------------
    data_t model [logic [AddrWidth-1:0]];     // golden live memory
    bit    chk_1 [NumRead];  data_t val_1 [NumRead];   // expectation from the previous cycle
    int    pass_cnt = 0;
    int    fail_cnt = 0;

    task automatic clear_we();
        for (int i = 0; i < NumWrite; i++) begin
            i_we[i]    = 0;
            i_waddr[i] = 0;
            i_wdata[i] = 0;
        end
    endtask

    // One scoreboard cycle.  Caller drives i_we/i_waddr/i_wdata/i_raddr first.
    task automatic step();
        bit                   chk_0 [NumRead];
        data_t                val_0 [NumRead];
        logic [AddrWidth-1:0] a;

        #1;
        // 1) outputs now reflect the addresses driven on the previous cycle
        for (int r = 0; r < NumRead; r++) begin
            if (chk_1[r]) begin
                if (o_rdata[r] !== val_1[r]) begin
                    $display("[FAIL] o_rdata[%0d]=0x%08h expected=0x%08h", r, o_rdata[r], val_1[r]);
                    fail_cnt++;
                end else begin
                    pass_cnt++;
                end
            end
        end
        // 2) expectation for this cycle's reads: model holds writes <= C-1
        for (int r = 0; r < NumRead; r++) begin
            a = i_raddr[r];
            if (model.exists(a)) begin
                chk_0[r] = 1;
                val_0[r] = model[a];
            end else begin
                chk_0[r] = 0;
            end
        end
        // 3) advance the delay line
        for (int r = 0; r < NumRead; r++) begin
            chk_1[r] = chk_0[r]; val_1[r] = val_0[r];
        end
        // 4) apply this cycle's writes in port order (highest index wins on tie)
        for (int w = 0; w < NumWrite; w++)
            if (i_we[w]) model[i_waddr[w]] = i_wdata[w];

        @(posedge clk);
    endtask

    task automatic do_reset();
        model.delete();
        clear_we();
        for (int r = 0; r < NumRead; r++) begin
            i_raddr[r] = 0;
            chk_1[r] = 0;
        end
        ce = 1; rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);
    endtask

    // Point every read port at one address.
    task automatic read_all(input logic [AddrWidth-1:0] a);
        for (int r = 0; r < NumRead; r++) i_raddr[r] = a;
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, mwnr_multiport_mem_tb);

        do_reset();

        // ---- TEST 1: parallel writes to unique addresses, read them back ----
        $display("\n=== TEST 1: parallel unique writes ===");
        clear_we();
        for (int p = 0; p < NumWrite; p++) begin
            i_we[p]    = 1;
            i_waddr[p] = p*3 + 1;
            i_wdata[p] = 32'hA000_0000 + p;
        end
        step();
        clear_we();
        for (int r = 0; r < NumRead; r++) i_raddr[r] = (r % NumWrite)*3 + 1;
        repeat(4) step();

        // ---- TEST 2: same-cycle write conflict (highest port wins) ----
        $display("\n=== TEST 2: write conflict on one address ===");
        clear_we();
        for (int p = 0; p < NumWrite; p++) begin
            i_we[p]    = 1;
            i_waddr[p] = 20;
            i_wdata[p] = 32'hC000_0000 + p;   // model -> port (NumWrite-1) data
        end
        step();
        clear_we();
        read_all(20);
        repeat(4) step();

        // ---- TEST 3: each read port reads a distinct address ----
        $display("\n=== TEST 3: distinct per-port reads ===");
        clear_we();
        for (int p = 0; p < NumWrite; p++) begin
            i_we[p] = 1; i_waddr[p] = p;             i_wdata[p] = 32'hD000_0000 + p;
        end
        step();
        for (int p = 0; p < NumWrite; p++) begin
            i_we[p] = 1; i_waddr[p] = NumWrite + p;  i_wdata[p] = 32'hD000_0000 + NumWrite + p;
        end
        step();
        clear_we();
        for (int r = 0; r < NumRead; r++) i_raddr[r] = r;   // 0..7
        repeat(4) step();

        // ---- TEST 4: last-write-wins over time (LVT bank switching) ----
        $display("\n=== TEST 4: last-write-wins / LVT switching ===");
        clear_we();
        i_we[0] = 1; i_waddr[0] = 30; i_wdata[0] = 32'h1111_0000; step(); clear_we();
        read_all(30); repeat(4) step();
        i_we[2] = 1; i_waddr[2] = 30; i_wdata[2] = 32'h2222_0000; step(); clear_we();
        read_all(30); repeat(4) step();
        i_we[1] = 1; i_waddr[1] = 30; i_wdata[1] = 32'h3333_0000; step(); clear_we();
        read_all(30); repeat(4) step();

        // ---- TEST 5: same-cycle write+read returns OLD value ----
        $display("\n=== TEST 5: same-cycle write/read collision ===");
        clear_we();
        i_we[0] = 1; i_waddr[0] = 40; i_wdata[0] = 32'hAABB_0000; step(); clear_we();
        read_all(40); repeat(4) step();
        // drive a new write and a read of addr 40 in the SAME cycle
        i_we[0] = 1; i_waddr[0] = 40; i_wdata[0] = 32'hCCDD_0000;
        read_all(40);
        step();                       // read here must still see OLD
        clear_we();
        read_all(40); repeat(4) step();   // now sees NEW

        // ---- TEST 6: randomized stress (the comprehensive check) ----
        $display("\n=== TEST 6: randomized stress ===");
        for (int c = 0; c < 500; c++) begin
            for (int w = 0; w < NumWrite; w++) begin
                i_we[w]    = $urandom_range(0, 1);
                i_waddr[w] = $urandom_range(0, AddrRange-1);
                i_wdata[w] = $urandom;
            end
            for (int r = 0; r < NumRead; r++)
                i_raddr[r] = $urandom_range(0, AddrRange-1);
            step();
        end

        // drain the read pipeline
        clear_we();
        repeat(3) step();

        // ---- Summary ----
        $display("\n=== SUMMARY: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED - see [FAIL] lines above", fail_cnt);

        #20 $finish;
    end

endmodule
