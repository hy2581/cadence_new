// ============================================================
// Reciprocal Approximation Unit (Newton-Raphson)
// Computes 1/x for unsigned fixed-point input
// Method: LUT initial guess + 2 Newton-Raphson iterations
//   x_{n+1} = x_n * (2 - d * x_n)
// ============================================================
module reciprocal_unit #(
    parameter WIDTH     = 40,
    parameter FRAC_BITS = 16
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     d_in,          // unsigned fixed-point denominator
    output logic                 valid_out,
    output logic [WIDTH-1:0]     recip_out       // unsigned fixed-point ≈ 1/d_in
);

    // --- LUT for initial guess ---
    // Normalize d_in to [0.5, 1.0) by finding leading one, then use top 8 bits as LUT index
    // LUT stores 1/x * 2^FRAC_BITS for normalized x

    localparam LUT_DEPTH = 256;

`ifdef SYNTHESIS
    // Synthesizable LUT: combinational ROM
    function automatic [WIDTH-1:0] recip_lut_lookup(input [7:0] idx);
        case (idx)
            8'd0: recip_lut_lookup = 40'd131072;
            8'd1: recip_lut_lookup = 40'd130562;
            8'd2: recip_lut_lookup = 40'd130056;
            8'd3: recip_lut_lookup = 40'd129554;
            8'd4: recip_lut_lookup = 40'd129056;
            8'd5: recip_lut_lookup = 40'd128561;
            8'd6: recip_lut_lookup = 40'd128070;
            8'd7: recip_lut_lookup = 40'd127583;
            8'd8: recip_lut_lookup = 40'd127100;
            8'd9: recip_lut_lookup = 40'd126620;
            8'd10: recip_lut_lookup = 40'd126144;
            8'd11: recip_lut_lookup = 40'd125672;
            8'd12: recip_lut_lookup = 40'd125203;
            8'd13: recip_lut_lookup = 40'd124738;
            8'd14: recip_lut_lookup = 40'd124276;
            8'd15: recip_lut_lookup = 40'd123817;
            8'd16: recip_lut_lookup = 40'd123362;
            8'd17: recip_lut_lookup = 40'd122910;
            8'd18: recip_lut_lookup = 40'd122461;
            8'd19: recip_lut_lookup = 40'd122016;
            8'd20: recip_lut_lookup = 40'd121574;
            8'd21: recip_lut_lookup = 40'd121135;
            8'd22: recip_lut_lookup = 40'd120699;
            8'd23: recip_lut_lookup = 40'd120267;
            8'd24: recip_lut_lookup = 40'd119837;
            8'd25: recip_lut_lookup = 40'd119411;
            8'd26: recip_lut_lookup = 40'd118987;
            8'd27: recip_lut_lookup = 40'd118567;
            8'd28: recip_lut_lookup = 40'd118149;
            8'd29: recip_lut_lookup = 40'd117735;
            8'd30: recip_lut_lookup = 40'd117323;
            8'd31: recip_lut_lookup = 40'd116914;
            8'd32: recip_lut_lookup = 40'd116508;
            8'd33: recip_lut_lookup = 40'd116105;
            8'd34: recip_lut_lookup = 40'd115705;
            8'd35: recip_lut_lookup = 40'd115307;
            8'd36: recip_lut_lookup = 40'd114912;
            8'd37: recip_lut_lookup = 40'd114520;
            8'd38: recip_lut_lookup = 40'd114131;
            8'd39: recip_lut_lookup = 40'd113744;
            8'd40: recip_lut_lookup = 40'd113360;
            8'd41: recip_lut_lookup = 40'd112978;
            8'd42: recip_lut_lookup = 40'd112599;
            8'd43: recip_lut_lookup = 40'd112222;
            8'd44: recip_lut_lookup = 40'd111848;
            8'd45: recip_lut_lookup = 40'd111477;
            8'd46: recip_lut_lookup = 40'd111107;
            8'd47: recip_lut_lookup = 40'd110741;
            8'd48: recip_lut_lookup = 40'd110376;
            8'd49: recip_lut_lookup = 40'd110015;
            8'd50: recip_lut_lookup = 40'd109655;
            8'd51: recip_lut_lookup = 40'd109298;
            8'd52: recip_lut_lookup = 40'd108943;
            8'd53: recip_lut_lookup = 40'd108590;
            8'd54: recip_lut_lookup = 40'd108240;
            8'd55: recip_lut_lookup = 40'd107892;
            8'd56: recip_lut_lookup = 40'd107546;
            8'd57: recip_lut_lookup = 40'd107203;
            8'd58: recip_lut_lookup = 40'd106861;
            8'd59: recip_lut_lookup = 40'd106522;
            8'd60: recip_lut_lookup = 40'd106185;
            8'd61: recip_lut_lookup = 40'd105850;
            8'd62: recip_lut_lookup = 40'd105517;
            8'd63: recip_lut_lookup = 40'd105186;
            8'd64: recip_lut_lookup = 40'd104858;
            8'd65: recip_lut_lookup = 40'd104531;
            8'd66: recip_lut_lookup = 40'd104206;
            8'd67: recip_lut_lookup = 40'd103884;
            8'd68: recip_lut_lookup = 40'd103563;
            8'd69: recip_lut_lookup = 40'd103244;
            8'd70: recip_lut_lookup = 40'd102928;
            8'd71: recip_lut_lookup = 40'd102613;
            8'd72: recip_lut_lookup = 40'd102300;
            8'd73: recip_lut_lookup = 40'd101989;
            8'd74: recip_lut_lookup = 40'd101680;
            8'd75: recip_lut_lookup = 40'd101373;
            8'd76: recip_lut_lookup = 40'd101068;
            8'd77: recip_lut_lookup = 40'd100764;
            8'd78: recip_lut_lookup = 40'd100462;
            8'd79: recip_lut_lookup = 40'd100162;
            8'd80: recip_lut_lookup = 40'd99864;
            8'd81: recip_lut_lookup = 40'd99568;
            8'd82: recip_lut_lookup = 40'd99273;
            8'd83: recip_lut_lookup = 40'd98981;
            8'd84: recip_lut_lookup = 40'd98690;
            8'd85: recip_lut_lookup = 40'd98400;
            8'd86: recip_lut_lookup = 40'd98112;
            8'd87: recip_lut_lookup = 40'd97826;
            8'd88: recip_lut_lookup = 40'd97542;
            8'd89: recip_lut_lookup = 40'd97259;
            8'd90: recip_lut_lookup = 40'd96978;
            8'd91: recip_lut_lookup = 40'd96699;
            8'd92: recip_lut_lookup = 40'd96421;
            8'd93: recip_lut_lookup = 40'd96145;
            8'd94: recip_lut_lookup = 40'd95870;
            8'd95: recip_lut_lookup = 40'd95597;
            8'd96: recip_lut_lookup = 40'd95325;
            8'd97: recip_lut_lookup = 40'd95055;
            8'd98: recip_lut_lookup = 40'd94787;
            8'd99: recip_lut_lookup = 40'd94520;
            8'd100: recip_lut_lookup = 40'd94254;
            8'd101: recip_lut_lookup = 40'd93990;
            8'd102: recip_lut_lookup = 40'd93727;
            8'd103: recip_lut_lookup = 40'd93466;
            8'd104: recip_lut_lookup = 40'd93207;
            8'd105: recip_lut_lookup = 40'd92949;
            8'd106: recip_lut_lookup = 40'd92692;
            8'd107: recip_lut_lookup = 40'd92436;
            8'd108: recip_lut_lookup = 40'd92183;
            8'd109: recip_lut_lookup = 40'd91930;
            8'd110: recip_lut_lookup = 40'd91679;
            8'd111: recip_lut_lookup = 40'd91429;
            8'd112: recip_lut_lookup = 40'd91181;
            8'd113: recip_lut_lookup = 40'd90933;
            8'd114: recip_lut_lookup = 40'd90688;
            8'd115: recip_lut_lookup = 40'd90443;
            8'd116: recip_lut_lookup = 40'd90200;
            8'd117: recip_lut_lookup = 40'd89958;
            8'd118: recip_lut_lookup = 40'd89718;
            8'd119: recip_lut_lookup = 40'd89478;
            8'd120: recip_lut_lookup = 40'd89241;
            8'd121: recip_lut_lookup = 40'd89004;
            8'd122: recip_lut_lookup = 40'd88768;
            8'd123: recip_lut_lookup = 40'd88534;
            8'd124: recip_lut_lookup = 40'd88301;
            8'd125: recip_lut_lookup = 40'd88069;
            8'd126: recip_lut_lookup = 40'd87839;
            8'd127: recip_lut_lookup = 40'd87609;
            8'd128: recip_lut_lookup = 40'd87381;
            8'd129: recip_lut_lookup = 40'd87154;
            8'd130: recip_lut_lookup = 40'd86929;
            8'd131: recip_lut_lookup = 40'd86704;
            8'd132: recip_lut_lookup = 40'd86480;
            8'd133: recip_lut_lookup = 40'd86258;
            8'd134: recip_lut_lookup = 40'd86037;
            8'd135: recip_lut_lookup = 40'd85817;
            8'd136: recip_lut_lookup = 40'd85598;
            8'd137: recip_lut_lookup = 40'd85380;
            8'd138: recip_lut_lookup = 40'd85164;
            8'd139: recip_lut_lookup = 40'd84948;
            8'd140: recip_lut_lookup = 40'd84733;
            8'd141: recip_lut_lookup = 40'd84520;
            8'd142: recip_lut_lookup = 40'd84308;
            8'd143: recip_lut_lookup = 40'd84096;
            8'd144: recip_lut_lookup = 40'd83886;
            8'd145: recip_lut_lookup = 40'd83677;
            8'd146: recip_lut_lookup = 40'd83469;
            8'd147: recip_lut_lookup = 40'd83262;
            8'd148: recip_lut_lookup = 40'd83056;
            8'd149: recip_lut_lookup = 40'd82850;
            8'd150: recip_lut_lookup = 40'd82646;
            8'd151: recip_lut_lookup = 40'd82443;
            8'd152: recip_lut_lookup = 40'd82241;
            8'd153: recip_lut_lookup = 40'd82040;
            8'd154: recip_lut_lookup = 40'd81840;
            8'd155: recip_lut_lookup = 40'd81641;
            8'd156: recip_lut_lookup = 40'd81443;
            8'd157: recip_lut_lookup = 40'd81246;
            8'd158: recip_lut_lookup = 40'd81049;
            8'd159: recip_lut_lookup = 40'd80854;
            8'd160: recip_lut_lookup = 40'd80660;
            8'd161: recip_lut_lookup = 40'd80466;
            8'd162: recip_lut_lookup = 40'd80274;
            8'd163: recip_lut_lookup = 40'd80082;
            8'd164: recip_lut_lookup = 40'd79892;
            8'd165: recip_lut_lookup = 40'd79702;
            8'd166: recip_lut_lookup = 40'd79513;
            8'd167: recip_lut_lookup = 40'd79325;
            8'd168: recip_lut_lookup = 40'd79138;
            8'd169: recip_lut_lookup = 40'd78952;
            8'd170: recip_lut_lookup = 40'd78766;
            8'd171: recip_lut_lookup = 40'd78582;
            8'd172: recip_lut_lookup = 40'd78398;
            8'd173: recip_lut_lookup = 40'd78215;
            8'd174: recip_lut_lookup = 40'd78034;
            8'd175: recip_lut_lookup = 40'd77853;
            8'd176: recip_lut_lookup = 40'd77672;
            8'd177: recip_lut_lookup = 40'd77493;
            8'd178: recip_lut_lookup = 40'd77314;
            8'd179: recip_lut_lookup = 40'd77137;
            8'd180: recip_lut_lookup = 40'd76960;
            8'd181: recip_lut_lookup = 40'd76784;
            8'd182: recip_lut_lookup = 40'd76608;
            8'd183: recip_lut_lookup = 40'd76434;
            8'd184: recip_lut_lookup = 40'd76260;
            8'd185: recip_lut_lookup = 40'd76087;
            8'd186: recip_lut_lookup = 40'd75915;
            8'd187: recip_lut_lookup = 40'd75744;
            8'd188: recip_lut_lookup = 40'd75573;
            8'd189: recip_lut_lookup = 40'd75403;
            8'd190: recip_lut_lookup = 40'd75234;
            8'd191: recip_lut_lookup = 40'd75066;
            8'd192: recip_lut_lookup = 40'd74898;
            8'd193: recip_lut_lookup = 40'd74731;
            8'd194: recip_lut_lookup = 40'd74565;
            8'd195: recip_lut_lookup = 40'd74400;
            8'd196: recip_lut_lookup = 40'd74235;
            8'd197: recip_lut_lookup = 40'd74072;
            8'd198: recip_lut_lookup = 40'd73908;
            8'd199: recip_lut_lookup = 40'd73746;
            8'd200: recip_lut_lookup = 40'd73584;
            8'd201: recip_lut_lookup = 40'd73423;
            8'd202: recip_lut_lookup = 40'd73263;
            8'd203: recip_lut_lookup = 40'd73103;
            8'd204: recip_lut_lookup = 40'd72944;
            8'd205: recip_lut_lookup = 40'd72786;
            8'd206: recip_lut_lookup = 40'd72629;
            8'd207: recip_lut_lookup = 40'd72472;
            8'd208: recip_lut_lookup = 40'd72316;
            8'd209: recip_lut_lookup = 40'd72160;
            8'd210: recip_lut_lookup = 40'd72005;
            8'd211: recip_lut_lookup = 40'd71851;
            8'd212: recip_lut_lookup = 40'd71698;
            8'd213: recip_lut_lookup = 40'd71545;
            8'd214: recip_lut_lookup = 40'd71392;
            8'd215: recip_lut_lookup = 40'd71241;
            8'd216: recip_lut_lookup = 40'd71090;
            8'd217: recip_lut_lookup = 40'd70940;
            8'd218: recip_lut_lookup = 40'd70790;
            8'd219: recip_lut_lookup = 40'd70641;
            8'd220: recip_lut_lookup = 40'd70493;
            8'd221: recip_lut_lookup = 40'd70345;
            8'd222: recip_lut_lookup = 40'd70198;
            8'd223: recip_lut_lookup = 40'd70051;
            8'd224: recip_lut_lookup = 40'd69905;
            8'd225: recip_lut_lookup = 40'd69760;
            8'd226: recip_lut_lookup = 40'd69615;
            8'd227: recip_lut_lookup = 40'd69471;
            8'd228: recip_lut_lookup = 40'd69327;
            8'd229: recip_lut_lookup = 40'd69184;
            8'd230: recip_lut_lookup = 40'd69042;
            8'd231: recip_lut_lookup = 40'd68900;
            8'd232: recip_lut_lookup = 40'd68759;
            8'd233: recip_lut_lookup = 40'd68618;
            8'd234: recip_lut_lookup = 40'd68478;
            8'd235: recip_lut_lookup = 40'd68339;
            8'd236: recip_lut_lookup = 40'd68200;
            8'd237: recip_lut_lookup = 40'd68062;
            8'd238: recip_lut_lookup = 40'd67924;
            8'd239: recip_lut_lookup = 40'd67787;
            8'd240: recip_lut_lookup = 40'd67650;
            8'd241: recip_lut_lookup = 40'd67514;
            8'd242: recip_lut_lookup = 40'd67378;
            8'd243: recip_lut_lookup = 40'd67243;
            8'd244: recip_lut_lookup = 40'd67109;
            8'd245: recip_lut_lookup = 40'd66975;
            8'd246: recip_lut_lookup = 40'd66841;
            8'd247: recip_lut_lookup = 40'd66709;
            8'd248: recip_lut_lookup = 40'd66576;
            8'd249: recip_lut_lookup = 40'd66444;
            8'd250: recip_lut_lookup = 40'd66313;
            8'd251: recip_lut_lookup = 40'd66182;
            8'd252: recip_lut_lookup = 40'd66052;
            8'd253: recip_lut_lookup = 40'd65922;
            8'd254: recip_lut_lookup = 40'd65793;
            8'd255: recip_lut_lookup = 40'd65664;
            default: recip_lut_lookup = 40'd65536;
        endcase
    endfunction
`else
    // Simulation: use initial block for accurate float computation
    logic [WIDTH-1:0] recip_lut [0:LUT_DEPTH-1];

    integer _ri;
    initial begin
        for (_ri = 0; _ri < LUT_DEPTH; _ri = _ri + 1) begin
            recip_lut[_ri] = WIDTH'(int'((1.0 / (0.5 + (real'(_ri) / real'(LUT_DEPTH)) * 0.5)) * (2.0 ** FRAC_BITS) + 0.5));
        end
    end
`endif

    // Stage 1: find leading one and normalize
    logic valid_s1;
    logic [$clog2(WIDTH)-1:0] lz_count;
    logic [WIDTH-1:0] d_norm;
    logic [WIDTH-1:0] d_saved;
    logic [$clog2(WIDTH)-1:0] shift_amt;

    function automatic [$clog2(WIDTH)-1:0] count_leading_zeros(input [WIDTH-1:0] val);
        integer i;
        reg [$clog2(WIDTH)-1:0] result;
        begin
            result = WIDTH;
            for (i = WIDTH-1; i >= 0; i = i - 1) begin
                if (val[i]) begin
                    result = WIDTH - 1 - i;
                    return result;
                end
            end
            return result;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1  <= 1'b0;
            d_norm    <= '0;
            d_saved   <= '0;
            shift_amt <= '0;
        end else begin
            valid_s1 <= valid_in;
            d_saved  <= d_in;
            lz_count  = count_leading_zeros(d_in);
            shift_amt <= lz_count;
            d_norm    <= d_in << lz_count;
        end
    end

    // Stage 2: LUT lookup for initial guess
    logic valid_s2;
    logic [WIDTH-1:0] x0;
    logic [WIDTH-1:0] d_s2;
    logic [$clog2(WIDTH)-1:0] shift_s2;
    logic [7:0] lut_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s2 <= 1'b0;
            x0       <= '0;
            d_s2     <= '0;
            shift_s2 <= '0;
        end else begin
            valid_s2 <= valid_s1;
            d_s2     <= d_saved;
            shift_s2 <= shift_amt;
            lut_idx   = d_norm[WIDTH-1 -: 8];
`ifdef SYNTHESIS
            x0       <= recip_lut_lookup(lut_idx) << shift_amt;
`else
            x0       <= recip_lut[lut_idx] << shift_amt;
`endif
        end
    end

    // Stage 3: Newton-Raphson iteration 1
    // x1 = x0 * (2 - d * x0)
    logic valid_s3;
    logic [WIDTH-1:0] x1;
    logic [WIDTH-1:0] d_s3;
    logic [2*WIDTH-1:0] d_x0;
    logic [WIDTH-1:0] two_minus;
    logic [2*WIDTH-1:0] x1_full;

    localparam [WIDTH-1:0] TWO_FP = WIDTH'(2) << FRAC_BITS;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s3 <= 1'b0;
            x1       <= '0;
            d_s3     <= '0;
        end else begin
            valid_s3  <= valid_s2;
            d_s3      <= d_s2;
            d_x0       = (d_s2 * x0) >> FRAC_BITS;
            two_minus  = TWO_FP - d_x0[WIDTH-1:0];
            x1_full    = (x0 * two_minus) >> FRAC_BITS;
            x1        <= x1_full[WIDTH-1:0];
        end
    end

    // Stage 4: Newton-Raphson iteration 2
    // x2 = x1 * (2 - d * x1)
    logic valid_s4;
    logic [WIDTH-1:0] x2;
    logic [2*WIDTH-1:0] d_x1;
    logic [WIDTH-1:0] two_minus2;
    logic [2*WIDTH-1:0] x2_full;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s4 <= 1'b0;
            x2       <= '0;
        end else begin
            valid_s4   <= valid_s3;
            d_x1        = (d_s3 * x1) >> FRAC_BITS;
            two_minus2  = TWO_FP - d_x1[WIDTH-1:0];
            x2_full     = (x1 * two_minus2) >> FRAC_BITS;
            x2         <= x2_full[WIDTH-1:0];
        end
    end

    assign valid_out = valid_s4;
    assign recip_out = x2;

endmodule
