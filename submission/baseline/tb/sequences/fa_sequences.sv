// ============================================================
// FlashAttention UVM Sequences
// ============================================================

// --- Register write sequence ---
class fa_reg_write_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_write_seq)

    bit [7:0]  addr;
    bit [31:0] data;

    function new(string name = "fa_reg_write_seq");
        super.new(name);
    endfunction

    task body();
        axi4_lite_txn txn;
        txn = axi4_lite_txn::type_id::create("txn");
        start_item(txn);
        txn.addr     = addr;
        txn.data     = data;
        txn.is_write = 1;
        finish_item(txn);
    endtask
endclass

// --- Register read sequence ---
class fa_reg_read_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_read_seq)

    bit [7:0]  addr;
    bit [31:0] rdata;

    function new(string name = "fa_reg_read_seq");
        super.new(name);
    endfunction

    task body();
        axi4_lite_txn txn;
        txn = axi4_lite_txn::type_id::create("txn");
        start_item(txn);
        txn.addr     = addr;
        txn.is_write = 0;
        finish_item(txn);
        rdata = txn.rdata;
    endtask
endclass

// --- Full configuration + start sequence ---
class fa_config_and_start_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_config_and_start_seq)

    bit [63:0] q_base, k_base, v_base, o_base;
    bit [31:0] stride_bytes;
    bit [15:0] neg_large;
    bit [15:0] scale;
    bit        causal_en;

    function new(string name = "fa_config_and_start_seq");
        super.new(name);
        stride_bytes = 32'd128;
        neg_large    = 16'h8000;
        scale        = 16'h0020;
    endfunction

    task body();
        fa_reg_write_seq wr;

        // Write base addresses
        write_reg(8'h14, q_base[31:0]);   // Q_BASE_L
        write_reg(8'h18, q_base[63:32]);  // Q_BASE_H
        write_reg(8'h1C, k_base[31:0]);   // K_BASE_L
        write_reg(8'h20, k_base[63:32]);  // K_BASE_H
        write_reg(8'h24, v_base[31:0]);   // V_BASE_L
        write_reg(8'h28, v_base[63:32]);  // V_BASE_H
        write_reg(8'h2C, o_base[31:0]);   // O_BASE_L
        write_reg(8'h30, o_base[63:32]);  // O_BASE_H

        // Write parameters
        write_reg(8'h34, stride_bytes);
        write_reg(8'h38, {16'h0, neg_large});
        write_reg(8'h3C, {16'h0, scale});

        // CFG: causal enable
        write_reg(8'h08, {31'd0, causal_en});

        // CTRL: START
        write_reg(8'h00, 32'h0000_0001);
    endtask

    task write_reg(bit [7:0] addr, bit [31:0] data);
        fa_reg_write_seq wr;
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = addr;
        wr.data = data;
        wr.start(m_sequencer);
    endtask
endclass

// --- Poll STATUS.DONE sequence ---
class fa_poll_done_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_poll_done_seq)

    int timeout_cycles = 500000;
    bit done;
    bit [31:0] cycles;

    function new(string name = "fa_poll_done_seq");
        super.new(name);
    endfunction

    task body();
        fa_reg_read_seq rd;
        int cnt = 0;
        done = 0;

        while (!done && cnt < timeout_cycles) begin
            rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = 8'h04;  // STATUS
            rd.start(m_sequencer);
            if (rd.rdata[1]) begin  // DONE bit
                done = 1;
                // Read cycle count
                rd = fa_reg_read_seq::type_id::create("rd_cyc");
                rd.addr = 8'h40;
                rd.start(m_sequencer);
                cycles = rd.rdata;
            end
            cnt++;
        end

        if (!done)
            `uvm_error("POLL", $sformatf("Timeout after %0d polls", timeout_cycles))
        else
            `uvm_info("POLL", $sformatf("Done! Execution took %0d cycles", cycles), UVM_LOW)
    endtask
endclass
