// ============================================================
// FlashAttention Bonus UVM Tests — Complete 24-Test Suite
// 7 Verification Blocks: VP, REG, DMA, AXI, PERF, COV, COMP
// ============================================================

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

    function void gen_random_matrix(ref shortint data[][], input int rows, input int cols, input int range = 512);
        data = new[rows];
        for (int i = 0; i < rows; i++) begin
            data[i] = new[cols];
            for (int j = 0; j < cols; j++)
                data[i][j] = $urandom_range(0, range) - range/2;
        end
    endfunction

    function void gen_zero_matrix(ref shortint data[][], input int rows, input int cols);
        data = new[rows];
        for (int i = 0; i < rows; i++) begin
            data[i] = new[cols];
            for (int j = 0; j < cols; j++)
                data[i][j] = 0;
        end
    endfunction

    function void gen_identity_matrix(ref shortint data[][], input int rows, input int cols,
                                       input shortint diag_val = 16'h0100);
        data = new[rows];
        for (int i = 0; i < rows; i++) begin
            data[i] = new[cols];
            for (int j = 0; j < cols; j++)
                data[i][j] = (i == j && i < cols) ? diag_val : 0;
        end
    endfunction

    function void gen_max_matrix(ref shortint data[][], input int rows, input int cols);
        data = new[rows];
        for (int i = 0; i < rows; i++) begin
            data[i] = new[cols];
            for (int j = 0; j < cols; j++)
                data[i][j] = 16'h3FFF;
        end
    endfunction

    function void gen_boundary_matrix(ref shortint data[][], input int rows, input int cols);
        data = new[rows];
        for (int i = 0; i < rows; i++) begin
            data[i] = new[cols];
            for (int j = 0; j < cols; j++)
                case ((i + j) % 4)
                    0: data[i][j] = 16'h7FFF;
                    1: data[i][j] = 16'h8000;
                    2: data[i][j] = 16'h0001;
                    3: data[i][j] = 16'hFFFF;
                endcase
        end
    endfunction

    task run_bonus_attention(input bit causal, input shortint q[][], input shortint k[][], input shortint v[][]);
        fa_bonus_config_seq  cfg;
        fa_bonus_poll_done_seq poll;

        env.mem_agent.preload_matrix(Q_BASE, q.size(), q[0].size(), q);
        env.mem_agent.preload_matrix(K_BASE, k.size(), k[0].size(), k);
        env.mem_agent.preload_matrix(V_BASE, v.size(), v[0].size(), v);

        env.scoreboard.q_data = q;
        env.scoreboard.k_data = k;
        env.scoreboard.v_data = v;
        env.scoreboard.causal_en = causal;
        env.scoreboard.valid_len = 0;

        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = causal;
        cfg.start(env.axil_agent.sqr);

        poll = fa_bonus_poll_done_seq::type_id::create("poll");
        poll.start(env.axil_agent.sqr);

        env.mem_agent.readback_matrix(O_BASE, 256, 64, env.scoreboard.dut_o);
        env.scoreboard.compute_golden();
        env.scoreboard.check_result(causal ? "CAUSAL" : "NOCAUSAL");

        env.coverage.sample_config(causal, 0, 0, 0, 0, 1, 0);
        env.coverage.sample_perf(poll.cycles);
    endtask
endclass

// ====================================================================
// SECTION 1: Verification Point Tests (VP01-VP06)
// ====================================================================

class fab_zero_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_zero_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP01: Zero input test (Bonus)", UVM_LOW)
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_bonus_attention(0, q, k, v);
        env.coverage.sample_vp("zero");
        phase.drop_objection(this);
    endtask
endclass

class fab_random_nocausal_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_random_nocausal_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP02: Random no-causal test (Bonus)", UVM_LOW)
        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);
        run_bonus_attention(0, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

class fab_random_causal_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_random_causal_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP03: Random causal test (Bonus)", UVM_LOW)
        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);
        run_bonus_attention(1, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

class fab_identity_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_identity_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP04: Identity matrix test (Bonus)", UVM_LOW)
        gen_identity_matrix(q, 256, 64, 16'h0100);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(0, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

class fab_boundary_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_boundary_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP05: Boundary value test (Bonus)", UVM_LOW)
        gen_boundary_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        run_bonus_attention(1, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

class fab_maxval_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_maxval_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP06: Max-value test (Bonus)", UVM_LOW)
        gen_max_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 64);
        gen_random_matrix(v, 256, 64, 64);
        run_bonus_attention(0, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 2: Register Model Tests (REG01-REG07)
// ====================================================================

class fab_reg_reset_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_reg_reset_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG01: Bonus register reset value test", UVM_LOW)
        seq = fa_bonus_reg_reset_seq::type_id::create("seq");
        seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

class fab_reg_access_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_access_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;
        bit [7:0] addrs[] = '{8'h08, 8'h0C, 8'h10, 8'h14, 8'h18,
                               8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C,
                               8'h30, 8'h34, 8'h38, 8'h3C,
                               8'h44, 8'h48, 8'h50, 8'h54};
        phase.raise_objection(this);
        `uvm_info("TEST", "REG02: Bonus register access test", UVM_LOW)
        foreach (addrs[i]) begin
            bit [31:0] tv = $urandom();
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = addrs[i]; wr.data = tv; wr.start(env.axil_agent.sqr);
            rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = addrs[i]; rd.start(env.axil_agent.sqr);
            if (rd.rdata !== tv)
                `uvm_error("REG", $sformatf("Mismatch 0x%02h: W=0x%08h R=0x%08h", addrs[i], tv, rd.rdata))
        end
        phase.drop_objection(this);
    endtask
endclass

class fab_reg_stress_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_stress_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_reg_stress_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG03: Bonus register stress test (50 rounds)", UVM_LOW)
        seq = fa_bonus_reg_stress_seq::type_id::create("seq");
        seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

class fab_reg_frontdoor_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_frontdoor_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG04: Bonus front-door register verification", UVM_LOW)

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h08; wr.data = 32'h0000_0001; wr.start(env.axil_agent.sqr);
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h08; rd.start(env.axil_agent.sqr);
        if (rd.rdata[0] !== 1'b1)
            `uvm_error("FD", $sformatf("CFG causal_en mismatch: 0x%08h", rd.rdata))
        else
            `uvm_info("FD", "CFG causal_en OK", UVM_LOW)

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h14; wr.data = Q_BASE[31:0]; wr.start(env.axil_agent.sqr);
        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h18; wr.data = Q_BASE[63:32]; wr.start(env.axil_agent.sqr);
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h14; rd.start(env.axil_agent.sqr);
        if (rd.rdata !== Q_BASE[31:0])
            `uvm_error("FD", "Q_BASE_L mismatch")
        else
            `uvm_info("FD", "Q_BASE_L OK", UVM_LOW)

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h0C; wr.data = 32'd256; wr.start(env.axil_agent.sqr);
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h0C; rd.start(env.axil_agent.sqr);
        if (rd.rdata !== 32'd256)
            `uvm_error("FD", "SEQ_LEN mismatch")
        else
            `uvm_info("FD", "SEQ_LEN OK", UVM_LOW)

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h10; wr.data = 32'd2; wr.start(env.axil_agent.sqr);
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h10; rd.start(env.axil_agent.sqr);
        if (rd.rdata !== 32'd2)
            `uvm_error("FD", "NUM_HEADS mismatch")
        else
            `uvm_info("FD", "NUM_HEADS OK", UVM_LOW)

        wr = fa_reg_write_seq::type_id::create("wr");
        wr.addr = 8'h50; wr.data = 32'd3; wr.start(env.axil_agent.sqr);
        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h50; rd.start(env.axil_agent.sqr);
        if (rd.rdata !== 32'd3)
            `uvm_error("FD", "DATA_FMT mismatch")
        else
            `uvm_info("FD", "DATA_FMT OK", UVM_LOW)

        rd = fa_reg_read_seq::type_id::create("rd");
        rd.addr = 8'h40; rd.start(env.axil_agent.sqr);
        `uvm_info("FD", $sformatf("CYCLES = %0d", rd.rdata), UVM_LOW)

        phase.drop_objection(this);
    endtask
endclass

class fab_reg_walk_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_walk_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_reg_walk_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG05: Bonus register walking bit test", UVM_LOW)
        seq = fa_bonus_reg_walk_seq::type_id::create("seq");
        seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

class fab_reg_unmapped_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_unmapped_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_reg_unmapped_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG06: Bonus unmapped register access test", UVM_LOW)
        seq = fa_bonus_reg_unmapped_seq::type_id::create("seq");
        seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

class fab_reg_soft_reset_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_reg_soft_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_soft_reset_seq seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG07: Bonus soft reset test", UVM_LOW)
        seq = fa_bonus_soft_reset_seq::type_id::create("seq");
        seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 3: DMA Tests (DMA01-DMA03)
// ====================================================================

class fab_dma_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_dma_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "DMA01: Bonus DMA data integrity test", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(1, q, k, v);
        `uvm_info("DMA", $sformatf("DMA integrity: mean_err=%.6f max_err=%.6f",
                                    env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

class fab_dma_b2b_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_dma_b2b_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "DMA02: Bonus DMA back-to-back test", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(1, q, k, v);
        `uvm_info("DMA", $sformatf("B2B run 1: mean=%.6f max=%.6f",
            env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_bonus_attention(0, q, k, v);
        `uvm_info("DMA", $sformatf("B2B run 2: mean=%.6f max=%.6f",
            env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

class fab_dma_addr_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_dma_addr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_bonus_config_seq  cfg;
        fa_bonus_poll_done_seq poll;
        bit [63:0] q2 = 64'h0010_0000, k2 = 64'h0020_0000;
        bit [63:0] v2 = 64'h0030_0000, o2 = 64'h0040_0000;
        phase.raise_objection(this);
        `uvm_info("TEST", "DMA03: Bonus DMA different address test", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        env.mem_agent.preload_matrix(q2, 256, 64, q);
        env.mem_agent.preload_matrix(k2, 256, 64, k);
        env.mem_agent.preload_matrix(v2, 256, 64, v);
        env.scoreboard.q_data = q;
        env.scoreboard.k_data = k;
        env.scoreboard.v_data = v;
        env.scoreboard.causal_en = 1;
        env.scoreboard.valid_len = 0;
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = q2; cfg.k_base = k2;
        cfg.v_base = v2; cfg.o_base = o2;
        cfg.causal_en = 1;
        cfg.start(env.axil_agent.sqr);
        poll = fa_bonus_poll_done_seq::type_id::create("poll");
        poll.start(env.axil_agent.sqr);
        if (poll.done) begin
            env.mem_agent.readback_matrix(o2, 256, 64, env.scoreboard.dut_o);
            env.scoreboard.compute_golden();
            env.scoreboard.check_result("DMA_ADDR");
        end else
            `uvm_error("DMA", "Alt address computation timeout")
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 4: AXI Protocol Tests (AXI01-AXI03)
// ====================================================================

class fab_axi_protocol_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_axi_protocol_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "AXI01: Bonus AXI protocol compliance test", UVM_LOW)
        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);
        run_bonus_attention(1, q, k, v);
        `uvm_info("TEST", "AXI protocol test completed", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

class fab_axi_dual_mode_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_axi_dual_mode_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "AXI02: Bonus AXI dual-mode test", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(0, q, k, v);
        `uvm_info("AXI", "Non-causal pass done", UVM_LOW)
        env.mem_agent.clear_region(O_BASE, 256*64*2);
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(1, q, k, v);
        `uvm_info("AXI", "Causal pass done", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

class fab_axi_regonly_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_axi_regonly_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        fa_bonus_reg_stress_seq stress;
        fa_bonus_rand_reg_seq   rand_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "AXI03: Bonus AXI-Lite register-only stress", UVM_LOW)
        stress = fa_bonus_reg_stress_seq::type_id::create("stress");
        stress.num_rounds = 20; stress.start(env.axil_agent.sqr);
        rand_seq = fa_bonus_rand_reg_seq::type_id::create("rand");
        rand_seq.num_txns = 300; rand_seq.start(env.axil_agent.sqr);
        `uvm_info("TEST", "AXI-Lite stress complete", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 5: Performance Tests (PERF01-PERF02)
// ====================================================================

class fab_perf_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_perf_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_bonus_config_seq cfg;
        fa_bonus_poll_done_seq poll;
        int cycle_limit = 600000;
        phase.raise_objection(this);
        `uvm_info("TEST", "PERF01: Bonus performance benchmark", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        env.mem_agent.preload_matrix(Q_BASE, 256, 64, q);
        env.mem_agent.preload_matrix(K_BASE, 256, 64, k);
        env.mem_agent.preload_matrix(V_BASE, 256, 64, v);
        cfg = fa_bonus_config_seq::type_id::create("cfg");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.start(env.axil_agent.sqr);
        poll = fa_bonus_poll_done_seq::type_id::create("poll");
        poll.start(env.axil_agent.sqr);
        if (poll.done) begin
            real total_rd = 3.0 * 256.0 * 64.0 * 2.0;
            real total_wr = 256.0 * 64.0 * 2.0;
            real clk_ns = 2.0;
            real rd_bw = total_rd / (poll.cycles * clk_ns * 1e-9) / 1e6;
            real wr_bw = total_wr / (poll.cycles * clk_ns * 1e-9) / 1e6;
            real util = (total_rd + total_wr) / 16.0 / real'(poll.cycles);
            env.coverage.sample_perf(poll.cycles);
            env.coverage.sample_perf_detail(rd_bw, wr_bw, util);
            `uvm_info("PERF", $sformatf(
                "Performance:\n  Cycles: %0d (limit %0d) %s\n  Read BW: %.1f MB/s\n  Write BW: %.1f MB/s",
                poll.cycles, cycle_limit,
                (poll.cycles <= cycle_limit) ? "PASS" : "FAIL",
                rd_bw, wr_bw), UVM_LOW)
        end
        phase.drop_objection(this);
    endtask
endclass

class fab_perf_compare_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_perf_compare_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_bonus_config_seq cfg;
        fa_bonus_poll_done_seq poll;
        int causal_cyc, nocausal_cyc;
        phase.raise_objection(this);
        `uvm_info("TEST", "PERF02: Bonus causal vs non-causal comparison", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        env.mem_agent.preload_matrix(Q_BASE, 256, 64, q);
        env.mem_agent.preload_matrix(K_BASE, 256, 64, k);
        env.mem_agent.preload_matrix(V_BASE, 256, 64, v);
        cfg = fa_bonus_config_seq::type_id::create("cfg_nc");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 0;
        cfg.start(env.axil_agent.sqr);
        poll = fa_bonus_poll_done_seq::type_id::create("poll_nc");
        poll.start(env.axil_agent.sqr);
        nocausal_cyc = poll.cycles;
        env.mem_agent.clear_region(O_BASE, 256*64*2);
        env.mem_agent.preload_matrix(Q_BASE, 256, 64, q);
        env.mem_agent.preload_matrix(K_BASE, 256, 64, k);
        env.mem_agent.preload_matrix(V_BASE, 256, 64, v);
        cfg = fa_bonus_config_seq::type_id::create("cfg_c");
        cfg.q_base = Q_BASE; cfg.k_base = K_BASE;
        cfg.v_base = V_BASE; cfg.o_base = O_BASE;
        cfg.causal_en = 1;
        cfg.start(env.axil_agent.sqr);
        poll = fa_bonus_poll_done_seq::type_id::create("poll_c");
        poll.start(env.axil_agent.sqr);
        causal_cyc = poll.cycles;
        `uvm_info("PERF", $sformatf("Non-causal: %0d  Causal: %0d", nocausal_cyc, causal_cyc), UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 6: Coverage-Driven Tests (COV01-COV02)
// ====================================================================

class fab_coverage_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_coverage_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "COV01: Bonus coverage-driven random test", UVM_LOW)
        begin
            fa_bonus_rand_reg_seq rs = fa_bonus_rand_reg_seq::type_id::create("rs");
            rs.num_txns = 200; rs.start(env.axil_agent.sqr);
        end
        gen_random_matrix(q, 256, 64, 128);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        run_bonus_attention(0, q, k, v);
        gen_random_matrix(q, 256, 64, 128);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        run_bonus_attention(1, q, k, v);
        phase.drop_objection(this);
    endtask
endclass

class fab_coverage_closure_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_coverage_closure_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "COV02: Bonus coverage closure test", UVM_LOW)
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_bonus_attention(0, q, k, v);
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_bonus_attention(1, q, k, v);
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_bonus_attention(0, q, k, v);
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_bonus_attention(1, q, k, v);
        gen_identity_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(0, q, k, v);
        `uvm_info("TEST", "Coverage closure complete", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 7: Comprehensive Test (COMP)
// ====================================================================

class fab_comprehensive_test extends fa_bonus_base_test;
    `uvm_component_utils(fab_comprehensive_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_bonus_reg_reset_seq rst_seq;
        fa_bonus_reg_stress_seq stress;
        phase.raise_objection(this);
        `uvm_info("TEST", "COMP: Bonus comprehensive all-in-one test", UVM_LOW)
        `uvm_info("TEST", "Phase 1: Register verification", UVM_LOW)
        rst_seq = fa_bonus_reg_reset_seq::type_id::create("rst");
        rst_seq.start(env.axil_agent.sqr);
        stress = fa_bonus_reg_stress_seq::type_id::create("stress");
        stress.num_rounds = 10; stress.start(env.axil_agent.sqr);
        `uvm_info("TEST", "Phase 2: Causal attention", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(1, q, k, v);
        `uvm_info("TEST", "Phase 3: Non-causal attention", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_bonus_attention(0, q, k, v);
        `uvm_info("TEST", "Phase 4: DMA back-to-back", UVM_LOW)
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_bonus_attention(1, q, k, v);
        `uvm_info("TEST", "=== Bonus comprehensive test COMPLETE ===", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
