// FlashAttention Functional Coverage Collector
class fa_coverage extends uvm_subscriber #(axi4_lite_txn);
    `uvm_component_utils(fa_coverage)

    // Coverage data
    bit causal_en;
    bit [2:0] data_pattern;  // 0=zero, 1=max, 2=rand_pos, 3=rand_neg, 4=mixed
    int test_count;

    covergroup fa_config_cg;
        causal_cp: coverpoint causal_en {
            bins enabled  = {1};
            bins disabled = {0};
        }
    endgroup

    covergroup fa_data_cg;
        pattern_cp: coverpoint data_pattern {
            bins all_zero   = {0};
            bins all_max    = {1};
            bins rand_pos   = {2};
            bins rand_neg   = {3};
            bins mixed      = {4};
        }
    endgroup

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
        }
        rw_cp: coverpoint is_write {
            bins read  = {0};
            bins write = {1};
        }
        addr_x_rw: cross addr_cp, rw_cp;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        fa_config_cg = new();
        fa_data_cg = new();
        fa_reg_cg = new();
    endfunction

    function void write(axi4_lite_txn t);
        fa_reg_cg.sample(t.addr, t.is_write);
    endfunction

    function void sample_config(bit _causal_en);
        causal_en = _causal_en;
        fa_config_cg.sample();
    endfunction

    function void sample_data(bit [2:0] pattern);
        data_pattern = pattern;
        fa_data_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf(
            "Coverage: config=%.1f%%, data=%.1f%%, reg=%.1f%%",
            fa_config_cg.get_coverage(), fa_data_cg.get_coverage(),
            fa_reg_cg.get_coverage()), UVM_LOW)
    endfunction
endclass
