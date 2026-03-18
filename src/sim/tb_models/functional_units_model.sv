`include "decode.svh"
import decode_package::*;

class FunctionalUnit#(
    parameter type DATA_T = bit [31:0],
    parameter int LATENCY = 1
);

    protected functional_unit_t fu_type;
    protected DATA_T dcache [];
    localparam int ROBTAG_WIDTH = $clog2(ROB_DEPTH);

    function new(functional_unit_t fu_type = INT_ALU_UNIT);
        this.fu_type = fu_type;
        if (fu_type == LOAD_STORE_UNIT)
            this.dcache = new[1024];
    endfunction

    //used for a load/store functional unit type
    function automatic void setCacheDepth(int dcache_depth = 1024);
        this.dcache = new[dcache_depth]; //needed for load/store units
    endfunction

    //publically accesible task that should be called by the instances of this class
    //defined as task as we have multiple outputs
    task static execute(
        input fu_op_t i_fu_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input DATA_T i_imm,
        input DATA_T i_pc,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        output DATA_T o_rd,
        output DATA_T o_pc,
        output DATA_T o_taken,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag,
        input logic i_store_valid,
        input logic i_store_robtag,
        input logic i_flush_store
    );

        unique case (this.fu_type) inside
                INT_ALU_UNIT: execute_as_alu_fu(
                                .i_alu_op(i_fu_op.alu_op),
                                .i_valid(i_valid),
                                .i_rs1(i_rs1),
                                .i_rs2(i_rs2),
                                .i_robtag(i_robtag),
                                .o_rd(o_rd),
                                .o_valid(o_valid),
                                .o_robtag(o_robtag)
                            );
                LOAD_STORE_UNIT: execute_as_load_store_fu(
                                .i_ls_op(i_fu_op.load_store_op),
                                .i_valid(i_valid),
                                .i_rs1(i_rs1),
                                .i_rs2(i_rs2),
                                .i_imm(i_imm),
                                .i_robtag(i_robtag),
                                //load specific outputs to ROB
                                .o_rd(o_rd),
                                .o_valid(o_valid),
                                .o_robtag(o_robtag),
                                //store specific inputs from ROB
                                .i_store_valid(i_store_valid),
                                .i_store_robtag(i_store_robtag),
                                .i_flush_store(i_flush_store)
                            );
                SHIFTER_UNIT:   execute_as_shifter_fu(
                                .i_shift_op(i_fu_op.shift_op),
                                .i_valid(i_valid),
                                .i_rs1(i_rs1),
                                .i_rs2(i_rs2),
                                .i_robtag(i_robtag),
                                .o_rd(o_rd),
                                .o_valid(o_valid),
                                .o_robtag(o_robtag)
                            );
                BRANCH_JUMP_UNIT: execute_as_branch_jump_fu(
                                .i_jump_op(i_fu_op.branch_jump_op),
                                .i_valid(i_valid),
                                .i_rs1(i_rs1),
                                .i_rs2(i_rs2),
                                .i_imm(i_imm),
                                .i_pc(i_pc),
                                .i_robtag(i_robtag),
                                .o_rd(o_rd),
                                .o_pc(o_pc),
                                .o_taken(o_taken),
                                .o_valid(o_valid),
                                .o_robtag(o_robtag)
                            );
                COMPARATOR_UNIT: execute_as_comaparator_fu(
                                .i_comp_op(i_fu_op.comp_op),
                                .i_valid(i_valid),
                                .i_rs1(i_rs1),
                                .i_rs2(i_rs2),
                                .i_robtag(i_robtag),
                                .o_rd(o_rd),
                                .o_valid(o_valid),
                                .o_robtag(o_robtag)
                            );
        endcase

    endtask

    //////////////////////////////////////////////////////////////////////
    //different types of task for each type of functional unit we can have
    protected task static execute_as_alu_fu(
        input alu_op_t i_alu_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        output DATA_T o_rd,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag
    );

        static DATA_T rd_queue [$:LATENCY] = '{default: '0};
        static bit valid_queue [$:LATENCY] = '{default: '0};
        static bit [ROBTAG_WIDTH-1:0] robtag_queue [$:LATENCY] = '{default: '0};
        DATA_T rd_value;

        o_rd = rd_queue.pop_front();
        o_valid = valid_queue.pop_front();
        o_robtag = robtag_queue.pop_front();

        if(i_valid) begin
            unique case(i_alu_op)
                ADD_OP: rd_value = i_rs1 + i_rs2;
                SUB_OP: rd_value = i_rs1 - i_rs2;
                AND_OP: rd_value = i_rs1 & i_rs2;
                OR_OP:  rd_value = i_rs1 | i_rs2;
                XOR_OP: rd_value = i_rs1 ^ i_rs2;
            endcase
            valid_queue.push_back('1);
            robtag_queue.push_back(i_robtag);
            rd_queue.push_back(rd_value);
        end
        else begin
            rd_queue.push_back('0);
            valid_queue.push_back('0);
            robtag_queue.push_back('0);
        end

    endtask


    protected task static execute_as_load_store_fu(
        //common inputs for load and store
        input load_store_t i_ls_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input DATA_T i_imm,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        //load specific outputs to ROB
        output DATA_T o_rd,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag,
        //store specific inputs from ROB
        input logic i_store_valid,
        input logic i_store_robtag,
        input logic i_flush_store
    );

        //common queue for both store and load to keep memory access in-order
        static DATA_T address_queue[$];
        static load_store_t op_queue[$];
        static DATA_T data_queue[$];
        static logic [ROBTAG_WIDTH-1:0] robtag_queue[$];
        static bit valid_queue[$];

        DATA_T head_address, head_data;
        load_store_t head_op;

        o_valid = '0;

        if(i_flush_store) begin //highest priority
            //delete all elements if misprediction happened
            address_queue = {};
            op_queue = {};
            data_queue = {};
            robtag_queue = {};
            valid_queue = {};
        end 
        else begin

            //in case there is a store that was commited by ROB then mark it as valid here as well
            if(i_store_valid) begin
                for(int i=0;i<address_queue.size();i++) begin
                    if(robtag_queue[i] == i_store_robtag) begin
                        valid_queue[i] = '1;
                        break;
                    end
                end
            end


            //pop instruction from queue if not empty and write or read data
            if(address_queue.size() && op_queue[0][3] == '0 && valid_queue[0] == '1) begin
                //if we have a valid load at head of queue then pop it directly
                op_queue.pop_front(); //TODO: actually interpret each kind of load
                o_valid = valid_queue.pop_front();
                o_rd = this.dcache[address_queue.pop_front()]; //load data and send it for commitment to ROB
                o_robtag = robtag_queue.pop_front();
                data_queue.pop_front();
            end
            else if(address_queue.size() && op_queue[0][3] == '1 && valid_queue[0] == '1) begin
                op_queue.pop_front(); //TODO: actually interpret each kind of store
                //nothing to do with these, just advance the queue
                valid_queue.pop_front();
                robtag_queue.pop_front();
                this.dcache[address_queue.pop_front()] = data_queue.pop_front(); //store data into memory
            end

            //push instructions to queue
            if(i_ls_op[3] == '0 && i_valid) begin //load
                address_queue.push_back(i_rs1 + i_imm);
                valid_queue.push_back('1);
                robtag_queue.push_back(i_robtag);
                data_queue.push_back('0);
                op_queue.push_back(i_ls_op);
            end
            else if(i_ls_op[3] == '1 && i_valid) begin //store
                address_queue.push_back(i_rs1 + i_imm);
                valid_queue.push_back('0); //mark as not valid until ROB flags it's safe to store
                robtag_queue.push_back(i_robtag);
                data_queue.push_back(i_rs2);
                op_queue.push_back(i_ls_op);
            end
        end
    endtask


    protected task static execute_as_branch_jump_fu(
        input branch_jump_t i_jump_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input DATA_T i_imm,
        input DATA_T i_pc,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        output DATA_T o_rd,
        output DATA_T o_pc,
        output DATA_T o_taken,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag
    );

        static DATA_T rd_queue [$:LATENCY] = '{default: '0};
        static DATA_T pc_queue [$:LATENCY] = '{default: '0};
        static bit valid_queue [$:LATENCY] = '{default: '0};
        static bit taken_queue [$:LATENCY] = '{default: '0};
        static bit [ROBTAG_WIDTH-1:0] robtag_queue [$:LATENCY] = '{default: '0};
        DATA_T rd_value;

        o_rd = rd_queue.pop_front();
        o_pc = pc_queue.pop_front();
        o_valid = valid_queue.pop_front();
        o_taken = taken_queue.pop_front();
        o_robtag = robtag_queue.pop_front();

        if(i_jump_op == JAL_OP) begin
            rd_queue.push_back(i_pc + 3'b100);
            pc_queue.push_back(i_pc + i_imm);
            taken_queue.push_back('1);
            valid_queue.push_back('1);
            robtag_queue.push_back(i_robtag);
        end
        else if(i_jump_op == JALR_OP && i_valid) begin
            DATA_T mask = '1; mask[0] = '0;
            rd_queue.push_back(i_pc + 3'b100);
            pc_queue.push_back((i_rs1 + i_imm) & mask);
            taken_queue.push_back('1);
            valid_queue.push_back('1);
            robtag_queue.push_back(i_robtag);
        end
        if(i_jump_op != JAL_OP && i_jump_op != JALR_OP && i_valid) begin
            unique case(i_jump_op)
                BNE_OP: rd_value = DATA_T'(signed'(i_rs1) != signed'(i_rs2));
                BLT_OP: rd_value = DATA_T'(signed'(i_rs1) < signed'(i_rs2));
                BGE_OP: rd_value = DATA_T'(signed'(i_rs1) >= signed'(i_rs2));
                BLTU_OP: rd_value = DATA_T'(i_rs1 < i_rs2);
                BGEU_OP: rd_value = DATA_T'(i_rs1 >= i_rs2);
                default: rd_value = DATA_T'(i_rs1 == i_rs2);
            endcase
            valid_queue.push_back('1);
            taken_queue.push_back(rd_value[0]);
            robtag_queue.push_back(i_robtag);
            rd_queue.push_back('0);
            pc_queue.push_back(i_pc + i_imm);
        end
        else begin
            rd_queue.push_back('0);
            pc_queue.push_back('0);
            taken_queue.push_back('0);
            valid_queue.push_back('0);
            robtag_queue.push_back('0);
        end

    endtask


    protected task static execute_as_shifter_fu(
        input shift_op_t i_shift_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        output DATA_T o_rd,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag
    );

        static DATA_T rd_queue [$:LATENCY] = '{default: '0};
        static bit valid_queue [$:LATENCY] = '{default: '0};
        static bit [ROBTAG_WIDTH-1:0] robtag_queue [$:LATENCY] = '{default: '0};
        DATA_T rd_value;

        o_rd = rd_queue.pop_front();
        o_valid = valid_queue.pop_front();
        o_robtag = robtag_queue.pop_front();

        if(i_valid) begin
            automatic int W = $clog2($bits(i_rs1));
            unique case(i_shift_op)
                SRL_OP:  rd_value = i_rs1 >> i_rs2;
                SLL_OP:  rd_value = i_rs1 << i_rs2;
                SRA_OP:  rd_value = signed'(i_rs1) >> i_rs2;
                ROTL_OP: rd_value = {i_rs1 << i_rs2[W-1:0], i_rs1[$bits(i_rs1) -: i_rs2[W-1:0]]};
                ROTR_OP: rd_value = {i_rs1[0 +: i_rs2[W-1:0]], i_rs1 >> i_rs2[W-1:0]};
            endcase
            valid_queue.push_back('1);
            robtag_queue.push_back(i_robtag);
            rd_queue.push_back(rd_value);
        end
        else begin
            rd_queue.push_back('0);
            valid_queue.push_back('0);
            robtag_queue.push_back('0);
        end

    endtask

    protected task static execute_as_comaparator_fu(
        input comp_op_t i_comp_op,
        input logic  i_valid,
        input DATA_T i_rs1,
        input DATA_T i_rs2,
        input logic [ROBTAG_WIDTH-1:0] i_robtag,
        output DATA_T o_rd,
        output logic  o_valid,
        output logic [ROBTAG_WIDTH-1:0] o_robtag
    );

        static DATA_T rd_queue [$:LATENCY] = '{default: '0};
        static bit valid_queue [$:LATENCY] = '{default: '0};
        static bit [ROBTAG_WIDTH-1:0] robtag_queue [$:LATENCY] = '{default: '0};
        DATA_T rd_value;

        o_rd = rd_queue.pop_front();
        o_valid = valid_queue.pop_front();
        o_robtag = robtag_queue.pop_front();

        if(i_valid) begin
            unique case(i_comp_op)
                SEQ_OP:  rd_value = DATA_T'(i_rs1 == i_rs2);
                SNE_OP:  rd_value = DATA_T'(i_rs1 != i_rs2);
                SLT_OP:  rd_value = DATA_T'(signed'(i_rs1) < signed'(i_rs2));
                SGE_OP:  rd_value = DATA_T'(signed'(i_rs1) >= signed'(i_rs2));
                SLTU_OP: rd_value = DATA_T'(i_rs1 < i_rs2);
                SGEU_OP: rd_value = DATA_T'(i_rs1 >= i_rs2);
            endcase
            valid_queue.push_back('1);
            robtag_queue.push_back(i_robtag);
            rd_queue.push_back(rd_value);
        end
        else begin
            rd_queue.push_back('0);
            valid_queue.push_back('0);
            robtag_queue.push_back('0);
        end

    endtask


endclass