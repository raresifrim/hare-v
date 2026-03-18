`timescale 1ns / 1ps

module wb_bram_tb;

    logic clk, rst;
    wishboneIf #(.DATA_T(bit[31:0])) wbIf(clk);
    logic [wbIf.DATA_WIDTH-1:0] rdata;
    logic [wbIf.DATA_WIDTH-1:0] wdata;
    logic [wbIf.ADDR_WIDTH-1:0] addr;
     
    wb_bram dut(.clk(clk), .rst(rst), .wb_cpu(wbIf.Slave));
    
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, wb_bram_tb);
        #0 clk = '0;
        forever #5 clk = ~clk;
    end
    
    initial begin
        #0 rst = '1;
        //Test some single burst writes and reads
        #10; rst = '0;
        for(int i=0;i<16;i++) begin
            addr = i * wbIf.SELECT_WIDTH;
            wdata = i+1;
            wbIf.MasterWrite(addr, wdata);
            #10;
        end
        for(int i=0;i<16;i++) begin
            addr = i * wbIf.SELECT_WIDTH;
            wbIf.MasterRead(addr,rdata);
           if(rdata != i+1) begin
                $display("ERROR reading from address %h", addr);
                $stop;
            end
            #10;
        end
        
        #10
        
        //Test some back-to-back pipelined requests
        for(int i=16;i<32;i++) begin
            addr = i * wbIf.SELECT_WIDTH;
            wdata = i+1;
            wbIf.addr = addr;
            wbIf.data_wr = wdata;
            wbIf.stb = 1'b1;
            wbIf.we = 1'b1;
            wbIf.cyc = 1'b1;
            #10;
        end
        wbIf.stb = 1'b0;
        wbIf.we = 1'b0;
        
        wait(wbIf.ack == 0);
        wbIf.cyc = 1'b0;
        
        #10;
      
        for(int i=16;i<32;i++) begin
            addr = i * wbIf.SELECT_WIDTH;
            wbIf.addr = addr;
            wbIf.stb = 1'b1;
            wbIf.cyc = 1'b1;
            #10;
        end
        wbIf.stb = 1'b0;
        
        wait(wbIf.ack == 0);
        wbIf.cyc = 1'b0;
        
        #10;
        
        $finish();
    end

endmodule
