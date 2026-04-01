// ============================================================
// FlashAttention Bonus Scoreboard with Enhanced Golden Model
// Supports: causal mask, padding mask, multi-head
// ============================================================

class fa_bonus_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fa_bonus_scoreboard)

    int seq_len = 256;
    int head_dim = 64;
    bit causal_en;
    int valid_len;

    shortint q_data[][];
    shortint k_data[][];
    shortint v_data[][];
    shortint golden_o[][];
    shortint dut_o[][];

    real mean_abs_error;
    real max_abs_error;
    int  num_checks;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void compute_golden();
        real q_f[][], k_f[][], v_f[][];
        real scale;
        real score, row_max, row_sum, p_val;

        scale = 1.0 / $sqrt(real'(head_dim));
        golden_o = new[seq_len];

        q_f = new[seq_len]; k_f = new[seq_len]; v_f = new[seq_len];
        for (int i = 0; i < seq_len; i++) begin
            q_f[i] = new[head_dim]; k_f[i] = new[head_dim]; v_f[i] = new[head_dim];
            golden_o[i] = new[head_dim];
        end

        for (int i = 0; i < seq_len; i++)
            for (int j = 0; j < head_dim; j++) begin
                q_f[i][j] = real'(q_data[i][j]) / 256.0;
                k_f[i][j] = real'(k_data[i][j]) / 256.0;
                v_f[i][j] = real'(v_data[i][j]) / 256.0;
            end

        for (int i = 0; i < seq_len; i++) begin
            real o_row[];
            o_row = new[head_dim];
            for (int d = 0; d < head_dim; d++) o_row[d] = 0.0;

            row_max = -1e30;
            for (int j = 0; j < seq_len; j++) begin
                if (causal_en && j > i) score = -128.0;
                else if (valid_len > 0 && j >= valid_len) score = -128.0;
                else begin
                    score = 0.0;
                    for (int k = 0; k < head_dim; k++)
                        score = score + q_f[i][k] * k_f[j][k];
                    score = score * scale;
                end
                if (score > row_max) row_max = score;
            end

            row_sum = 0.0;
            for (int j = 0; j < seq_len; j++) begin
                if (causal_en && j > i) score = -128.0;
                else if (valid_len > 0 && j >= valid_len) score = -128.0;
                else begin
                    score = 0.0;
                    for (int k = 0; k < head_dim; k++)
                        score = score + q_f[i][k] * k_f[j][k];
                    score = score * scale;
                end
                row_sum = row_sum + $exp(score - row_max);
            end

            for (int j = 0; j < seq_len; j++) begin
                if (causal_en && j > i) score = -128.0;
                else if (valid_len > 0 && j >= valid_len) score = -128.0;
                else begin
                    score = 0.0;
                    for (int k = 0; k < head_dim; k++)
                        score = score + q_f[i][k] * k_f[j][k];
                    score = score * scale;
                end
                p_val = $exp(score - row_max) / row_sum;
                for (int d = 0; d < head_dim; d++)
                    o_row[d] = o_row[d] + p_val * v_f[j][d];
            end

            for (int d = 0; d < head_dim; d++)
                golden_o[i][d] = shortint'($rtoi(o_row[d] * 256.0));
        end
    endfunction

    function void check_result(string test_name);
        real dut_val, gold_val, abs_err;
        mean_abs_error = 0.0;
        max_abs_error  = 0.0;
        num_checks     = 0;

        for (int i = 0; i < seq_len; i++)
            for (int j = 0; j < head_dim; j++) begin
                dut_val  = real'(dut_o[i][j]) / 256.0;
                gold_val = real'(golden_o[i][j]) / 256.0;
                abs_err  = (dut_val > gold_val) ? (dut_val - gold_val) : (gold_val - dut_val);
                mean_abs_error = mean_abs_error + abs_err;
                if (abs_err > max_abs_error) max_abs_error = abs_err;
                num_checks++;
            end

        mean_abs_error = mean_abs_error / real'(num_checks);

        if (max_abs_error < 1.0)
            `uvm_info(test_name, $sformatf("PASS mean=%.6f max=%.6f", mean_abs_error, max_abs_error), UVM_LOW)
        else
            `uvm_error(test_name, $sformatf("FAIL mean=%.6f max=%.6f", mean_abs_error, max_abs_error))
    endfunction
endclass
