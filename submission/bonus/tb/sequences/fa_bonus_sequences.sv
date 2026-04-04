// ============================================================
// FlashAttention Bonus UVM Sequences
// Extended configuration + register test sequences
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

// --- Bonus register reset value check ---
class fa_bonus_reg_reset_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_reg_reset_seq)
    function new(string name = "fa_bonus_reg_reset_seq"); super.new(name); endfunction

    task body();
        fa_reg_read_seq rd;

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h00; rd.start(m_sequencer);
        chk("CTRL", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h04; rd.start(m_sequencer);
        chk("STATUS", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h08; rd.start(m_sequencer);
        chk("CFG", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h34; rd.start(m_sequencer);
        chk("STRIDE", rd.rdata, 32'd128);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h40; rd.start(m_sequencer);
        chk("CYCLES", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h0C; rd.start(m_sequencer);
        chk("SEQ_LEN", rd.rdata, 32'd256);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h10; rd.start(m_sequencer);
        chk("NUM_HEADS", rd.rdata, 32'd1);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h44; rd.start(m_sequencer);
        chk("PAD_LEN", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd"); rd.addr = 8'h50; rd.start(m_sequencer);
        chk("DATA_FMT", rd.rdata, 32'h0);
    endtask

    function void chk(string name, bit [31:0] actual, bit [31:0] expected);
        if (actual !== expected)
            `uvm_error("RESET", $sformatf("%s reset FAIL: 0x%08h exp 0x%08h", name, actual, expected))
        else
            `uvm_info("RESET", $sformatf("%s reset OK: 0x%08h", name, actual), UVM_MEDIUM)
    endfunction
endclass

// --- Bonus register stress ---
class fa_bonus_reg_stress_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_reg_stress_seq)
    int num_rounds = 50;
    function new(string name = "fa_bonus_reg_stress_seq"); super.new(name); endfunction

    task body();
        bit [7:0] addrs[] = '{8'h08, 8'h0C, 8'h10, 8'h14, 8'h18,
                              8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C,
                              8'h30, 8'h34, 8'h38, 8'h3C,
                              8'h44, 8'h48, 8'h50, 8'h54};
        for (int r = 0; r < num_rounds; r++) begin
            foreach (addrs[i]) begin
                bit [31:0] wv = $urandom();
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                wr.addr = addrs[i]; wr.data = wv;
                wr.start(m_sequencer);
                begin
                    fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
                    rd.addr = addrs[i]; rd.start(m_sequencer);
                    if (rd.rdata !== wv)
                        `uvm_error("STRESS", $sformatf("R%0d 0x%02h W=0x%08h R=0x%08h",
                                                        r, addrs[i], wv, rd.rdata))
                end
            end
        end
    endtask
endclass

// --- Bonus walking-1/0 bit test ---
class fa_bonus_reg_walk_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_reg_walk_seq)
    function new(string name = "fa_bonus_reg_walk_seq"); super.new(name); endfunction

    task body();
        bit [7:0] addrs[] = '{8'h14, 8'h18, 8'h34, 8'h38, 8'h3C,
                              8'h0C, 8'h44, 8'h50, 8'h54};
        foreach (addrs[a]) begin
            for (int b = 0; b < 32; b++) begin
                bit [31:0] pat = (32'd1 << b);
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                fa_reg_read_seq  rd = fa_reg_read_seq::type_id::create("rd");
                wr.addr = addrs[a]; wr.data = pat; wr.start(m_sequencer);
                rd.addr = addrs[a]; rd.start(m_sequencer);
                if (rd.rdata !== pat)
                    `uvm_error("WALK1", $sformatf("0x%02h bit%0d W=0x%08h R=0x%08h",
                                                   addrs[a], b, pat, rd.rdata))
            end
            for (int b = 0; b < 32; b++) begin
                bit [31:0] pat = ~(32'd1 << b);
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                fa_reg_read_seq  rd = fa_reg_read_seq::type_id::create("rd");
                wr.addr = addrs[a]; wr.data = pat; wr.start(m_sequencer);
                rd.addr = addrs[a]; rd.start(m_sequencer);
                if (rd.rdata !== pat)
                    `uvm_error("WALK0", $sformatf("0x%02h bit%0d W=0x%08h R=0x%08h",
                                                   addrs[a], b, pat, rd.rdata))
            end
        end
        `uvm_info("WALK", "Bonus walking bit test complete", UVM_LOW)
    endtask
endclass

// --- Bonus unmapped address test ---
class fa_bonus_reg_unmapped_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_reg_unmapped_seq)
    function new(string name = "fa_bonus_reg_unmapped_seq"); super.new(name); endfunction

    task body();
        bit [7:0] unmapped[] = '{8'h58, 8'h5C, 8'h60, 8'h70,
                                  8'h80, 8'h90, 8'hA0, 8'hF0, 8'hFC};
        foreach (unmapped[i]) begin
            fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = unmapped[i]; rd.start(m_sequencer);
            `uvm_info("UNMAP", $sformatf("0x%02h => 0x%08h", unmapped[i], rd.rdata), UVM_MEDIUM)
        end
    endtask
endclass

// --- Bonus soft reset ---
class fa_bonus_soft_reset_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_soft_reset_seq)
    function new(string name = "fa_bonus_soft_reset_seq"); super.new(name); endfunction

    task body();
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h14; wr.data = 32'hDEAD_BEEF; wr.start(m_sequencer);

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h08; wr.data = 32'h1; wr.start(m_sequencer);

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h00; wr.data = 32'h2; wr.start(m_sequencer);

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h04; rd.start(m_sequencer);
        `uvm_info("SRST", $sformatf("STATUS after soft reset: 0x%08h", rd.rdata), UVM_LOW)
    endtask
endclass

// --- Bonus random register access ---
class fa_bonus_rand_reg_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_bonus_rand_reg_seq)
    int num_txns = 100;
    function new(string name = "fa_bonus_rand_reg_seq"); super.new(name); endfunction

    task body();
        bit [7:0] rw_addrs[] = '{8'h08, 8'h0C, 8'h10, 8'h14, 8'h18,
                                  8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C,
                                  8'h30, 8'h34, 8'h38, 8'h3C,
                                  8'h44, 8'h48, 8'h50, 8'h54};
        for (int i = 0; i < num_txns; i++) begin
            int idx = $urandom_range(0, rw_addrs.size()-1);
            if ($urandom_range(0,1)) begin
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                wr.addr = rw_addrs[idx]; wr.data = $urandom();
                wr.start(m_sequencer);
            end else begin
                fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
                rd.addr = rw_addrs[idx]; rd.start(m_sequencer);
            end
        end
    endtask
endclass
