// ============================================================
// FlashAttention Bonus UVM Tests
// One test per bonus feature + combined test
// ============================================================

// --- Base test with common helpers ---
class fa_bonus_base_test extends uvm_test;
    `uvm_component_utils(fa_bonus_base_test)

    fa_bonus_env env;

    bit [63:0] Q_BASE = 64'h0001_0000;
    bit [63:0] K_BASE = 64'h0002_0000;
    bit [63:0] V_BASE = 64'h0003_0000;
    bit [63:0] O_BASE = 64'h0004_0000;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fa_bonus_env::type_id::create("env", this);
    endfunction

    function void preload_random_data();
        shortint q[][], k[][], v[][];
        q = new[256]; k = new[256]; v = new[256];
        for (int i = 0; i < 256; i++) begin
            q[i] = new[64]; k[i] = new[64]; v[i] = new[64];
            for (int j = 0; j < 64; j++) begin
                q[i][j] = $random % 64;
                k[i][j] = $random % 64;
                v[i][j] = $random % 64;
            end
        end
        env.mem_agent.preload_matrix(Q_BASE, 256, 64, q);
        env.mem_agent.preload_matrix(K_BASE, 256, 64, k);
        env.mem_agent.preload_matrix(V_BASE, 256, 64, v);
        env.scoreboard.q_data = q;
        env.scoreboard.k_data = k;
        env.scoreboard.v_data = v;
    endfunction

    task run_attention(fa_bonus_config_seq cfg);
        fa_bonus_poll_done_seq poll;
        `uvm_info("TEST", "Starting config sequence...", UVM_LOW)
        cfg.start(env.axil_agent.sqr);
        `uvm_info("TEST", "Config done, starting poll...", UVM_LOW)
        poll = fa_bonus_poll_done_seq::type_id::create("poll");
        poll.start(env.axil_agent.sqr);
        `uvm_info("TEST", "Poll done!", UVM_LOW)
    endtask

    task readback_and_check(string name);
        shortint o[][];
        env.mem_agent.readback_matrix(O_BASE, 256, 64, o);
        env.scoreboard.dut_o = o;
        env.scoreboard.compute_golden();
        env.scoreboard.check_result(name);
    endtask
endclass

// --- Test 1: Baseline Causal ---
class fa_bonus_causal_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_causal_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;
        fa_bonus_config_seq cfg;
        fa_bonus_poll_done_seq poll;

        phase.raise_objection(this);
        // Wait for reset to complete
        #100;
        `uvm_info("TEST", "Preloading data...", UVM_LOW)
        preload_random_data();

        `uvm_info("TEST", "Writing first register (SEQ_LEN)...", UVM_LOW)
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h0C;
        wr.data = 32'd256;
        wr.start(env.axil_agent.sqr);
        `uvm_info("TEST", "First write done! Reading back...", UVM_LOW)

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h0C;
        rd.start(env.axil_agent.sqr);
        `uvm_info("TEST", $sformatf("Read back: 0x%08x", rd.rdata), UVM_LOW)

        `uvm_info("TEST", "Running full config sequence...", UVM_LOW)
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        run_attention(cfg);

        env.scoreboard.causal_en = 1;
        env.scoreboard.valid_len = 0;
        readback_and_check("CAUSAL");

        env.coverage.sample_config(1, 0, 0, 0, 0, 1, 0);
        phase.drop_objection(this);
    endtask
endclass

// --- Test 2: Padding Mask ---
class fa_bonus_padding_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_padding_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_bonus_config_seq cfg;
        phase.raise_objection(this);
        #100;
        preload_random_data();
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.padding_en = 1;
        cfg.pad_len_val = 16'd200;
        run_attention(cfg);

        env.scoreboard.causal_en = 1;
        env.scoreboard.valid_len = 200;
        readback_and_check("PADDING");

        env.coverage.sample_config(1, 1, 0, 0, 0, 1, 0);
        phase.drop_objection(this);
    endtask
endclass

// --- Test 3: Multi-Head ---
class fa_bonus_multihead_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_multihead_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_bonus_config_seq cfg;
        phase.raise_objection(this);
        #100;
        preload_random_data();
        // Copy to head 1
        env.mem_agent.preload_matrix(Q_BASE + 64'h8000, 256, 64, env.scoreboard.q_data);
        env.mem_agent.preload_matrix(K_BASE + 64'h8000, 256, 64, env.scoreboard.k_data);
        env.mem_agent.preload_matrix(V_BASE + 64'h8000, 256, 64, env.scoreboard.v_data);

        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.num_heads_val = 8'd2;
        cfg.head_stride_val = 32'h8000;
        run_attention(cfg);

        env.scoreboard.causal_en = 1;
        env.scoreboard.valid_len = 0;
        readback_and_check("MULTIHEAD");

        env.coverage.sample_config(1, 0, 0, 0, 0, 2, 0);
        phase.drop_objection(this);
    endtask
endclass

// --- Test 4: Dropout ---
class fa_bonus_dropout_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_dropout_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_bonus_config_seq cfg;
        phase.raise_objection(this);
        #100;
        preload_random_data();
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.dropout_en = 1;
        cfg.drop_prob_val = 8'h33;
        cfg.dropout_seed_val = 32'hCAFE_BABE;
        run_attention(cfg);

        `uvm_info("DROPOUT", "Dropout test completed successfully", UVM_LOW)
        env.coverage.sample_config(1, 0, 1, 0, 0, 1, 0);
        phase.drop_objection(this);
    endtask
endclass

// --- Test 5: BF16 Format ---
class fa_bonus_bf16_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_bf16_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_bonus_config_seq cfg;
        phase.raise_objection(this);
        #100;
        preload_random_data();
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.data_fmt_val = 3'd3; // BF16
        run_attention(cfg);

        `uvm_info("BF16", "BF16 format test completed", UVM_LOW)
        env.coverage.sample_config(1, 0, 0, 0, 3, 1, 0);
        phase.drop_objection(this);
    endtask
endclass

// --- Test 6: All Features Combined ---
class fa_bonus_combined_test extends fa_bonus_base_test;
    `uvm_component_utils(fa_bonus_combined_test)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_bonus_config_seq cfg;
        phase.raise_objection(this);
        #100;
        preload_random_data();
        env.mem_agent.preload_matrix(Q_BASE + 64'h8000, 256, 64, env.scoreboard.q_data);
        env.mem_agent.preload_matrix(K_BASE + 64'h8000, 256, 64, env.scoreboard.k_data);
        env.mem_agent.preload_matrix(V_BASE + 64'h8000, 256, 64, env.scoreboard.v_data);

        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.padding_en = 1;
        cfg.pad_len_val = 16'd200;
        cfg.num_heads_val = 8'd2;
        cfg.head_stride_val = 32'h8000;
        run_attention(cfg);

        env.scoreboard.causal_en = 1;
        env.scoreboard.valid_len = 200;
        readback_and_check("COMBINED");

        env.coverage.sample_config(1, 1, 0, 0, 0, 2, 0);
        phase.drop_objection(this);
    endtask
endclass
