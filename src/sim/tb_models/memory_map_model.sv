`include "decode.svh"
import decode_package::*;

import "DPI-C" function void read_elf(input string filename);
import "DPI-C" function byte get_section(output longint address, output longint len);
import "DPI-C" context function void read_section_sv(input longint address, inout byte buffer[]);

//general class to handle data memory requests either to main memory or to an I/O
class MemoryMap #(parameter type DATA_T = decode_package::rv32_data_t);
    
    local static MemoryMap memory_map_singleton;
    
    local Peripheral#(.DATA_T(DATA_T)) map [DATA_T];
    typedef Peripheral::data_pkt data_pkt;
    local int DATA_WIDTH = $bits(DATA_T);
    local int WORD_WIDTH = (DATA_WIDTH/8); 
    local int WORD_SIZE = 8;

    static function MemoryMap get(); // function to return singleton handle
        if(this.memory_map_singleton == null)
            this.memory_map_singleton = new; // create a_singleton once only
        return this.memory_map_singleton;
    endfunction

    function void addMemoryRegion(Peripheral p);
        if (type(this::DATA_T) == type(p::DATA_T))
            if(map.exists(p.getBaseAddress()) || this.findBaseAddress(p.getBaseAddress()))
                $display("ERROR[MemoryMap]: there is already a memory region mapped at address %x", p.getBaseAddress());
            else
                map[p.getBaseAddress()] = p;
        else
            $display("ERROR[MemoryMap]: could not add peripheral as DATA_T parameter of peripheral is different then the one from the MemoryMap");
    endfunction

    function int findBaseAddress (ref DATA_T address);
        bit found = 0;
        foreach(map[key]) begin
            DATA_T base_address = map[key].getBaseAddress();
            DATA_T end_address = map[key].getBaseAddress();
            if(address >= base_address && address <= end_address) begin
                found = 1;
                address = key; 
            end
        end
    endfunction

    function data_pkt read(DATA_T address, bit [this.WORD_WIDTH-1:0] data_select);
        data_pkt pkt = '{default:'0};
        DATA_T base_address = address;
        if (this.findBaseAddress(base_address)) begin
            return this.map[base_address].read(address, data_select);
        end
        else begin
            pkt.err = 1'b1;
            $display("ERROR[MemoryMap]: there is no memory region mapped for address %x", address);
        end
        return pkt;
    endfunction

    function data_pkt write(DATA_T address, DATA_T data, bit [this.WORD_WIDTH-1:0] data_select);
        data_pkt pkt = '{default:'0};
        DATA_T base_address = address;
        if (this.findBaseAddress(base_address)) begin
            return this.map[base_address].write(address, data, data_select);
        end
        else begin
            pkt.err = 1'b1;
            $display("ERROR[MemoryMap]: there is no memory region mapped for address %x", address);
        end
        return pkt;
    endfunction

    function automatic void load_elf(string binary);
        automatic logic [7:0][3:0] mem_row;
        longint address, load_address, last_load_address, len;
        byte buffer[];

        if (binary != "") begin
            $write("[Core Test]: Preloading ELF: %s", binary);

            read_elf(binary);

            last_load_address = 'hFFFFFFFF;
            // while there are more sections to process
            while (get_section(address, len)) begin
                automatic int num_words = (len+3)/4;
                $write( "[Core Test]: Loading Address: %x, Length: %x", address, len);
                buffer = new [num_words*8];
                read_section_sv(address, buffer);
                // preload memories
                // 32-bit
                for (int i = 0; i < num_words; i++) begin
                    mem_row = '0;
                    for (int j = 0; j < 4; j++) begin
                        mem_row[j] = buffer[i*4 + j];
                    end
                    load_address = (address[23:0] >> 2) + i;
                    if (load_address != last_load_address) begin
                        this.write(load_address, mem_row, 4);
                        last_load_address = load_address;
                    end else begin
                        $write( "[Debug info]: Address: %x Already Loaded! ELF file might have less than 64 bits granularity on segments.", load_address);
                    end

                end
            end
        end
    endfunction

endclass

