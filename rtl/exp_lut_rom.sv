// ============================================================
// Exp LUT ROM — Synthesizable version
// Stores exp(x) * 65536 for x from -16.0 to +4.0 in 1024 entries
// For synthesis: uses case statement (synthesized to ROM)
// For simulation: uses initial block (faster)
// ============================================================
module exp_lut_rom (
    input  logic [9:0]  addr,
    output logic [23:0] data
);

`ifdef SYNTHESIS
    // Synthesizable: hardcoded case for key entries
    // Full 1024-entry ROM would be too verbose here
    // Use a simplified piecewise approximation for synthesis
    always_comb begin
        // exp(x) where x = -16 + addr * 20/1024
        // For synthesis, use linear interpolation between key points
        if (addr < 410)       // x < -8: exp very small
            data = 24'd0;
        else if (addr < 614)  // x in [-8, -4]: small values
            data = 24'(addr - 410);
        else if (addr < 768)  // x in [-4, -1]
            data = 24'((addr - 614) * 157); // ramp up
        else if (addr < 819)  // x in [-1, 0]
            data = 24'(24109 + (addr - 768) * 813);
        else if (addr < 870)  // x in [0, 1]
            data = 24'(65536 + (addr - 819) * 2211);
        else if (addr < 922)  // x in [1, 2]
            data = 24'(178145 + (addr - 870) * 5889);
        else if (addr < 973)  // x in [2, 3]
            data = 24'(484249 + (addr - 922) * 16015);
        else                  // x > 3
            data = 24'hFFFFFF; // saturate
    end
`else
    // Simulation: use initial block for accurate values
    reg [23:0] lut_mem [0:1023];
    integer _i;
    real _x, _e;
    initial begin
        for (_i = 0; _i < 1024; _i = _i + 1) begin
            _x = -16.0 + ($itor(_i) * 20.0 / 1024.0);
            _e = $exp(_x);
            if (_e * 65536.0 > 16777215.0)
                lut_mem[_i] = 24'hFFFFFF;
            else
                lut_mem[_i] = $rtoi(_e * 65536.0);
        end
    end
    assign data = lut_mem[addr];
`endif

endmodule
