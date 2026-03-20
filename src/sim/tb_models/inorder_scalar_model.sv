`include "decode.svh"
import decode_package::*;

class ScalarInorderModel#(
    parameter type DATA_T = decode_package::rv32_data_t,
    parameter type DECODER_T = decode_package::rv32iDecoder
);

    //Main components of this model: frontend, rob and execution units
    protected RVFrontend #(.DATA_T(DATA_T), .DECODER_T(DECODER_T)) frontend;
    protected FunctionalUnit #(.DATA_T(DATA_T), .LATENCY(3)) functional_units [functional_unit_t]; //all units have the same latency
    parameter int ROBTAG_WIDTH = $clog2(ROB_DEPTH);
    protected ReorderBuffer #(.DATA_T(DATA_T)) rob;
    //memory_map is a singleton available in multiple places, but the memory map should only be handled in here
    protected MemoryMap #(.DATA_T(DATA_T)) memory_map;

    function new();

        this.frontend = new();
        this.rob = new();
        this.memory_map = MemoryMap::get();

        //initialize one funtional unit of each type
        this.functional_units[INT_ALU_UNIT] = new(.fu_type(INT_ALU_UNIT));
        this.functional_units[BRANCH_JUMP_UNIT] = new(.fu_type(BRANCH_JUMP_UNIT));
        this.functional_units[LOAD_STORE_UNIT] = new(.fu_type(LOAD_STORE_UNIT));
        this.functional_units[SHIFTER_UNIT] = new(.fu_type(SHIFTER_UNIT));
        this.functional_units[COMPARATOR_UNIT] = new(.fu_type(COMPARATOR_UNIT));

    endfunction

    function automatic void setPC(DATA_T start_address);
        this.frontend.setPC(start_address);
    endfunction

    function automatic void load_elf(string binary);
        this.memory_map.load_elf(binary);
    endfunction

    task fetchAndDecode (ref logic clk);
        forever begin
            @(posedge clk);
            this.frontend.stallingFetchAndDecode();
        end
    endtask

    task renameAndDispatch (ref logic clk);
        forever begin
            @(posedge clk);
            if(!this.frontend.instrQueueEmpty()) begin
                automatic DECODER_T::decoded_instruction_t decoded_instr;
                automatic bit [ROBTAG_WIDTH-1:0] rd_robtag;
                decoded_instr = this.frontend.getNextInstruction(); //read next instruction to generate tag in ROB;
                rd_robtag = this.rob.allocate(decoded_instr.Pc, decoded_instr.Rd, decoded_instr.Store, decoded_instr.Branch, decoded_instr.RegWrite);
                this.frontend.inorderDispatch(rd_robtag);
            end
        end
    endtask


    task execute(ref logic clk);
        forever begin
            @(posedge clk);
            
        end
    endtask
endclass

module scalarinordermodel_tb();


endmodule