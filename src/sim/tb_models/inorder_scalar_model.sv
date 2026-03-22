`include "decode.svh"
import decode_package::*;

class ScalarInorderModel#(
    parameter type DATA_T = decode_package::rv32_data_t,
    parameter type DECODER_T = decode_package::rv32iDecoder
);

    //Main components of this model: frontend, rob and execution units
    protected RVFrontend #(.DATA_T(DATA_T), .DECODER_T(DECODER_T)) frontend;
    protected FunctionalUnit #(.DATA_T(DATA_T), .LATENCY(3)) functional_units [functional_unit_t]; //all units have the same latency
    localparam int ROBTAG_WIDTH = $clog2(ROB_DEPTH);
    protected ReorderBuffer #(.DATA_T(DATA_T)) rob;
    //memory_map is a singleton available in multiple places, but the memory map should only be handled in here
    protected MemoryMap #(.DATA_T(DATA_T)) memory_map;

    typedef struct {
        DATA_T reg_data;
        DATA_T pc;
        bit pc_taken;
        bit [ROBTAG_WIDTH-1:0] robtag;
    } fu_result_t;

    protected fu_result_t rob_queue [$];

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

    protected function automatic void setPC(DATA_T start_address);
        this.frontend.setPC(start_address);
    endfunction

    protected function automatic void loadELF(string binary);
        this.memory_map.loadELF(binary);
    endfunction

    function automatic void init(DATA_T start_address, string binary);
        this.setPC(start_address);
        this.loadELF(binary);
    endfunction

    function automatic void addPeripheral(Peripheral p);
        this.memory_map.addMemoryRegion(p);
    endfunction

    task run(ref logic clk);
        //start all stages in parallel
        fork
            fetchAndDecode(clk);
            renameAndDispatch(clk);
            execute(clk);
            writeBack(clk);
            commit(clk);
        join_none
    endtask

   protected task fetchAndDecode (ref logic clk);
        forever begin
            @(posedge clk);
            this.frontend.stallingFetchAndDecode();
        end
    endtask

    protected task renameAndDispatch (ref logic clk);
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


    protected task execute(ref logic clk);
        forever begin
            @(posedge clk);
            foreach(this.functional_units[fu_type]) begin
                automatic RVFrontend::fu_packet_t pkt = this.frontend.readFuPacket(fu_type, 1'b1);
                automatic bit pkt_valid = 1, result_valid = 0;
                automatic fu_result_t result;

                //check if RS1 is ready
                if (pkt.ControlData.FuSrc1 == REG)
                    if (!pkt.Rs1Ready)
                        if (this.rob.isResultReady(pkt.Rs1Tag))
                            pkt.Rs1Data = this.rob.readResult(pkt.Rs1Tag);
                        else
                            pkt_valid = 0;

                //check if RS2 is ready
                if(pkt_valid && pkt.ControlData.FuSrc2 == REG)
                    if(!pkt.Rs1Ready)
                        if(this.rob.isResultReady(pkt.Rs2Tag))
                            pkt.Rs2Data = this.rob.readResult(pkt.Rs2Tag);
                        else
                            pkt_valid = 0;

                this.functional_units[fu_type].execute(
                    .i_fu_op(pkt.OpType),
                    .i_valid(pkt_valid),
                    .i_rs1(pkt.Rs1Data),
                    .i_rs2(pkt.Rs2Data),
                    .i_imm(pkt.Imm),
                    .i_pc(pkt.Pc),
                    .i_robtag(pkt.RdTag),
                    .o_rd(result.reg_data),
                    .o_pc(result.pc),
                    .o_taken(result.pc_taken),
                    .o_valid(result_valid),
                    .o_robtag(result.robtag),
                    .i_store_valid('0), //we perform this in the commit stage
                    .i_store_robtag('0), //we perform this in the commit stage
                    .i_flush_store('0) // TODO: modify when branch prediction is added
                ); 

                this.rob_queue.push_back(result);
            end
        end
    endtask


    protected task writeBack (ref logic clk);
        forever begin
            @(posedge clk);
            if (this.rob_queue.size()) begin
                fu_result_t result = this.rob_queue.pop_front();
                this.rob.writeResult(result.reg_data, result.robtag);
            end
        end
    endtask

    protected task commit (ref logic clk);
        forever begin
            @(posedge clk);
            if (this.rob.canCommit()) begin
                automatic DATA_T rd_value;
                automatic bit [4:0] rd_addr;
                automatic bit reg_write;
                automatic bit is_store;
                automatic bit [ROBTAG_WIDTH-1:0] robtag;
                this.rob.commit(.o_rd_value(rd_value), .o_rd_addr(rd_addr), .o_reg_write(reg_write), .o_is_store(is_store), .o_robtag(robtag));

                if (reg_write) begin
                    this.frontend.writeRegister(.i_rd_addr(rd_addr), .i_rd_data(rd_value), .i_rd_tag(robtag));
                end
                else if (is_store) begin
                    this.functional_units[LOAD_STORE_UNIT].execute(
                        .i_fu_op('{default:'0}),
                        .i_valid('0),
                        .i_rs1('0),
                        .i_rs2('0),
                        .i_imm('0),
                        .i_pc('0),
                        .i_robtag('0),
                        .o_rd('0),
                        .o_pc('0),
                        .o_taken(),
                        .o_valid(),
                        .o_robtag(),
                        .i_store_valid('1), //we perform this in the commit stage
                        .i_store_robtag(robtag), //we perform this in the commit stage
                        .i_flush_store('0) // TODO: modify when branch prediction is added
                    );
                end

            end
        end
    endtask

endclass

module scalarinordermodel_tb();

    logic clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars();
        forever #5 clk = ~clk;
    end

    initial begin
        //create and initialize model core        
        ScalarInorderModel #(.DATA_T(bit[31:0]), .DECODER_T(decode_package::rv32iDecoder)) sim;
        sim = new();
        sim.init(32'h8000_0000, "binary");

        //start the core
        sim.run(clk);
        
        #1000 $finish;
    end

endmodule