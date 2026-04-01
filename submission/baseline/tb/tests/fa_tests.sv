// ============================================================
// FlashAttention UVM Tests
// ============================================================

// --- Base Test ---
class fa_base_test extends uvm_test;
    `uvm_component_utils(fa_base_test)

    fa_env env;

    // Memory layout
    bit [63:0] Q_BASE = 64'h0000_0000_0001_0000;
    bit [63:0] K_BASE = 64'h0000_0000_0002_0000;
    bit [63:0] V_BASE = 64'h0000_0000_0003_0000;
    bit [63:0] O_BASE = 64'h0000_0000_0004_0000;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fa_env::type_id::create("env", this);
    endfunction

    // Helper: preload matrix into memory agent
    function void preload_matrix(bit [63:0] base, shortint data[][]);
        env.mem_agent.preload_matrix(base, data.size(), data[0].size(), data);
    endfunction

    // Helper: readback matrix from memory agent
    function void readback_matrix(bit [63:0] base, int rows, int cols, ref shortint data[][]);
        env.mem_agent.readback_matrix(base, rows, cols, data);
    endfunction

    // Run a complete attention operation
    task run_attention(bit causal_en, shortint q[][], shortint k[][], shortint v[][]);
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;

        // Preload data
        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        // Store in scoreboard
        env.scoreboard.q_data = q;
        env.scoreboard.k_data = k;
        env.scoreboard.v_data = v;
        env.scoreboard.causal_en = causal_en;

        // Configure and start
        cfg_seq = fa_config_and_start_seq::type_id::create("cfg");
        cfg_seq.q_base    = Q_BASE;
        cfg_seq.k_base    = K_BASE;
        cfg_seq.v_base    = V_BASE;
        cfg_seq.o_base    = O_BASE;
        cfg_seq.causal_en = causal_en;
        cfg_seq.start(env.axil_agent.sqr);

        // Wait for completion
        poll_seq = fa_poll_done_seq::type_id::create("poll");
        poll_seq.start(env.axil_agent.sqr);

        // Read back O and check
        readback_matrix(O_BASE, 256, 64, env.scoreboard.dut_o);
        env.scoreboard.compute_golden();
        env.scoreboard.check_results();

        // Sample coverage
        env.coverage.sample_config(causal_en);
    endtask
endclass

// --- TC01: Zero Input Test ---
class fa_zero_test extends fa_base_test;
    `uvm_component_utils(fa_zero_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);

        q = new[256]; k = new[256]; v = new[256];
        for (int i = 0; i < 256; i++) begin
            q[i] = new[64]; k[i] = new[64]; v[i] = new[64];
            for (int j = 0; j < 64; j++) begin
                q[i][j] = 0; k[i][j] = 0; v[i][j] = 0;
            end
        end

        `uvm_info("TEST", "TC01: Zero input test", UVM_LOW)
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd0);

        phase.drop_objection(this);
    endtask
endclass

// --- TC03: Random No-Causal Test ---
class fa_random_nocausal_test extends fa_base_test;
    `uvm_component_utils(fa_random_nocausal_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);

        q = new[256]; k = new[256]; v = new[256];
        for (int i = 0; i < 256; i++) begin
            q[i] = new[64]; k[i] = new[64]; v[i] = new[64];
            for (int j = 0; j < 64; j++) begin
                q[i][j] = $urandom_range(0, 512) - 256;  // small Q8.8 range
                k[i][j] = $urandom_range(0, 512) - 256;
                v[i][j] = $urandom_range(0, 512) - 256;
            end
        end

        `uvm_info("TEST", "TC03: Random no-causal test", UVM_LOW)
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd4);

        phase.drop_objection(this);
    endtask
endclass

// --- TC04: Random Causal Test ---
class fa_random_causal_test extends fa_base_test;
    `uvm_component_utils(fa_random_causal_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);

        q = new[256]; k = new[256]; v = new[256];
        for (int i = 0; i < 256; i++) begin
            q[i] = new[64]; k[i] = new[64]; v[i] = new[64];
            for (int j = 0; j < 64; j++) begin
                q[i][j] = $urandom_range(0, 512) - 256;
                k[i][j] = $urandom_range(0, 512) - 256;
                v[i][j] = $urandom_range(0, 512) - 256;
            end
        end

        `uvm_info("TEST", "TC04: Random causal test", UVM_LOW)
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd4);

        phase.drop_objection(this);
    endtask
endclass

// --- TC09: Register Access Test ---
class fa_reg_access_test extends fa_base_test;
    `uvm_component_utils(fa_reg_access_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;
        bit [7:0] test_addrs[] = '{8'h08, 8'h14, 8'h18, 8'h1C, 8'h20,
                                    8'h24, 8'h28, 8'h2C, 8'h30, 8'h34,
                                    8'h38, 8'h3C};
        phase.raise_objection(this);

        `uvm_info("TEST", "TC09: Register access test", UVM_LOW)

        foreach (test_addrs[i]) begin
            bit [31:0] test_val = $urandom();

            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = test_addrs[i];
            wr.data = test_val;
            wr.start(env.axil_agent.sqr);

            rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = test_addrs[i];
            rd.start(env.axil_agent.sqr);

            if (rd.rdata !== test_val)
                `uvm_error("REG", $sformatf("Mismatch at 0x%02h: wrote 0x%08h, read 0x%08h",
                                            test_addrs[i], test_val, rd.rdata))
            else
                `uvm_info("REG", $sformatf("OK: addr=0x%02h val=0x%08h", test_addrs[i], test_val), UVM_HIGH)
        end

        phase.drop_objection(this);
    endtask
endclass
