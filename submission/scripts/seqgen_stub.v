// Temporary SEQGEN behavioral model for gate-level simulation of generic netlists.
// This model is used only when synthesized netlists contain \**SEQGEN** cells.
module \**SEQGEN** (clear, preset, next_state, clocked_on, data_in, enable, Q,
                    synch_clear, synch_preset, synch_toggle, synch_enable);
    input clear, preset, next_state, clocked_on, data_in, enable;
    input synch_clear, synch_preset, synch_toggle, synch_enable;
    output reg Q;

    always @(posedge clocked_on or posedge clear or posedge preset) begin
        if (clear) begin
            Q <= 1'b0;
        end else if (preset) begin
            Q <= 1'b1;
        end else begin
            if (synch_clear) Q <= 1'b0;
            else if (synch_preset) Q <= 1'b1;
            else if (synch_toggle) Q <= ~Q;
            else if (synch_enable) Q <= next_state;
            else if (enable) Q <= data_in;
        end
    end
endmodule

// Temporary SELECT_OP behavioral model for generic mapped netlists.
module SELECT_OP (
    DATA1, DATA2, DATA3, DATA4, DATA5,
    DATA6, DATA7, DATA8, DATA9, DATA10,
    DATA11, DATA12, DATA13, DATA14, DATA15,
    CONTROL1, CONTROL2, CONTROL3, CONTROL4, CONTROL5,
    CONTROL6, CONTROL7, CONTROL8, CONTROL9, CONTROL10,
    CONTROL11, CONTROL12, CONTROL13, CONTROL14, CONTROL15,
    Z
);
    input DATA1, DATA2, DATA3, DATA4, DATA5;
    input DATA6, DATA7, DATA8, DATA9, DATA10;
    input DATA11, DATA12, DATA13, DATA14, DATA15;
    input CONTROL1, CONTROL2, CONTROL3, CONTROL4, CONTROL5;
    input CONTROL6, CONTROL7, CONTROL8, CONTROL9, CONTROL10;
    input CONTROL11, CONTROL12, CONTROL13, CONTROL14, CONTROL15;
    output Z;

    assign Z = CONTROL1  ? DATA1  :
               CONTROL2  ? DATA2  :
               CONTROL3  ? DATA3  :
               CONTROL4  ? DATA4  :
               CONTROL5  ? DATA5  :
               CONTROL6  ? DATA6  :
               CONTROL7  ? DATA7  :
               CONTROL8  ? DATA8  :
               CONTROL9  ? DATA9  :
               CONTROL10 ? DATA10 :
               CONTROL11 ? DATA11 :
               CONTROL12 ? DATA12 :
               CONTROL13 ? DATA13 :
               CONTROL14 ? DATA14 :
               CONTROL15 ? DATA15 : 1'b0;
endmodule
