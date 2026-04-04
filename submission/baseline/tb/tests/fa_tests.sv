// ============================================================
// FlashAttention UVM Tests — Complete Verification Suite
// Covers: Verification Points, AXI VIP, Register Model,
//         DMA, AXI Protocol, Performance, Coverage
// ============================================================

// --- Base Test ---
class fa_base_test extends uvm_test;
    `uvm_component_utils(fa_base_test)
    fa_env env;

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

    function void preload_matrix(input bit [63:0] base, input shortint data[][]);
        env.mem_agent.preload_matrix(base, data.size(), data[0].size(), data);
    endfunction

    function void readback_matrix(input bit [63:0] base, input int rows, input int cols, ref shortint data[][]);
        env.mem_agent.readback_matrix(base, rows, cols, data);
    endfunction

    task run_attention(input bit causal_en, input shortint q[][], input shortint k[][], input shortint v[][]);
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;

        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        env.scoreboard.q_data = q;
        env.scoreboard.k_data = k;
        env.scoreboard.v_data = v;
        env.scoreboard.causal_en = causal_en;

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg");
        cfg_seq.q_base    = Q_BASE;
        cfg_seq.k_base    = K_BASE;
        cfg_seq.v_base    = V_BASE;
        cfg_seq.o_base    = O_BASE;
        cfg_seq.causal_en = causal_en;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll");
        poll_seq.start(env.axil_agent.sqr);

        readback_matrix(O_BASE, 256, 64, env.scoreboard.dut_o);
        env.scoreboard.compute_golden();
        env.scoreboard.check_results();

        env.coverage.sample_config(causal_en);
        env.coverage.sample_perf(poll_seq.cycles);
    endtask

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
            for (int j = 0; j < cols; j++) begin
                case ((i + j) % 4)
                    0: data[i][j] = 16'h7FFF;   // max positive
                    1: data[i][j] = 16'h8000;   // max negative
                    2: data[i][j] = 16'h0001;   // min positive
                    3: data[i][j] = 16'hFFFF;   // -1
                endcase
            end
        end
    endfunction
endclass

// ====================================================================
// SECTION 1: Verification Point Tests (VP)
// ====================================================================

// --- VP01: Zero Input Test ---
class fa_zero_test extends fa_base_test;
    `uvm_component_utils(fa_zero_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP01: Zero input test", UVM_LOW)
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd0);
        env.coverage.sample_vp("zero");
        phase.drop_objection(this);
    endtask
endclass

// --- VP02: Random No-Causal Test ---
class fa_random_nocausal_test extends fa_base_test;
    `uvm_component_utils(fa_random_nocausal_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP02: Random no-causal test", UVM_LOW)
        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd4);
        env.coverage.sample_vp("nocausal");
        phase.drop_objection(this);
    endtask
endclass

// --- VP03: Random Causal Test ---
class fa_random_causal_test extends fa_base_test;
    `uvm_component_utils(fa_random_causal_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP03: Random causal test", UVM_LOW)
        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd4);
        env.coverage.sample_vp("causal");
        phase.drop_objection(this);
    endtask
endclass

// --- VP04: Identity Matrix Test ---
class fa_identity_test extends fa_base_test;
    `uvm_component_utils(fa_identity_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP04: Identity matrix Q test", UVM_LOW)
        gen_identity_matrix(q, 256, 64, 16'h0100);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd5);
        env.coverage.sample_vp("identity");
        phase.drop_objection(this);
    endtask
endclass

// --- VP05: Boundary Value Test ---
class fa_boundary_test extends fa_base_test;
    `uvm_component_utils(fa_boundary_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP05: Boundary value test", UVM_LOW)
        gen_boundary_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd6);
        env.coverage.sample_vp("boundary");
        phase.drop_objection(this);
    endtask
endclass

// --- VP06: Max Value Test ---
class fa_maxval_test extends fa_base_test;
    `uvm_component_utils(fa_maxval_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "VP06: Max-value test", UVM_LOW)
        gen_max_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 64);
        gen_random_matrix(v, 256, 64, 64);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd1);
        env.coverage.sample_vp("maxval");
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 2: Register Model Tests (REG)
// ====================================================================

// --- REG01: Register Reset Value Test ---
class fa_reg_reset_test extends fa_base_test;
    `uvm_component_utils(fa_reg_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_reset_seq reset_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG01: Register reset value test", UVM_LOW)
        reset_seq = fa_reg_reset_seq::type_id::create("reset_seq");
        reset_seq.start(env.axil_agent.sqr);
        env.coverage.sample_vp("reg_reset");
        phase.drop_objection(this);
    endtask
endclass

// --- REG02: Register Read/Write Test ---
class fa_reg_access_test extends fa_base_test;
    `uvm_component_utils(fa_reg_access_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_write_seq wr;
        fa_reg_read_seq  rd;
        bit [7:0] test_addrs[] = '{8'h08, 8'h14, 8'h18, 8'h1C, 8'h20,
                                    8'h24, 8'h28, 8'h2C, 8'h30, 8'h34,
                                    8'h38, 8'h3C};
        phase.raise_objection(this);
        `uvm_info("TEST", "REG02: Register access test", UVM_LOW)

        foreach (test_addrs[i]) begin
            bit [31:0] test_val = $urandom();
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = test_addrs[i]; wr.data = test_val;
            wr.start(env.axil_agent.sqr);

            rd = fa_reg_read_seq::type_id::create("rd");
            rd.addr = test_addrs[i];
            rd.start(env.axil_agent.sqr);

            if (rd.rdata !== test_val)
                `uvm_error("REG", $sformatf("Mismatch at 0x%02h: W=0x%08h R=0x%08h",
                                            test_addrs[i], test_val, rd.rdata))
            else
                `uvm_info("REG", $sformatf("OK: 0x%02h = 0x%08h", test_addrs[i], test_val), UVM_HIGH)
        end
        env.coverage.sample_vp("reg_rw");
        phase.drop_objection(this);
    endtask
endclass

// --- REG03: Register Stress Test ---
class fa_reg_stress_test extends fa_base_test;
    `uvm_component_utils(fa_reg_stress_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_stress_seq stress_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG03: Register stress test (50 rounds)", UVM_LOW)
        stress_seq = fa_reg_stress_seq::type_id::create("stress_seq");
        stress_seq.start(env.axil_agent.sqr);
        env.coverage.sample_vp("reg_stress");
        phase.drop_objection(this);
    endtask
endclass

// --- REG04: RAL Model Test ---
class fa_ral_test extends fa_base_test;
    `uvm_component_utils(fa_ral_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        uvm_status_e status;
        uvm_reg_data_t rdata;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG04: RAL model test", UVM_LOW)

        // Front-door write via RAL
        env.reg_model.cfg.write(status, 32'h0000_0001);
        if (status != UVM_IS_OK)
            `uvm_error("RAL", "CFG write failed")

        env.reg_model.cfg.read(status, rdata);
        if (rdata[0] !== 1'b1)
            `uvm_error("RAL", $sformatf("CFG read mismatch: got 0x%08h", rdata))
        else
            `uvm_info("RAL", "CFG causal_en via RAL OK", UVM_LOW)

        // All base addresses
        env.reg_model.q_base_l.write(status, Q_BASE[31:0]);
        env.reg_model.q_base_h.write(status, Q_BASE[63:32]);
        env.reg_model.k_base_l.write(status, K_BASE[31:0]);
        env.reg_model.k_base_h.write(status, K_BASE[63:32]);
        env.reg_model.v_base_l.write(status, V_BASE[31:0]);
        env.reg_model.v_base_h.write(status, V_BASE[63:32]);
        env.reg_model.o_base_l.write(status, O_BASE[31:0]);
        env.reg_model.o_base_h.write(status, O_BASE[63:32]);

        // Read back
        env.reg_model.q_base_l.read(status, rdata);
        if (rdata !== Q_BASE[31:0])
            `uvm_error("RAL", $sformatf("Q_BASE_L mismatch: 0x%08h vs 0x%08h", rdata, Q_BASE[31:0]))
        else
            `uvm_info("RAL", "Q_BASE_L via RAL OK", UVM_LOW)

        env.reg_model.k_base_l.read(status, rdata);
        if (rdata !== K_BASE[31:0])
            `uvm_error("RAL", $sformatf("K_BASE_L mismatch"))
        else
            `uvm_info("RAL", "K_BASE_L via RAL OK", UVM_LOW)

        // Mirror/predict
        env.reg_model.stride_bytes.write(status, 32'd256);
        env.reg_model.stride_bytes.read(status, rdata);
        if (rdata !== 32'd256)
            `uvm_error("RAL", "STRIDE mirror mismatch")
        else
            `uvm_info("RAL", "STRIDE via RAL OK", UVM_LOW)

        // Neg-large and scale
        env.reg_model.neg_large.write(status, 32'h0000_8000);
        env.reg_model.neg_large.read(status, rdata);
        if (rdata !== 32'h0000_8000)
            `uvm_error("RAL", "NEG_LARGE mismatch")
        else
            `uvm_info("RAL", "NEG_LARGE via RAL OK", UVM_LOW)

        env.reg_model.scale.write(status, 32'h0000_0020);
        env.reg_model.scale.read(status, rdata);
        if (rdata !== 32'h0000_0020)
            `uvm_error("RAL", "SCALE mismatch")
        else
            `uvm_info("RAL", "SCALE via RAL OK", UVM_LOW)

        // Read-only register (CYCLES)
        env.reg_model.cycles.read(status, rdata);
        `uvm_info("RAL", $sformatf("CYCLES = %0d", rdata), UVM_LOW)

        env.coverage.sample_vp("reg_ral");
        phase.drop_objection(this);
    endtask
endclass

// --- REG05: Register Walking Bit Test ---
class fa_reg_walk_test extends fa_base_test;
    `uvm_component_utils(fa_reg_walk_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_walk_bit_seq walk_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG05: Register walking bit test", UVM_LOW)
        walk_seq = fa_reg_walk_bit_seq::type_id::create("walk_seq");
        walk_seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

// --- REG06: Unmapped Register Test ---
class fa_reg_unmapped_test extends fa_base_test;
    `uvm_component_utils(fa_reg_unmapped_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_unmapped_seq unmap_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG06: Unmapped register access test", UVM_LOW)
        unmap_seq = fa_reg_unmapped_seq::type_id::create("unmap_seq");
        unmap_seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

// --- REG07: Soft Reset Test ---
class fa_reg_soft_reset_test extends fa_base_test;
    `uvm_component_utils(fa_reg_soft_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_soft_reset_seq srst_seq;
        phase.raise_objection(this);
        `uvm_info("TEST", "REG07: Soft reset test", UVM_LOW)
        srst_seq = fa_soft_reset_seq::type_id::create("srst_seq");
        srst_seq.start(env.axil_agent.sqr);
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 3: DMA Tests
// ====================================================================

// --- DMA01: DMA End-to-End Data Integrity ---
class fa_dma_test extends fa_base_test;
    `uvm_component_utils(fa_dma_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];

        phase.raise_objection(this);
        `uvm_info("TEST", "DMA01: DMA data integrity test (golden model comparison)", UVM_LOW)

        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);

        // Preload and verify
        preload_matrix(Q_BASE, q);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                bit [15:0] rd_val = env.mem_agent.read_half(Q_BASE + (i * 64 + j) * 2);
                if (rd_val !== q[i][j])
                    `uvm_error("DMA", $sformatf("Preload verify Q[%0d][%0d]: got 0x%04h exp 0x%04h",
                                                i, j, rd_val, q[i][j]))
            end

        run_attention(1, q, k, v);

        `uvm_info("DMA", $sformatf("DMA integrity: mean_err=%.6f max_err=%.6f",
                                    env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)

        env.coverage.sample_vp("dma_int");
        phase.drop_objection(this);
    endtask
endclass

// --- DMA02: DMA Back-to-Back Transfers ---
class fa_dma_b2b_test extends fa_base_test;
    `uvm_component_utils(fa_dma_b2b_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];

        phase.raise_objection(this);
        `uvm_info("TEST", "DMA02: DMA back-to-back transfer test (golden model)", UVM_LOW)

        // First computation (causal)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_attention(1, q, k, v);
        `uvm_info("DMA", $sformatf("B2B run 1: mean_err=%.6f max_err=%.6f",
                                    env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)

        // Second computation (non-causal, different data)
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_attention(0, q, k, v);
        `uvm_info("DMA", $sformatf("B2B run 2: mean_err=%.6f max_err=%.6f",
                                    env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error), UVM_LOW)

        env.coverage.sample_vp("dma_b2b");
        phase.drop_objection(this);
    endtask
endclass

// --- DMA03: DMA with Different Address Regions ---
class fa_dma_addr_test extends fa_base_test;
    `uvm_component_utils(fa_dma_addr_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;

        bit [63:0] q2 = 64'h0000_0000_0010_0000;
        bit [63:0] k2 = 64'h0000_0000_0020_0000;
        bit [63:0] v2 = 64'h0000_0000_0030_0000;
        bit [63:0] o2 = 64'h0000_0000_0040_0000;

        phase.raise_objection(this);
        `uvm_info("TEST", "DMA03: DMA different address regions test", UVM_LOW)

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

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg");
        cfg_seq.q_base = q2; cfg_seq.k_base = k2;
        cfg_seq.v_base = v2; cfg_seq.o_base = o2;
        cfg_seq.causal_en = 1;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll");
        poll_seq.start(env.axil_agent.sqr);

        if (!poll_seq.done)
            `uvm_error("DMA", "Computation with alt addresses did not complete!")
        else begin
            env.mem_agent.readback_matrix(o2, 256, 64, env.scoreboard.dut_o);
            env.scoreboard.compute_golden();
            env.scoreboard.check_results();
            `uvm_info("DMA", $sformatf("Alt addr test: mean_err=%.6f max_err=%.6f, %0d cycles",
                                        env.scoreboard.mean_abs_error, env.scoreboard.max_abs_error,
                                        poll_seq.cycles), UVM_LOW)
        end

        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 4: AXI Protocol Tests
// ====================================================================

// --- AXI01: AXI Protocol Compliance ---
class fa_axi_protocol_test extends fa_base_test;
    `uvm_component_utils(fa_axi_protocol_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "AXI01: AXI protocol compliance test", UVM_LOW)

        gen_random_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64);
        gen_random_matrix(v, 256, 64);

        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd4);
        env.coverage.sample_vp("axi_prot");

        `uvm_info("TEST", "AXI protocol test completed — check assertion results", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// --- AXI02: AXI with Both Causal Modes ---
class fa_axi_dual_mode_test extends fa_base_test;
    `uvm_component_utils(fa_axi_dual_mode_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "AXI02: AXI dual-mode test (causal + non-causal)", UVM_LOW)

        // Non-causal run
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);

        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg_nc");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 0;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll_nc");
        poll_seq.start(env.axil_agent.sqr);
        `uvm_info("AXI", $sformatf("Non-causal: %0d cycles", poll_seq.cycles), UVM_LOW)

        // Causal run
        env.mem_agent.clear_region(O_BASE, 256 * 64 * 2);

        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);

        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg_c");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 1;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll_c");
        poll_seq.start(env.axil_agent.sqr);
        `uvm_info("AXI", $sformatf("Causal: %0d cycles", poll_seq.cycles), UVM_LOW)

        `uvm_info("TEST", "AXI dual-mode test complete — no protocol violations", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// --- AXI03: AXI Register-Only Protocol Test (no DMA) ---
class fa_axi_regonly_test extends fa_base_test;
    `uvm_component_utils(fa_axi_regonly_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        fa_reg_stress_seq stress_seq;
        fa_rand_reg_seq   rand_seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "AXI03: AXI-Lite register-only protocol stress", UVM_LOW)

        stress_seq = fa_reg_stress_seq::type_id::create("stress");
        stress_seq.num_rounds = 20;
        stress_seq.start(env.axil_agent.sqr);

        rand_seq = fa_rand_reg_seq::type_id::create("rand");
        rand_seq.num_txns = 300;
        rand_seq.start(env.axil_agent.sqr);

        `uvm_info("TEST", "AXI-Lite protocol stress complete", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 5: Performance Tests
// ====================================================================

// --- PERF01: Performance Benchmark ---
class fa_perf_test extends fa_base_test;
    `uvm_component_utils(fa_perf_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;
        int cycle_limit = 300000;

        phase.raise_objection(this);
        `uvm_info("TEST", "PERF01: Performance benchmark", UVM_LOW)

        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);

        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 1;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll");
        poll_seq.start(env.axil_agent.sqr);

        if (poll_seq.done) begin
            real total_rd_bytes, total_wr_bytes;
            real clk_period_ns = 2.0;
            real rd_bw_mbps, wr_bw_mbps, bus_util;

            env.coverage.sample_perf(poll_seq.cycles);

            // Bandwidth calculation
            total_rd_bytes = (256.0 * 64.0 * 2.0) + 2.0 * (256.0 * 64.0 * 2.0); // Q + K + V
            total_wr_bytes = 256.0 * 64.0 * 2.0;  // O

            rd_bw_mbps = total_rd_bytes / (poll_seq.cycles * clk_period_ns * 1e-9) / 1e6;
            wr_bw_mbps = total_wr_bytes / (poll_seq.cycles * clk_period_ns * 1e-9) / 1e6;

            // Bus utilization = (total beats * beat_time) / total_time
            bus_util = (total_rd_bytes + total_wr_bytes) / 16.0 /
                       real'(poll_seq.cycles);

            env.coverage.sample_perf_detail(rd_bw_mbps, wr_bw_mbps, bus_util);

            `uvm_info("PERF", $sformatf(
                "Performance Report:\n  Cycles:      %0d (limit %0d) %s\n  Read BW:     %.1f MB/s\n  Write BW:    %.1f MB/s\n  Bus Util:    %.1f%%\n  Throughput:  %.2f elements/cycle",
                poll_seq.cycles, cycle_limit,
                (poll_seq.cycles <= cycle_limit) ? "PASS" : "FAIL",
                rd_bw_mbps, wr_bw_mbps,
                bus_util * 100.0,
                (256.0 * 64.0) / real'(poll_seq.cycles)
            ), UVM_LOW)

            if (poll_seq.cycles > cycle_limit)
                `uvm_warning("PERF", $sformatf("Cycles %0d exceeds target %0d",
                                                poll_seq.cycles, cycle_limit))
        end

        env.coverage.sample_vp("perf");
        phase.drop_objection(this);
    endtask
endclass

// --- PERF02: Causal vs Non-Causal Performance Comparison ---
class fa_perf_compare_test extends fa_base_test;
    `uvm_component_utils(fa_perf_compare_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq        poll_seq;
        int causal_cycles, nocausal_cycles;

        phase.raise_objection(this);
        `uvm_info("TEST", "PERF02: Causal vs Non-Causal performance comparison", UVM_LOW)

        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);

        // Non-causal
        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg_nc");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 0;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll_nc");
        poll_seq.start(env.axil_agent.sqr);
        nocausal_cycles = poll_seq.cycles;
        env.coverage.sample_perf(poll_seq.cycles);

        // Causal
        env.mem_agent.clear_region(O_BASE, 256 * 64 * 2);
        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg_c");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 1;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll_c");
        poll_seq.start(env.axil_agent.sqr);
        causal_cycles = poll_seq.cycles;
        env.coverage.sample_perf(poll_seq.cycles);

        `uvm_info("PERF", $sformatf(
            "Performance Comparison:\n  Non-causal: %0d cycles\n  Causal:     %0d cycles\n  Delta:      %0d cycles (%.1f%%)",
            nocausal_cycles, causal_cycles,
            causal_cycles - nocausal_cycles,
            100.0 * real'(causal_cycles - nocausal_cycles) / real'(nocausal_cycles)
        ), UVM_LOW)

        phase.drop_objection(this);
    endtask
endclass

// ====================================================================
// SECTION 6: Coverage-Driven Tests
// ====================================================================

// --- COV01: Coverage-Driven Random Test ---
class fa_coverage_test extends fa_base_test;
    `uvm_component_utils(fa_coverage_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "COV01: Coverage-driven random test", UVM_LOW)

        // Random register access for coverage
        begin
            fa_rand_reg_seq rand_seq = fa_rand_reg_seq::type_id::create("rand_seq");
            rand_seq.num_txns = 200;
            rand_seq.start(env.axil_agent.sqr);
        end

        // All-positive small values (no causal)
        gen_random_matrix(q, 256, 64, 128);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        for (int i = 0; i < 256; i++)
            for (int j = 0; j < 64; j++) begin
                if (q[i][j] < 0) q[i][j] = -q[i][j];
                if (k[i][j] < 0) k[i][j] = -k[i][j];
                if (v[i][j] < 0) v[i][j] = -v[i][j];
            end
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd2);

        // All-negative values (causal)
        gen_random_matrix(q, 256, 64, 128);
        gen_random_matrix(k, 256, 64, 128);
        gen_random_matrix(v, 256, 64, 128);
        for (int i = 0; i < 256; i++)
            for (int j = 0; j < 64; j++) begin
                if (q[i][j] > 0) q[i][j] = -q[i][j];
                if (k[i][j] > 0) k[i][j] = -k[i][j];
                if (v[i][j] > 0) v[i][j] = -v[i][j];
            end
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd3);

        phase.drop_objection(this);
    endtask
endclass

// --- COV02: Coverage Closure Test ---
class fa_coverage_closure_test extends fa_base_test;
    `uvm_component_utils(fa_coverage_closure_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        phase.raise_objection(this);
        `uvm_info("TEST", "COV02: Coverage closure — all patterns × all modes", UVM_LOW)

        // zero + no-causal
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd0);

        // zero + causal
        gen_zero_matrix(q, 256, 64);
        gen_zero_matrix(k, 256, 64);
        gen_zero_matrix(v, 256, 64);
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd0);

        // random mixed + no-causal
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd4);

        // random mixed + causal
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);
        run_attention(1, q, k, v);
        env.coverage.sample_data(3'd4);

        // identity + no-causal
        gen_identity_matrix(q, 256, 64);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_attention(0, q, k, v);
        env.coverage.sample_data(3'd5);

        // Register access coverage closure
        begin
            fa_reg_write_seq wr;
            fa_reg_read_seq  rd;
            bit [7:0] all_addrs[] = '{8'h00, 8'h04, 8'h08, 8'h14, 8'h18,
                                       8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C,
                                       8'h30, 8'h34, 8'h38, 8'h3C, 8'h40};
            foreach (all_addrs[i]) begin
                rd = fa_reg_read_seq::type_id::create("rd");
                rd.addr = all_addrs[i];
                rd.start(env.axil_agent.sqr);
            end
            // Write to writable registers
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = 8'h00; wr.data = 32'h5; wr.start(env.axil_agent.sqr);
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = 8'h00; wr.data = 32'h2; wr.start(env.axil_agent.sqr);
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = 8'h00; wr.data = 32'h4; wr.start(env.axil_agent.sqr);
            wr = fa_reg_write_seq::type_id::create("wr");
            wr.addr = 8'h00; wr.data = 32'h1; wr.start(env.axil_agent.sqr);
        end

        `uvm_info("TEST", "Coverage closure test complete", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass

// --- COV03: Comprehensive All-in-One Test ---
class fa_comprehensive_test extends fa_base_test;
    `uvm_component_utils(fa_comprehensive_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        shortint q[][], k[][], v[][];
        fa_reg_reset_seq       reset_seq;
        fa_reg_stress_seq      stress_seq;
        fa_config_and_start_seq cfg_seq;
        fa_poll_done_seq       poll_seq;

        phase.raise_objection(this);
        `uvm_info("TEST", "COMP: Comprehensive all-in-one verification test", UVM_LOW)

        // Phase 1: Register verification
        `uvm_info("TEST", "Phase 1: Register verification", UVM_LOW)
        reset_seq = fa_reg_reset_seq::type_id::create("reset");
        reset_seq.start(env.axil_agent.sqr);

        stress_seq = fa_reg_stress_seq::type_id::create("stress");
        stress_seq.num_rounds = 10;
        stress_seq.start(env.axil_agent.sqr);

        // Phase 2: End-to-end causal attention
        `uvm_info("TEST", "Phase 2: End-to-end causal attention", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_attention(1, q, k, v);

        // Phase 3: End-to-end non-causal attention
        `uvm_info("TEST", "Phase 3: End-to-end non-causal attention", UVM_LOW)
        gen_random_matrix(q, 256, 64, 256);
        gen_random_matrix(k, 256, 64, 256);
        gen_random_matrix(v, 256, 64, 256);
        run_attention(0, q, k, v);

        // Phase 4: DMA verification
        `uvm_info("TEST", "Phase 4: DMA back-to-back", UVM_LOW)
        gen_random_matrix(q, 256, 64, 512);
        gen_random_matrix(k, 256, 64, 512);
        gen_random_matrix(v, 256, 64, 512);

        preload_matrix(Q_BASE, q);
        preload_matrix(K_BASE, k);
        preload_matrix(V_BASE, v);

        cfg_seq = fa_config_and_start_seq::type_id::create("cfg_comp");
        cfg_seq.q_base = Q_BASE; cfg_seq.k_base = K_BASE;
        cfg_seq.v_base = V_BASE; cfg_seq.o_base = O_BASE;
        cfg_seq.causal_en = 1;
        cfg_seq.start(env.axil_agent.sqr);

        poll_seq = fa_poll_done_seq::type_id::create("poll_comp");
        poll_seq.start(env.axil_agent.sqr);

        if (poll_seq.done)
            `uvm_info("TEST", $sformatf("Comprehensive: completed in %0d cycles", poll_seq.cycles), UVM_LOW)
        else
            `uvm_error("TEST", "Comprehensive test: computation timeout")

        env.coverage.sample_perf(poll_seq.cycles);

        `uvm_info("TEST", "=== Comprehensive test COMPLETE ===", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
