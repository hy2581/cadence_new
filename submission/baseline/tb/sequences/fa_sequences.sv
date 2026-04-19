// ============================================================
// FlashAttention UVM Sequences — Comprehensive Suite
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
        write_reg(8'h08, {31'd0, causal_en});
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
            `uvm_info("POLL", $sformatf("Done! Execution took %0d cycles", cycles), UVM_LOW)
    endtask
endclass

// --- Random register read/write sequence ---
class fa_rand_reg_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_rand_reg_seq)
    int num_txns = 100;

    function new(string name = "fa_rand_reg_seq");
        super.new(name);
    endfunction

    task body();
        bit [7:0] rw_addrs[] = '{8'h08, 8'h14, 8'h18, 8'h1C, 8'h20,
                                  8'h24, 8'h28, 8'h2C, 8'h30, 8'h34,
                                  8'h38, 8'h3C};
        for (int i = 0; i < num_txns; i++) begin
            int idx = $urandom_range(0, rw_addrs.size()-1);
            bit do_write = $urandom_range(0, 1);
            if (do_write) begin
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                wr.addr = rw_addrs[idx];
                wr.data = $urandom();
                wr.start(m_sequencer);
            end else begin
                fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
                rd.addr = rw_addrs[idx];
                rd.start(m_sequencer);
            end
        end
    endtask
endclass

// --- Register reset value check sequence ---
class fa_reg_reset_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_reset_seq)

    function new(string name = "fa_reg_reset_seq");
        super.new(name);
    endfunction

    task body();
        fa_reg_read_seq rd;

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h00; rd.start(m_sequencer);
        check_val("CTRL", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h04; rd.start(m_sequencer);
        check_val("STATUS", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h08; rd.start(m_sequencer);
        check_val("CFG", rd.rdata, 32'h0);

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h34; rd.start(m_sequencer);
        check_val("STRIDE", rd.rdata, 32'd128);

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h40; rd.start(m_sequencer);
        check_val("CYCLES", rd.rdata, 32'h0);
    endtask

    function void check_val(string name, bit [31:0] actual, bit [31:0] expected);
        if (actual !== expected)
            `uvm_error("RESET", $sformatf("%s reset mismatch: got 0x%08h, exp 0x%08h",
                                          name, actual, expected))
        else
            `uvm_info("RESET", $sformatf("%s reset OK: 0x%08h", name, actual), UVM_MEDIUM)
    endfunction
endclass

// --- Back-to-back register access stress sequence ---
class fa_reg_stress_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_stress_seq)
    int num_rounds = 50;

    function new(string name = "fa_reg_stress_seq");
        super.new(name);
    endfunction

    task body();
        bit [7:0] addrs[] = '{8'h08, 8'h14, 8'h18, 8'h1C, 8'h20,
                              8'h24, 8'h28, 8'h2C, 8'h30, 8'h34,
                              8'h38, 8'h3C};
        for (int round = 0; round < num_rounds; round++) begin
            foreach (addrs[i]) begin
                bit [31:0] wr_val = $urandom();
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                wr.addr = addrs[i]; wr.data = wr_val;
                wr.start(m_sequencer);

                begin
                    fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
                    rd.addr = addrs[i];
                    rd.start(m_sequencer);
                    if (rd.rdata !== wr_val)
                        `uvm_error("STRESS", $sformatf("Round %0d addr 0x%02h: W=0x%08h R=0x%08h",
                                                        round, addrs[i], wr_val, rd.rdata))
                end
            end
        end
    endtask
endclass

// --- Register walking-1 / walking-0 bit test ---
class fa_reg_walk_bit_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_walk_bit_seq)

    function new(string name = "fa_reg_walk_bit_seq");
        super.new(name);
    endfunction

    task body();
        bit [7:0] addrs[] = '{8'h14, 8'h18, 8'h34, 8'h38, 8'h3C};

        foreach (addrs[a]) begin
            // Walking-1
            for (int bit_pos = 0; bit_pos < 32; bit_pos++) begin
                bit [31:0] pattern = (32'd1 << bit_pos);
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                fa_reg_read_seq  rd = fa_reg_read_seq::type_id::create("rd");
                wr.addr = addrs[a]; wr.data = pattern;
                wr.start(m_sequencer);
                rd.addr = addrs[a];
                rd.start(m_sequencer);
                if (rd.rdata !== pattern)
                    `uvm_error("WALK1", $sformatf("addr=0x%02h bit=%0d W=0x%08h R=0x%08h",
                                                   addrs[a], bit_pos, pattern, rd.rdata))
            end
            // Walking-0
            for (int bit_pos = 0; bit_pos < 32; bit_pos++) begin
                bit [31:0] pattern = ~(32'd1 << bit_pos);
                fa_reg_write_seq wr = fa_reg_write_seq::type_id::create("wr");
                fa_reg_read_seq  rd = fa_reg_read_seq::type_id::create("rd");
                wr.addr = addrs[a]; wr.data = pattern;
                wr.start(m_sequencer);
                rd.addr = addrs[a];
                rd.start(m_sequencer);
                if (rd.rdata !== pattern)
                    `uvm_error("WALK0", $sformatf("addr=0x%02h bit=%0d W=0x%08h R=0x%08h",
                                                   addrs[a], bit_pos, pattern, rd.rdata))
            end
        end
        `uvm_info("WALK", "Walking bit test complete", UVM_LOW)
    endtask
endclass

// --- Register unmapped address test ---
class fa_reg_unmapped_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_reg_unmapped_seq)

    function new(string name = "fa_reg_unmapped_seq");
        super.new(name);
    endfunction

    task body();
        bit [7:0] unmapped_addrs[] = '{8'h0C, 8'h10, 8'h44, 8'h48, 8'h4C,
                                        8'h50, 8'h60, 8'h7C, 8'hFC};
        foreach (unmapped_addrs[i]) begin
            fa_reg_read_seq rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = unmapped_addrs[i];
            rd.start(m_sequencer);
            `uvm_info("UNMAP", $sformatf("Unmapped 0x%02h => 0x%08h (expect 0 or default)",
                                          unmapped_addrs[i], rd.rdata), UVM_MEDIUM)
        end
    endtask
endclass

// --- Soft reset sequence ---
class fa_soft_reset_seq extends uvm_sequence #(axi4_lite_txn);
    `uvm_object_utils(fa_soft_reset_seq)

    function new(string name = "fa_soft_reset_seq");
        super.new(name);
    endfunction

    task body();
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;

        // Write some values
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h14; wr.data = 32'hDEAD_BEEF;
        wr.start(m_sequencer);

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h08; wr.data = 32'h1;
        wr.start(m_sequencer);

        // Issue soft reset
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h00; wr.data = 32'h2;
        wr.start(m_sequencer);

        // Verify reset took effect
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h04; rd.start(m_sequencer);
        `uvm_info("SRST", $sformatf("STATUS after soft reset: 0x%08h", rd.rdata), UVM_LOW)
    endtask
endclass
