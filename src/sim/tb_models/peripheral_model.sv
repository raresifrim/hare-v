`include "decode.svh"
import decode_package::*;

virtual class Peripheral #(parameter type DATA_T = decode_package::rv32_data_t);
    
    protected string name = "Generic Peripheral";
    protected DATA_T base_address;
    protected int size = 1024;
    protected int DATA_WIDTH = $bits(DATA_T);
    protected int WORD_WIDTH = (DATA_WIDTH/8); //4 or 8 words depending if RV32 or RV64
    protected int SELECT_WIDTH = $clog2(WORD_WIDTH);
    protected int WORD_SIZE = 8; //8-bit word size

    //byte-alligned memory
    protected bit [WORD_SIZE-1:0] mem_region [];
    
    typedef struct {
        DATA_T data;
        bit ack;
        bit err;
    } data_pkt;

    function new(DATA_T base_address, int size);
        this.base_address = base_address;
        this.size = size;
        this.mem_region = new[depth];
        this.name = name;
    endfunction

    function setName(string name);
        this.name = name;
    endfunction

    virtual function DATA_T getBaseAddress();
        return this.base_address;
    endfunction

    virtual function DATA_T getEndAddress();
        return this.base_address + DATA_T'(size) - 1;
    endfunction

    virtual function data_pkt read(DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);
        data_pkt pkt = '{default: '0};
        if(this.addressWithinRange(address) && !this.addressMisaligned(address, data_select)) begin
            for (int i = 0; i < this.WORD_WIDTH; i = i + 1)
                if(data_select[i])
                    pkt.data[this.WORD_SIZE*i +: this.WORD_SIZE] <= this.mem_region[address + i];
            pkt.ack = '1;
            this.onRead(pkt, address, data_select);
        end
        else pkt.err = '1;
        return pkt;
    endfunction

    virtual function data_pkt write(DATA_T address, DATA_T data, bit [this.WORD_WIDTH-1:0] data_select);
        data_pkt pkt = '{default: '0};
        if(this.addressWithinRange(address) && !this.addressMisaligned(address, data_select)) begin
            for (int i = 0; i < this.WORD_WIDTH; i = i + 1)
                if(data_select[i])
                    this.mem_region[address + i] <= data[this.WORD_SIZE*i +: this.WORD_SIZE];
            pkt.ack = '1;
            pkt.data = data;
            this.onWrite(pkt, address, data_select);
        end
        else pkt.err = '1;
        return pkt;
    endfunction

    virtual function bit addressWithinRegion(DATA_T address);
        return address >= this.base_address && address < this.base_address + this.size;
    endfunction;

    virtual function bit addressMisaligned(DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);
        for (int i = 1; i < this.WORD_WIDTH; i = i + 1)
            if(data_select[i] && address[i-1] != '0) begin
                $display("ERROR[Peripheral %s]: address %x misaligned", this.name, address);
                return 1;
            end
        return 0;
    endfunction

    pure virtual function void onWrite(ref data_pkt data, DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);

    pure virtual function void onRead(ref data_pkt data, DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);

endclass

class DCache #(parameter type DATA_T = decode_package::rv32_data_t) extends Peripheral #(DATA_T);
    protected string name = "DCACHE";
endclass

class ICache #(parameter type DATA_T = decode_package::rv32_data_t) extends Peripheral #(DATA_T);
    protected string name = "ICACHE";
endclass

class Uart #(parameter type DATA_T = decode_package::rv32_data_t) extends Peripheral #(DATA_T);
    protected string name = "UART";
    
    //currently only UART TX is supported
    virtual function onWrite(ref Peripheral::data_pkt pkt, DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);
        if(address == this.base_address + 4'h4 && data_select[0] == 1'b1) begin
            $write("%c", pkt.data[7:0]);
        end
    endfunction

endclass