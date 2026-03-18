module reorder_buffer#(
    //data type and width of value fields
    parameter type DATA_T = bit[31:0],
    //read and write ports supporting all functional units that are outputing results to the ROB
    parameter int NUM_WPORTS = 4,
    parameter int NUM_RPORTS = 8,
    parameter int DEBUG = 1,
    //depth of ROB, defined in the decode package
    //local to the module, can be modified only through the decode package
    localparam int DEPTH = ROB_DEPTH,
    localparam int TAG_WIDTH = $clog2(ROB_DEPTH)
)(
    input logic                 clk,
    input logic                 rst,

    //input in-order instruction comming from issue (ROB tail)
    input DATA_T                i_issue_pc,
    input logic [4:0]           i_issue_rd,
    input logic                 i_issue_regwrite,
    input logic                 i_issue_store,
    input logic                 i_issue_valid,

    //input results comming from functional units
    input logic                 i_fu_res_valid  [NUM_WPORTS],
    input logic [TAG_WIDTH-1:0] i_fu_res_robtag [NUM_WPORTS], //address inside rob to store result
    input DATA_T                i_fu_res_data [NUM_WPORTS],

    //input operands addresses that each FU is waiting to be computed
    //usually all type of functional units are expecting two operands comming from registers
    input logic [TAG_WIDTH-1:0] i_fu_op_robtag [NUM_RPORTS],
    //output values for the requested operands
    output DATA_T               o_fu_op_value [NUM_RPORTS],
    output logic                o_fu_op_valid [NUM_RPORTS],

    //output commit values for the register file (ROB head)
    output logic [4:0]          o_commit_rd,
    output DATA_T               o_commit_value,
    output logic                o_commit_valid,

    //output commit values for the store queue
    output logic[TAG_WIDTH-1:0] o_store_robtag,
    output logic                o_store_valid,
    output logic                o_store_flush,

    //branch/jump misprediction identified by the ROB position
    input logic [TAG_WIDTH-1:0] i_jump_robtag,
    input logic                 i_jump_valid,
    input logic                 i_jump_mispredicted,

    //status signals
    //used to flag that ROB is not full and ready to accept new instructions
    output logic                o_ready
);

    localparam int FIFO_DWIDTH = $bits(i_issue_pc) + $bits(i_issue_rd) + 2;

    ////////////////////////////////ROB PORTS <=> FIFO PORTS MAPPING////////////////////////////////

    logic [$clog2(DEPTH)-1:0] wptr;
    logic [$clog2(DEPTH)-1:0] rptr;

    logic w_almost_full, w_almost_empty;
    logic r_full, r_empty;

    (*ram_style="block"*) logic [FIFO_DWIDTH-1:0] fifo [DEPTH];

    logic [FIFO_DWIDTH-1:0] tail_data, head_data;
    assign tail_data = {i_issue_pc, i_issue_store, i_issue_regwrite, i_issue_rd};
    logic fifo_read, fifo_write;
    assign fifo_write = i_issue_valid;

    assign o_ready = ~r_full;
    assign o_commit_valid = rob_ready_flags[rptr] & head_data[5];
    assign o_commit_rd = head_data[4:0];

    assign o_store_valid = rob_ready_flags[rptr] & head_data[6];
    assign o_store_robtag = rptr;

    /////////////////////////////////ROB READY FLAGS FOR EACH ENTRY/////////////////////////////////

    logic [DEPTH-1:0] rob_ready_flags;
    assign fifo_read = rob_ready_flags[rptr];

    //////////////////////////////////////LOGIC FOR FIFO - START/////////////////////////////////////

    always_ff@(posedge clk) begin
        if(rst)
            rob_ready_flags <= '0;
        else begin
            if(i_jump_valid && ~i_jump_mispredicted)
                rob_ready_flags[i_jump_robtag] <= 1'b1;
            for (int i=0;i<NUM_WPORTS;i++) begin
                if (i_fu_res_valid[i] == 1'b1)
                    rob_ready_flags[i] <= 1'b1;
            end
            if (fifo_write)
                rob_ready_flags[wptr] <= 1'b0;
        end
    end

    always_comb begin
        for (int i=0;i<NUM_RPORTS;i++)
           o_fu_op_valid[i] = rob_ready_flags[i_fu_op_robtag[i]];
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            wptr <= 0;
            r_full <= '0;
            o_store_flush <= '0;
        end
        else begin
            o_store_flush <= '0;
            if (i_jump_valid && i_jump_mispredicted) begin
                wptr <= i_jump_robtag;
                r_full <= '0;
                o_store_flush <= '1;
            end
            else if (fifo_write & !r_full) begin
                fifo[wptr] <= tail_data;
                wptr <= wptr + 1'b1;
                if(w_almost_full)
                    r_full <= '1;
            end
            else if(r_full && fifo_read)
                r_full <= '0;
        end
    end

    initial begin
        if (DEBUG)
            $monitor("[%0t] [ROB] rob_issue=%0b rob_input=0x%0h rob_commit=%0b rob_head=0x%0h empty=%0b full=%0b", $time, fifo_write, tail_data, fifo_read, head_data, r_empty, r_full);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rptr <= 0;
            head_data <= '0;
            r_empty <= '1;
        end
        else begin
            if (fifo_read & !r_empty) begin
                head_data <= fifo[rptr];
                rptr <= rptr + 1'b1;
                if(w_almost_empty)
                    r_empty <= '1;
            end
            else if(r_empty && fifo_write)
                r_empty <= '0;
        end
    end

    assign w_almost_full = wptr + 1'b1 == rptr;
    assign w_almost_empty = rptr + 1'b1 == wptr;

    //////////////////////////////////////LOGIC FOR FIFO - END/////////////////////////////////////

    /////////////////////////////////MULTI-PORT MEM HOLDING RESUTS/////////////////////////////////

    mwnr_multiport_mem#(
        .NUM_WRITE(NUM_WPORTS),
        .NUM_READ(NUM_RPORTS + 1),
        .DATA_T(DATA_T),
        .ADDR_WIDTH(TAG_WIDTH),
        .RAMSTYLE("block")
    ) multiport_mem_inst(
        .clk(clk),
        .rst(rst),
        .ce(1'b1),
        .i_we(i_fu_res_valid),
        .i_waddr(i_fu_res_robtag),
        .i_raddr({i_fu_op_robtag, rptr}),
        .i_wdata(i_fu_res_data),
        .o_rdata({o_fu_op_value, o_commit_value})
    );

endmodule