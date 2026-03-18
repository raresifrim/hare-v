`timescale 1ns/1ps

module reorder_buffer_tb;

    localparam int NUM_FU = 4;
    localparam type DATA_T = bit[31:0];
    localparam int TAG_WIDTH = $clog2(decode_package::ROB_DEPTH);
    localparam int CLK_PERIOD = 10;

    logic                 clk;
    logic                 rst = '0;

    //input in-order instruction comming from issue (ROB tail)
    DATA_T                i_issue_pc = '0;
    logic [4:0]           i_issue_rd = '0;
    logic                 i_issue_regwrite = '0;
    logic                 i_issue_store = '0;
    logic                 i_issue_valid = '0;

    //input results comming from functional units
    logic                 i_fu_res_valid  [NUM_FU] = '{default:'0};
    logic [TAG_WIDTH-1:0] i_fu_res_robtag [NUM_FU] = '{default:'0}; //address inside rob to store result
    DATA_T                i_fu_res_data [NUM_FU] = '{default:'0};

    //input operands addresses that each FU is waiting to be computed
    //usually all type of functional units are expecting two operands comming from registers
    logic [TAG_WIDTH-1:0] i_fu_op_robtag [NUM_FU*2] = '{default:'0};
    //output values for the requested operands
    DATA_T               o_fu_op_value [NUM_FU*2];
    logic                o_fu_op_valid [NUM_FU*2];

    //output commit values for the register file (ROB head)
    logic [4:0]          o_commit_rd;
    DATA_T               o_commit_value;
    logic                o_commit_valid;

    //output commit values for the store queue
    logic[TAG_WIDTH-1:0] o_store_robtag;
    logic                o_store_valid;
    logic                o_store_flush;

    //branch/jump misprediction identified by the ROB position
    logic [TAG_WIDTH-1:0] i_jump_robtag = '0;
    logic                 i_jump_mispredicted = '0;
    logic                 i_jump_valid = '0;

    //status signals
    //used to flag that ROB is not full and ready to accept new instructions
    logic                o_ready;


    reorder_buffer#(
        //data type and width of value fields
        .DATA_T(DATA_T),
        //how many parallel functional units are outputing results to the ROB
        .NUM_WPORTS(NUM_FU),
        .NUM_RPORTS(2*NUM_FU),
        .DEBUG (1)
    ) rob_inst(.*);

    // Clock Generation
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0,queue_tb);
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end




endmodule