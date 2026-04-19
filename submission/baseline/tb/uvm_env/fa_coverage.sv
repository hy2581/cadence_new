// FlashAttention Functional Coverage — Comprehensive
class fa_coverage extends uvm_subscriber #(axi4_lite_txn);
    `uvm_component_utils(fa_coverage)

    // Configuration state
    bit causal_en;
    bit [2:0] data_pattern;
    int test_count;

    // DMA transfer tracking
    int dma_rd_count, dma_wr_count;
    int total_rd_bytes, total_wr_bytes;

    // Performance tracking
    int exec_cycles;
    real throughput_elem_per_cycle;

    // AXI4 burst tracking
    int axi_rd_bursts, axi_wr_bursts;
    int axi_rd_bytes,  axi_wr_bytes;

    // Verification completeness tracking
    bit vp_zero_tested, vp_random_tested, vp_causal_tested;
    bit vp_boundary_tested, vp_identity_tested, vp_maxval_tested;
    bit vp_nocausal_tested;
    bit dma_integrity_tested, dma_backtoback_tested;
    bit reg_reset_tested, reg_rw_tested, reg_stress_tested, reg_ral_tested;
    bit axi_protocol_tested;
    bit perf_tested;

    // --- Configuration Coverage ---
    covergroup fa_config_cg;
        causal_cp: coverpoint causal_en {
            bins enabled  = {1};
            bins disabled = {0};
        }
        pattern_cp: coverpoint data_pattern {
            bins all_zero   = {0};
            bins all_max    = {1};
            bins rand_pos   = {2};
            bins rand_neg   = {3};
            bins mixed      = {4};
            bins identity   = {5};
            bins boundary   = {6};
        }
        config_x_data: cross causal_cp, pattern_cp;
    endgroup

    // --- Register Access Coverage ---
    covergroup fa_reg_cg with function sample(bit [7:0] addr, bit is_write);
        addr_cp: coverpoint addr {
            bins ctrl       = {8'h00};
            bins status     = {8'h04};
            bins cfg        = {8'h08};
            bins q_base_l   = {8'h14};
            bins q_base_h   = {8'h18};
            bins k_base_l   = {8'h1C};
            bins k_base_h   = {8'h20};
            bins v_base_l   = {8'h24};
            bins v_base_h   = {8'h28};
            bins o_base_l   = {8'h2C};
            bins o_base_h   = {8'h30};
            bins stride     = {8'h34};
            bins neg_large  = {8'h38};
            bins scale      = {8'h3C};
            bins cycles     = {8'h40};
            bins unmapped   = default;
        }
        rw_cp: coverpoint is_write {
            bins read  = {0};
            bins write = {1};
        }
        addr_x_rw: cross addr_cp, rw_cp;
    endgroup

    // --- Register Value Coverage ---
    covergroup fa_reg_val_cg with function sample(bit [7:0] addr, bit [31:0] data);
        ctrl_val: coverpoint data[2:0] iff (addr == 8'h00) {
            bins start_only   = {3'b001};
            bins reset_only   = {3'b010};
            bins irq_en_only  = {3'b100};
            bins start_irq    = {3'b101};
        }
        cfg_val: coverpoint data[0] iff (addr == 8'h08) {
            bins causal_off = {0};
            bins causal_on  = {1};
        }
        stride_val: coverpoint data iff (addr == 8'h34) {
            bins default_stride = {32'd128};
            bins other          = default;
        }
        scale_val: coverpoint data[15:0] iff (addr == 8'h3C) {
            bins default_scale = {16'h0020};
            bins other         = default;
        }
    endgroup

    // --- DMA Transfer Coverage ---
    covergroup fa_dma_cg with function sample(bit is_write, int byte_count);
        dir_cp: coverpoint is_write {
            bins rd  = {0};
            bins wr  = {1};
        }
        size_cp: coverpoint byte_count {
            bins sz_s  = {[1:256]};
            bins sz_m  = {[257:1024]};
            bins sz_l  = {[1025:4096]};
            bins sz_xl = {[4097:$]};
        }
        dir_x_size: cross dir_cp, size_cp;
    endgroup

    // --- AXI4 Burst Transaction Coverage ---
    covergroup fa_axi_burst_cg with function sample(bit is_write, bit [7:0] len,
                                                     bit [2:0] size, bit [1:0] burst,
                                                     int byte_count);
        dir_cp: coverpoint is_write {
            bins rd  = {0};
            bins wr  = {1};
        }
        len_cp: coverpoint len {
            bins single      = {0};
            bins short_burst = {[1:3]};
            bins mid_burst   = {[4:15]};
            bins long_burst  = {[16:$]};
        }
        size_cp: coverpoint size {
            bins byte_1  = {3'd0};
            bins byte_2  = {3'd1};
            bins byte_4  = {3'd2};
            bins byte_8  = {3'd3};
            bins byte_16 = {3'd4};
        }
        burst_cp: coverpoint burst {
            bins fixed = {2'b00};
            bins incr  = {2'b01};
            bins wrap  = {2'b10};
        }
        bytes_cp: coverpoint byte_count {
            bins sz_sm  = {[1:128]};
            bins sz_md  = {[129:1024]};
            bins sz_lg  = {[1025:$]};
        }
        dir_x_len:  cross dir_cp, len_cp;
        dir_x_size: cross dir_cp, size_cp;
    endgroup

    // --- Performance Coverage ---
    covergroup fa_perf_cg with function sample(int cycles);
        cycle_cp: coverpoint cycles {
            bins fast   = {[0:200000]};
            bins normal = {[200001:300000]};
            bins slow   = {[300001:500000]};
            bins vslow  = {[500001:$]};
        }
    endgroup

    // --- Performance Metrics Coverage ---
    covergroup fa_perf_detail_cg with function sample(real rd_bw, real wr_bw, real util);
        rd_bw_cp: coverpoint int'(rd_bw) {
            bins bw_lo  = {[0:1000]};
            bins bw_md  = {[1001:5000]};
            bins bw_hi  = {[5001:10000]};
            bins bw_vh  = {[10001:$]};
        }
        wr_bw_cp: coverpoint int'(wr_bw) {
            bins bw_lo  = {[0:50]};
            bins bw_md  = {[51:200]};
            bins bw_hi  = {[201:$]};
        }
        util_cp: coverpoint int'(util * 100) {
            bins ut_lo  = {[0:25]};
            bins ut_md  = {[26:50]};
            bins ut_hi  = {[51:75]};
            bins ut_vh  = {[76:100]};
        }
    endgroup

    // --- Verification Point Completeness ---
    covergroup fa_vp_cg;
        zero_cp:      coverpoint vp_zero_tested     { bins done = {1}; }
        random_cp:    coverpoint vp_random_tested    { bins done = {1}; }
        causal_cp:    coverpoint vp_causal_tested    { bins done = {1}; }
        nocausal_cp:  coverpoint vp_nocausal_tested  { bins done = {1}; }
        boundary_cp:  coverpoint vp_boundary_tested  { bins done = {1}; }
        identity_cp:  coverpoint vp_identity_tested  { bins done = {1}; }
        maxval_cp:    coverpoint vp_maxval_tested    { bins done = {1}; }
        dma_int_cp:   coverpoint dma_integrity_tested  { bins done = {1}; }
        dma_b2b_cp:   coverpoint dma_backtoback_tested { bins done = {1}; }
        reg_rst_cp:   coverpoint reg_reset_tested    { bins done = {1}; }
        reg_rw_cp:    coverpoint reg_rw_tested       { bins done = {1}; }
        reg_str_cp:   coverpoint reg_stress_tested   { bins done = {1}; }
        reg_ral_cp:   coverpoint reg_ral_tested      { bins done = {1}; }
        axi_prot_cp:  coverpoint axi_protocol_tested { bins done = {1}; }
        perf_cp:      coverpoint perf_tested         { bins done = {1}; }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        fa_config_cg     = new();
        fa_reg_cg        = new();
        fa_reg_val_cg    = new();
        fa_dma_cg        = new();
        fa_axi_burst_cg  = new();
        fa_perf_cg       = new();
        fa_perf_detail_cg = new();
        fa_vp_cg         = new();
        dma_rd_count = 0; dma_wr_count = 0;
        axi_rd_bursts = 0; axi_wr_bursts = 0;
    endfunction

    function void write(axi4_lite_txn t);
        fa_reg_cg.sample(t.addr, t.is_write);
        if (t.is_write)
            fa_reg_val_cg.sample(t.addr, t.data);
    endfunction

    function void sample_config(bit _causal_en);
        causal_en = _causal_en;
        fa_config_cg.sample();
    endfunction

    function void sample_data(bit [2:0] pattern);
        data_pattern = pattern;
        fa_config_cg.sample();
    endfunction

    function void sample_dma(bit is_write, int byte_count);
        fa_dma_cg.sample(is_write, byte_count);
        if (is_write) begin
            dma_wr_count++;
            total_wr_bytes += byte_count;
        end else begin
            dma_rd_count++;
            total_rd_bytes += byte_count;
        end
    endfunction

    function void sample_axi_burst(axi4_burst_txn txn);
        fa_axi_burst_cg.sample(txn.is_write, txn.len, txn.size, txn.burst, txn.byte_count);
        if (txn.is_write) begin
            axi_wr_bursts++;
            axi_wr_bytes += txn.byte_count;
        end else begin
            axi_rd_bursts++;
            axi_rd_bytes += txn.byte_count;
        end
    endfunction

    function void sample_perf(int cycles);
        exec_cycles = cycles;
        fa_perf_cg.sample(cycles);
    endfunction

    function void sample_perf_detail(real rd_bw_mbps, real wr_bw_mbps, real bus_util);
        fa_perf_detail_cg.sample(rd_bw_mbps, wr_bw_mbps, bus_util);
    endfunction

    function void sample_vp(string vp_name);
        case (vp_name)
            "zero":       vp_zero_tested = 1;
            "random":     vp_random_tested = 1;
            "causal":     vp_causal_tested = 1;
            "nocausal":   vp_nocausal_tested = 1;
            "boundary":   vp_boundary_tested = 1;
            "identity":   vp_identity_tested = 1;
            "maxval":     vp_maxval_tested = 1;
            "dma_int":    dma_integrity_tested = 1;
            "dma_b2b":    dma_backtoback_tested = 1;
            "reg_reset":  reg_reset_tested = 1;
            "reg_rw":     reg_rw_tested = 1;
            "reg_stress": reg_stress_tested = 1;
            "reg_ral":    reg_ral_tested = 1;
            "axi_prot":   axi_protocol_tested = 1;
            "perf":       perf_tested = 1;
        endcase
        fa_vp_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf(
            "Coverage Summary:\n  config=%.1f%%  reg_access=%.1f%%  reg_val=%.1f%%\n  dma=%.1f%%  axi_burst=%.1f%%  perf=%.1f%%\n  perf_detail=%.1f%%  vp_complete=%.1f%%",
            fa_config_cg.get_coverage(), fa_reg_cg.get_coverage(),
            fa_reg_val_cg.get_coverage(), fa_dma_cg.get_coverage(),
            fa_axi_burst_cg.get_coverage(), fa_perf_cg.get_coverage(),
            fa_perf_detail_cg.get_coverage(), fa_vp_cg.get_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf(
            "DMA Stats: rd=%0d (%0d B), wr=%0d (%0d B)",
            dma_rd_count, total_rd_bytes, dma_wr_count, total_wr_bytes), UVM_LOW)
        `uvm_info("COV", $sformatf(
            "AXI4 Stats: rd_bursts=%0d (%0d B), wr_bursts=%0d (%0d B)",
            axi_rd_bursts, axi_rd_bytes, axi_wr_bursts, axi_wr_bytes), UVM_LOW)
    endfunction
endclass

// AXI4 burst coverage subscriber (connects to axi4_mem_monitor)
class fa_axi_cov_sub extends uvm_subscriber #(axi4_burst_txn);
    `uvm_component_utils(fa_axi_cov_sub)
    fa_coverage cov_ref;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void write(axi4_burst_txn t);
        if (cov_ref != null)
            cov_ref.sample_axi_burst(t);
    endfunction
endclass
