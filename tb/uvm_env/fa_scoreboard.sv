// FlashAttention Scoreboard with Golden Model
class fa_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fa_scoreboard)

    // Configuration
    int seq_len = 256;
    int head_dim = 64;
    bit causal_en;

    // Golden model data
    shortint q_data[][];
    shortint k_data[][];
    shortint v_data[][];
    shortint golden_o[][];
    shortint dut_o[][];

    // Error statistics
    real mean_abs_error;
    real max_abs_error;
    int  num_checks;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Compute golden reference (FP64 precision)
    function void compute_golden();
        real q_f[][], k_f[][], v_f[][];
        real s_f[][], p_f[][], o_f[][];
        real scale;

        scale = 1.0 / $sqrt(real'(head_dim));

        // Allocate
        q_f = new[seq_len]; k_f = new[seq_len]; v_f = new[seq_len];
        s_f = new[seq_len]; p_f = new[seq_len]; o_f = new[seq_len];
        golden_o = new[seq_len];

        for (int i = 0; i < seq_len; i++) begin
            q_f[i] = new[head_dim]; k_f[i] = new[head_dim]; v_f[i] = new[head_dim];
            s_f[i] = new[seq_len]; p_f[i] = new[seq_len]; o_f[i] = new[head_dim];
            golden_o[i] = new[head_dim];
        end

        // Q8.8 → float
        for (int i = 0; i < seq_len; i++)
            for (int j = 0; j < head_dim; j++) begin
                q_f[i][j] = real'(q_data[i][j]) / 256.0;
                k_f[i][j] = real'(k_data[i][j]) / 256.0;
                v_f[i][j] = real'(v_data[i][j]) / 256.0;
            end

        // S = Q * K^T * scale, softmax, O = P * V
        for (int i = 0; i < seq_len; i++) begin
            real row_max, row_sum;

            // Compute scores
            row_max = -1e30;
            for (int j = 0; j < seq_len; j++) begin
                s_f[i][j] = 0;
                for (int k = 0; k < head_dim; k++)
                    s_f[i][j] += q_f[i][k] * k_f[j][k];
                s_f[i][j] *= scale;
                if (causal_en && j > i) s_f[i][j] = -1e9;
                if (s_f[i][j] > row_max) row_max = s_f[i][j];
            end

            // Softmax
            row_sum = 0;
            for (int j = 0; j < seq_len; j++) begin
                p_f[i][j] = $exp(s_f[i][j] - row_max);
                row_sum += p_f[i][j];
            end
            for (int j = 0; j < seq_len; j++)
                p_f[i][j] /= row_sum;

            // O = P * V
            for (int j = 0; j < head_dim; j++) begin
                o_f[i][j] = 0;
                for (int k = 0; k < seq_len; k++)
                    o_f[i][j] += p_f[i][k] * v_f[k][j];
                golden_o[i][j] = shortint'($rtoi(o_f[i][j] * 256.0));
            end
        end

        `uvm_info("GOLDEN", "Golden model computation complete", UVM_MEDIUM)
    endfunction

    // Compare DUT output with golden
    function void check_results();
        real abs_err;
        real total_err = 0;
        int  count = 0;

        max_abs_error = 0;

        for (int i = 0; i < seq_len; i++) begin
            for (int j = 0; j < head_dim; j++) begin
                real dut_val  = real'(dut_o[i][j]) / 256.0;
                real gold_val = real'(golden_o[i][j]) / 256.0;
                abs_err = (dut_val > gold_val) ? (dut_val - gold_val) : (gold_val - dut_val);
                total_err += abs_err;
                if (abs_err > max_abs_error) max_abs_error = abs_err;
                count++;
            end
        end

        mean_abs_error = total_err / real'(count);
        num_checks = count;

        `uvm_info("SCORE", $sformatf(
            "Error stats: mean_abs=%.6f, max_abs=%.6f (over %0d elements)",
            mean_abs_error, max_abs_error, count), UVM_LOW)

        if (max_abs_error > 1.0)
            `uvm_error("SCORE", $sformatf("max_abs_error %.6f exceeds threshold", max_abs_error))
        else
            `uvm_info("SCORE", "PASS: Error within acceptable limits", UVM_LOW)
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCORE", $sformatf(
            "Final: mean_abs_error=%.6f, max_abs_error=%.6f, checks=%0d",
            mean_abs_error, max_abs_error, num_checks), UVM_LOW)
    endfunction
endclass
