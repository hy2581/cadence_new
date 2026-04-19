// ============================================================
// FlashAttention Bonus Coverage Collector
// Covers all 9 bonus features + performance + VP tracking
// ============================================================

class fa_bonus_coverage extends uvm_subscriber #(axi4_lite_txn);
    `uvm_component_utils(fa_bonus_coverage)

    bit causal_en, padding_en, dropout_en, stream_mode;
    bit [2:0] data_fmt;
    bit [7:0] num_heads;
    bit task_queue_en;
    int cycle_count;
    int rd_bw_int, wr_bw_int;

    covergroup bonus_config_cg;
        causal_cp:    coverpoint causal_en    { bins on = {1}; bins off = {0}; }
        padding_cp:   coverpoint padding_en   { bins on = {1}; bins off = {0}; }
        dropout_cp:   coverpoint dropout_en   { bins on = {1}; bins off = {0}; }
        stream_cp:    coverpoint stream_mode  { bins on = {1}; bins off = {0}; }
        data_fmt_cp:  coverpoint data_fmt     {
            bins q8_8  = {0};
            bins q6_10 = {1};
            bins q4_12 = {2};
            bins bf16  = {3};
            bins int8  = {4};
        }
        num_heads_cp: coverpoint num_heads    {
            bins single = {1};
            bins multi  = {[2:8]};
        }
        task_q_cp:    coverpoint task_queue_en { bins on = {1}; bins off = {0}; }
        causal_x_pad: cross causal_cp, padding_cp;
    endgroup

    covergroup bonus_reg_cg with function sample(bit [7:0] addr, bit is_write);
        addr_cp: coverpoint addr {
            bins ctrl       = {8'h00};
            bins status     = {8'h04};
            bins cfg        = {8'h08};
            bins seq_len    = {8'h0C};
            bins num_heads  = {8'h10};
            bins q_base     = {[8'h14:8'h18]};
            bins k_base     = {[8'h1C:8'h20]};
            bins v_base     = {[8'h24:8'h28]};
            bins o_base     = {[8'h2C:8'h30]};
            bins stride     = {8'h34};
            bins neg_large  = {8'h38};
            bins scale      = {8'h3C};
            bins cycles     = {8'h40};
            bins pad_len    = {8'h44};
            bins dropout    = {8'h48};
            bins task_ctrl  = {8'h4C};
            bins data_fmt   = {8'h50};
            bins head_stride = {8'h54};
        }
        rw_cp: coverpoint is_write { bins read = {0}; bins write = {1}; }
    endgroup

    covergroup bonus_perf_cg;
        cycles_cp: coverpoint cycle_count {
            bins fast    = {[0:200000]};
            bins normal  = {[200001:400000]};
            bins slow    = {[400001:600000]};
            bins very_slow = {[600001:$]};
        }
    endgroup

    covergroup bonus_perf_detail_cg;
        rd_bw_cp: coverpoint rd_bw_int {
            bins low   = {[0:100]};
            bins med   = {[101:200]};
            bins high  = {[201:$]};
        }
        wr_bw_cp: coverpoint wr_bw_int {
            bins low   = {[0:50]};
            bins med   = {[51:100]};
            bins high  = {[101:$]};
        }
    endgroup

    string vp_hits[string];
    covergroup bonus_vp_cg;
        option.per_instance = 1;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        bonus_config_cg = new();
        bonus_reg_cg = new();
        bonus_perf_cg = new();
        bonus_perf_detail_cg = new();
        bonus_vp_cg = new();
    endfunction

    function void write(axi4_lite_txn t);
        bonus_reg_cg.sample(t.addr, t.is_write);
    endfunction

    function void sample_config(bit _causal, bit _padding, bit _dropout, bit _stream,
                                bit [2:0] _fmt, bit [7:0] _heads, bit _tq);
        causal_en    = _causal;
        padding_en   = _padding;
        dropout_en   = _dropout;
        stream_mode  = _stream;
        data_fmt     = _fmt;
        num_heads    = _heads;
        task_queue_en = _tq;
        bonus_config_cg.sample();
    endfunction

    function void sample_perf(int cycles);
        cycle_count = cycles;
        bonus_perf_cg.sample();
    endfunction

    function void sample_perf_detail(real _rd_bw, real _wr_bw, real _util);
        rd_bw_int = int'(_rd_bw);
        wr_bw_int = int'(_wr_bw);
        bonus_perf_detail_cg.sample();
    endfunction

    function void sample_vp(string vp_name);
        vp_hits[vp_name] = "hit";
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("BCOV", $sformatf("Coverage: config=%.1f%%  reg=%.1f%%  perf=%.1f%%",
            bonus_config_cg.get_coverage(),
            bonus_reg_cg.get_coverage(),
            bonus_perf_cg.get_coverage()), UVM_LOW)
    endfunction
endclass
