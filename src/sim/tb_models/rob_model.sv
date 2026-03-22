class ReorderBuffer#(parameter type DATA_T = decode_package::rv32_data_t);

    typedef struct {
        DATA_T RdValue;
        bit [4:0] RdAddr;
        DATA_T Pc;
        bit RdReady;
        bit Store;
        bit Branch;
        bit RegWrite;
    } rob_data_t;

    parameter int ROBTAG_WIDTH = $clog2(ROB_DEPTH);
    protected rob_data_t rob_fifo [];
    protected bit [ROBTAG_WIDTH-1:0] wr_ptr = '0;
    protected bit [ROBTAG_WIDTH-1:0] rd_ptr = '0;
    protected bit is_full = '0;

    function new();
        this.rob_fifo = new[ROB_DEPTH];
        this.wr_ptr = '0;
        this.rd_ptr = '0;
        this.is_full = '0;
    endfunction

    function automatic bit isFull();
        return this.is_full;
    endfunction

    function automatic bit canCommit();
        return (this.rob_fifo[this.rd_ptr].RegWrite && this.rob_fifo[this.rd_ptr].RdReady) || this.rob_fifo[this.rd_ptr].Store || this.rob_fifo[this.rd_ptr].Branch;
    endfunction

    function bit [ROBTAG_WIDTH-1:0] getNewTag();
        return this.wr_ptr;
    endfunction

    function bit [ROBTAG_WIDTH-1:0] allocate(DATA_T pc, bit [4:0] rd, bit store, bit branch, bit reg_write);

        rob_data_t row = '{
            Pc: pc,
            RdAddr: rd,
            RdValue: '0,
            RdReady: '0,
            Store: store,
            Branch: branch,
            RegWrite: reg_write
        };

        this.rob_fifo[this.wr_ptr] = row;
        this.wr_ptr++;

        if(this.is_full == '0 && this.wr_ptr == this.rd_ptr)
            this.is_full = '1;

        return this.wr_ptr - 1;
    endfunction


    function automatic void writeResult(DATA_T rd_value, bit [ROBTAG_WIDTH-1:0] rd_robtag);
        this.rob_fifo[rd_robtag].RdValue = rd_value;
        this.rob_fifo[rd_robtag].RdReady = 1'b1;
    endfunction

    function automatic bit isResultReady(bit [ROBTAG_WIDTH-1:0] rd_robtag);
        return this.rob_fifo[rd_robtag].RdReady;
    endfunction

    function automatic DATA_T readResult(bit [ROBTAG_WIDTH-1:0] rd_robtag);
        return this.rob_fifo[rd_robtag].RdValue;
    endfunction

    task automatic commit(output DATA_T o_rd_value, output bit [4:0] o_rd_addr, output bit o_reg_write, output bit o_is_store, output bit [ROBTAG_WIDTH-1:0] o_robtag);
        if(this.canCommit()) begin
            rob_data_t top_row = this.rob_fifo[this.rd_ptr];
            o_rd_value = top_row.RdValue;
            o_rd_addr = top_row.RdAddr;
            o_reg_write = top_row.RegWrite;
            o_is_store = top_row.Store;
            o_robtag = this.rd_ptr;
            this.rd_ptr++;
        end
        else begin
            o_rd_value = '0;
            o_rd_addr = '0;
            o_reg_write = '0;
            o_is_store = '0;
            o_robtag = this.rd_ptr;
        end
    endtask

    function automatic void branchMispredicted(bit [ROBTAG_WIDTH-1:0] robtag);
        for(bit [ROBTAG_WIDTH-1:0] i = robtag+1; i <= this.wr_ptr; i++) begin
            this.rob_fifo[i] = '{default: '0};
        end
        this.wr_ptr = robtag;
    endfunction

    function automatic bit storeCommitReady();
        return this.rob_fifo[this.rd_ptr].Store;
    endfunction

    function automatic bit[ROBTAG_WIDTH-1:0] topCommitTag();
        return this.this.rd_ptr;
    endfunction
endclass