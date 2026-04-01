// ============================================================
// FlashAttention Bonus UVM Sequences
// Extended configuration for all 9 bonus features
// ============================================================

class fa_bonus_config_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_config_seq)

    bit [63:0] q_base, k_base, v_base, o_base;
    bit [31:0] stride_bytes;
    bit [15:0] neg_large, scale;
    bit        causal_en, padding_en, dropout_en, stream_mode;
    bit [15:0] seq_len_val;
    bit [7:0]  num_heads_val;
    bit [15:0] pad_len_val;
    bit [7:0]  drop_prob_val;
    bit [31:0] dropout_seed_val;
    bit [2:0]  data_fmt_val;
    bit [31:0] head_stride_val;
    bit        task_queue_en;

    function new(string name = "fa_bonus_config_seq");
        super.new(name);
        stride_bytes    = 32'd128;
        neg_large       = 16'h8000;
        scale           = 16'h0020;
        seq_len_val     = 16'd256;
        num_heads_val   = 8'd1;
        pad_len_val     = 16'd0;
        drop_prob_val   = 8'd0;
        dropout_seed_val = 32'hDEAD_BEEF;
        data_fmt_val    = 3'd0;
        head_stride_val = 32'd0;
    endfunction

    task body();
        write_reg(8'h0C, {16'd0, seq_len_val});
        write_reg(8'h10, {24'd0, num_heads_val});
        write_reg(8'h14, q_base[31:0]);
        write_reg(8'h18, q_base[63:32]);
        write_reg(8'h1C, k_base[31:0]);
        write_reg(8'h20, k_base[63:32]);
        write_reg(8'h24, v_base[31:0]);
        write_reg(8'h28, v_base[63:32]);
        write_reg(8'h2C, o_base[31:0]);
        write_reg(8'h30, o_base[63:32]);
        write_reg(8'h34, stride_bytes);
        write_reg(8'h38, {16'h0, neg_large});
        write_reg(8'h3C, {16'h0, scale});
        write_reg(8'h44, {16'd0, pad_len_val});
        write_reg(8'h48, {dropout_seed_val[31:8], drop_prob_val});
        write_reg(8'h50, {29'd0, data_fmt_val});
        write_reg(8'h54, head_stride_val);
        write_reg(8'h4C, {31'd0, task_queue_en});
        write_reg(8'h08, {28'd0, stream_mode, dropout_en, padding_en, causal_en});
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

class fa_bonus_poll_done_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_poll_done_seq)

    int timeout_cycles = 500000;
    bit done;
    bit [31:0] cycles;

    function new(string name = "fa_bonus_poll_done_seq");
        super.new(name);
    endfunction

    task body();
        fa_reg_read_seq rd;
        int cnt = 0;
        done = 0;
        while (!done && cnt < timeout_cycles) begin
            rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = 8'h04;
            rd.start(m_sequencer);
            if (rd.rdata[1]) begin
                done = 1;
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
            `uvm_info("POLL", $sformatf("Done! %0d cycles", cycles), UVM_LOW)
    endtask
endclass
