`timescale 1ns/1ps
package fa_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

`ifdef FA_SEQ_LEN_OVERRIDE
    localparam int FA_SEQ_LEN  = `FA_SEQ_LEN_OVERRIDE;
`else
    localparam int FA_SEQ_LEN  = 256;
`endif
    localparam int FA_HEAD_DIM = 64;
    localparam int FA_TILE_BR  = 4;
    localparam int FA_TILE_BC  = 16;
    localparam int FA_MAX_HEADS = 2;
    localparam int FA_MAX_SCOREBOARD_JOBS = 2;

    localparam bit [63:0] FA_Q_BASE = 64'h0000_0000_0001_0000;
    localparam bit [63:0] FA_K_BASE = 64'h0000_0000_0002_0000;
    localparam bit [63:0] FA_V_BASE = 64'h0000_0000_0003_0000;
    localparam bit [63:0] FA_O_BASE = 64'h0000_0000_0004_0000;
    localparam bit [63:0] FA_Q_BASE_JOB1 = 64'h0000_0000_0011_0000;
    localparam bit [63:0] FA_K_BASE_JOB1 = 64'h0000_0000_0012_0000;
    localparam bit [63:0] FA_V_BASE_JOB1 = 64'h0000_0000_0013_0000;
    localparam bit [63:0] FA_O_BASE_JOB1 = 64'h0000_0000_0014_0000;

    localparam longint unsigned FA_TENSOR_BYTES        = FA_SEQ_LEN * FA_HEAD_DIM * 2;
    localparam longint unsigned FA_TILE_QO_BYTES       = FA_TILE_BR * FA_HEAD_DIM * 2;
    localparam longint unsigned FA_TILE_KV_BYTES       = FA_TILE_BC * FA_HEAD_DIM * 2;
    localparam longint unsigned FA_EXPECT_Q_READ_BYTES = FA_TENSOR_BYTES;
    localparam longint unsigned FA_EXPECT_K_READ_BYTES = 1114112;
    localparam longint unsigned FA_EXPECT_V_READ_BYTES = 1114112;
    localparam longint unsigned FA_EXPECT_O_WR_BYTES   = FA_TENSOR_BYTES;
    localparam longint unsigned FA_EXPECT_RD_BYTES     = FA_EXPECT_Q_READ_BYTES + FA_EXPECT_K_READ_BYTES + FA_EXPECT_V_READ_BYTES;
    localparam longint unsigned FA_EXPECT_WR_BYTES     = FA_EXPECT_O_WR_BYTES;

    localparam real FA_MEAN_LIMIT        = 0.03;
    localparam real FA_MAX_LIMIT         = 0.10;
    localparam real FA_CAUSAL_ROW0_LIMIT = 0.02;

    localparam bit [7:0] FA_REG_CTRL         = 8'h00;
    localparam bit [7:0] FA_REG_STATUS       = 8'h04;
    localparam bit [7:0] FA_REG_CFG          = 8'h08;
    localparam bit [7:0] FA_REG_Q_BASE_L     = 8'h14;
    localparam bit [7:0] FA_REG_Q_BASE_H     = 8'h18;
    localparam bit [7:0] FA_REG_K_BASE_L     = 8'h1C;
    localparam bit [7:0] FA_REG_K_BASE_H     = 8'h20;
    localparam bit [7:0] FA_REG_V_BASE_L     = 8'h24;
    localparam bit [7:0] FA_REG_V_BASE_H     = 8'h28;
    localparam bit [7:0] FA_REG_O_BASE_L     = 8'h2C;
    localparam bit [7:0] FA_REG_O_BASE_H     = 8'h30;
    localparam bit [7:0] FA_REG_STRIDE_BYTES = 8'h34;
    localparam bit [7:0] FA_REG_NEG_LARGE    = 8'h38;
    localparam bit [7:0] FA_REG_SCALE        = 8'h3C;
    localparam bit [7:0] FA_REG_CYCLES       = 8'h40;
    localparam bit [7:0] FA_REG_RD_BYTES     = 8'h44;
    localparam bit [7:0] FA_REG_WR_BYTES     = 8'h48;
    localparam bit [7:0] FA_REG_VALID_LEN    = 8'h4C;
    localparam bit [7:0] FA_REG_HEAD_COUNT   = 8'h50;
    localparam bit [7:0] FA_REG_HEAD_STRIDE  = 8'h54;
    localparam bit [7:0] FA_REG_QUEUE_STATUS = 8'h58;
    localparam bit [7:0] FA_REG_FORMAT       = 8'h5C;
    localparam bit [7:0] FA_REG_DROPOUT_CTRL = 8'h60;
    localparam bit [7:0] FA_REG_DROPOUT_RATE = 8'h64;
    localparam bit [7:0] FA_REG_DROPOUT_SEED = 8'h68;

    localparam int FA_CTRL_START      = 0;
    localparam int FA_CTRL_SOFT_RESET = 1;
    localparam int FA_STATUS_BUSY     = 0;
    localparam int FA_STATUS_DONE     = 1;
    localparam int FA_STATUS_ERROR    = 2;
    localparam int FA_CFG_CAUSAL_EN   = 0;

    localparam int FA_FORMAT_Q8_8      = 0;
    localparam int FA_FORMAT_Q6_10     = 1;
    localparam int FA_FORMAT_Q4_12     = 2;
    localparam int FA_FORMAT_INT8_Q4_4 = 3;
    localparam int FA_FORMAT_FP8_E4M3  = 4;
    localparam int FA_FORMAT_FP16      = 5;
    localparam int FA_FORMAT_BF16      = 6;

    `uvm_analysis_imp_decl(_axil)
    `uvm_analysis_imp_decl(_dma)
    `uvm_analysis_imp_decl(_axis)

    function automatic longint unsigned fa_burst_byte_count(
        input bit [7:0] len,
        input bit [2:0] size
    );
        fa_burst_byte_count = (longint'(len) + 1) << size;
    endfunction

    function automatic int fa_dma_region(
        input bit is_write,
        input bit [63:0] addr,
        input longint unsigned bytes
    );
        begin
            fa_dma_region = -1;
            if (!is_write && addr >= FA_Q_BASE && (addr + bytes) <= (FA_Q_BASE + FA_TENSOR_BYTES))
                fa_dma_region = 0;
            else if (!is_write && addr >= FA_K_BASE && (addr + bytes) <= (FA_K_BASE + FA_TENSOR_BYTES))
                fa_dma_region = 1;
            else if (!is_write && addr >= FA_V_BASE && (addr + bytes) <= (FA_V_BASE + FA_TENSOR_BYTES))
                fa_dma_region = 2;
            else if (is_write && addr >= FA_O_BASE && (addr + bytes) <= (FA_O_BASE + FA_TENSOR_BYTES))
                fa_dma_region = 3;
        end
    endfunction

    class fa_axil_reg_item extends uvm_sequence_item;
        rand bit        write;
        rand bit [7:0]  addr;
        rand bit [31:0] data;
        rand bit [3:0]  strb;
        bit [31:0]      rdata;
        bit [1:0]       resp;

        `uvm_object_utils_begin(fa_axil_reg_item)
            `uvm_field_int(write, UVM_DEFAULT)
            `uvm_field_int(addr,  UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(data,  UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(strb,  UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(rdata, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(resp,  UVM_DEFAULT | UVM_HEX)
        `uvm_object_utils_end

        function new(string name = "fa_axil_reg_item");
            super.new(name);
            strb = 4'hF;
        endfunction
    endclass

    class fa_attention_job_item extends uvm_sequence_item;
        rand bit [63:0] q_base;
        rand bit [63:0] k_base;
        rand bit [63:0] v_base;
        rand bit [63:0] o_base;
        rand bit        causal_en;
        rand bit [31:0] stride_bytes;
        rand bit [31:0] neg_large;
        rand bit [31:0] scale;
        rand bit [31:0] valid_len;
        rand bit [31:0] head_count;
        rand bit [31:0] head_stride_bytes;
        rand bit [31:0] format_mode;
        rand bit        dropout_en;
        rand bit [31:0] dropout_rate;
        rand bit [31:0] dropout_seed;
        int unsigned    job_id;

        `uvm_object_utils_begin(fa_attention_job_item)
            `uvm_field_int(q_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(k_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(v_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(o_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(causal_en,    UVM_DEFAULT)
            `uvm_field_int(stride_bytes, UVM_DEFAULT)
            `uvm_field_int(neg_large,    UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(scale,        UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(valid_len,    UVM_DEFAULT)
            `uvm_field_int(head_count,   UVM_DEFAULT)
            `uvm_field_int(head_stride_bytes, UVM_DEFAULT)
            `uvm_field_int(format_mode,  UVM_DEFAULT)
            `uvm_field_int(dropout_en,   UVM_DEFAULT)
            `uvm_field_int(dropout_rate, UVM_DEFAULT)
            `uvm_field_int(dropout_seed, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(job_id,       UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "fa_attention_job_item");
            super.new(name);
            q_base       = FA_Q_BASE;
            k_base       = FA_K_BASE;
            v_base       = FA_V_BASE;
            o_base       = FA_O_BASE;
            causal_en    = 1'b1;
            stride_bytes = 32'd128;
            neg_large    = 32'h0000_8000;
            scale        = 32'h0000_0020;
            valid_len    = FA_SEQ_LEN;
            head_count   = 32'd1;
            head_stride_bytes = 32'(FA_TENSOR_BYTES);
            format_mode  = FA_FORMAT_Q8_8;
            dropout_en   = 1'b0;
            dropout_rate = 32'd0;
            dropout_seed = 32'h0000_0001;
            job_id       = 0;
        endfunction
    endclass

    class fa_axi_dma_item extends uvm_sequence_item;
        bit        is_write;
        bit [63:0] addr;
        bit [7:0]  len;
        bit [2:0]  size;
        bit [1:0]  burst;
        int        beats;
        longint unsigned bytes;

        `uvm_object_utils_begin(fa_axi_dma_item)
            `uvm_field_int(is_write, UVM_DEFAULT)
            `uvm_field_int(addr,     UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(len,      UVM_DEFAULT)
            `uvm_field_int(size,     UVM_DEFAULT)
            `uvm_field_int(burst,    UVM_DEFAULT)
            `uvm_field_int(beats,    UVM_DEFAULT)
            `uvm_field_int(bytes,    UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "fa_axi_dma_item");
            super.new(name);
        endfunction
    endclass

    class fa_axis_item extends uvm_sequence_item;
        bit [127:0] data;
        bit [15:0]  keep;
        bit         last;

        `uvm_object_utils_begin(fa_axis_item)
            `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(keep, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(last, UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "fa_axis_item");
            super.new(name);
        endfunction
    endclass

    class fa_axil_sequencer extends uvm_sequencer #(fa_axil_reg_item);
        `uvm_component_utils(fa_axil_sequencer)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class fa_axil_driver extends uvm_driver #(fa_axil_reg_item);
        `uvm_component_utils(fa_axil_driver)

        virtual fa_axil_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_axil_if)::get(this, "", "axil_vif", vif))
                `uvm_fatal("NOVIF", "fa_axil_driver requires axil_vif")
        endfunction

        task run_phase(uvm_phase phase);
            fa_axil_reg_item tr;

            vif.awaddr  <= '0;
            vif.awvalid <= 1'b0;
            vif.wdata   <= '0;
            vif.wstrb   <= '0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.araddr  <= '0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;

            forever begin
                seq_item_port.get_next_item(tr);
                if (tr.write)
                    drive_write(tr);
                else
                    drive_read(tr);
                seq_item_port.item_done();
            end
        endtask

        task automatic wait_reset_done();
            wait (vif.rst_n === 1'b1);
            @(posedge vif.clk);
        endtask

        task automatic drive_write(fa_axil_reg_item tr);
            wait_reset_done();
            @(posedge vif.clk);
            vif.awaddr  <= tr.addr;
            vif.awvalid <= 1'b1;
            vif.wdata   <= tr.data;
            vif.wstrb   <= tr.strb;
            vif.wvalid  <= 1'b1;

            do begin
                @(posedge vif.clk);
            end while (!(vif.awready && vif.wready));

            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b1;

            do begin
                @(posedge vif.clk);
            end while (!vif.bvalid);

            tr.resp = vif.bresp;
            @(posedge vif.clk);
            vif.bready <= 1'b0;
        endtask

        task automatic drive_read(fa_axil_reg_item tr);
            wait_reset_done();
            @(posedge vif.clk);
            vif.araddr  <= tr.addr;
            vif.arvalid <= 1'b1;

            do begin
                @(posedge vif.clk);
            end while (!vif.arready);

            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b1;

            do begin
                @(posedge vif.clk);
            end while (!vif.rvalid);

            tr.rdata = vif.rdata;
            tr.resp  = vif.rresp;
            @(posedge vif.clk);
            vif.rready <= 1'b0;
        endtask
    endclass

    class fa_axil_monitor extends uvm_component;
        `uvm_component_utils(fa_axil_monitor)

        virtual fa_axil_if vif;
        uvm_analysis_port #(fa_axil_reg_item) ap;

        bit aw_stall_q;
        bit w_stall_q;
        bit ar_stall_q;
        bit r_stall_q;
        bit [7:0]  awaddr_hold;
        bit [7:0]  araddr_hold;
        bit [31:0] wdata_hold;
        bit [31:0] rdata_hold;
        bit [3:0]  wstrb_hold;
        bit [1:0]  rresp_hold;
        bit [7:0]  pending_ar[$];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_axil_if)::get(this, "", "axil_vif", vif))
                `uvm_fatal("NOVIF", "fa_axil_monitor requires axil_vif")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    aw_stall_q = 1'b0;
                    w_stall_q  = 1'b0;
                    ar_stall_q = 1'b0;
                    r_stall_q  = 1'b0;
                    pending_ar.delete();
                end else begin
                    check_protocol();
                    sample_transactions();
                    update_stall_state();
                end
            end
        endtask

        function void check_protocol();
            if (vif.awvalid && $isunknown({vif.awaddr, vif.awvalid, vif.awready}))
                `uvm_fatal("AXILVIP", "X/Z on AXI4-Lite AW channel")
            if (vif.wvalid && $isunknown({vif.wdata, vif.wstrb, vif.wvalid, vif.wready}))
                `uvm_fatal("AXILVIP", "X/Z on AXI4-Lite W channel")
            if (vif.arvalid && $isunknown({vif.araddr, vif.arvalid, vif.arready}))
                `uvm_fatal("AXILVIP", "X/Z on AXI4-Lite AR channel")
            if (vif.rvalid && $isunknown({vif.rdata, vif.rresp, vif.rvalid, vif.rready}))
                `uvm_fatal("AXILVIP", "X/Z on AXI4-Lite R channel")
            if (vif.bvalid && $isunknown({vif.bresp, vif.bvalid, vif.bready}))
                `uvm_fatal("AXILVIP", "X/Z on AXI4-Lite B channel")

            if (aw_stall_q) begin
                if (!vif.awvalid)
                    `uvm_fatal("AXILVIP", "AWVALID dropped before AWREADY")
                if (vif.awaddr !== awaddr_hold)
                    `uvm_fatal("AXILVIP", "AWADDR changed while stalled")
            end
            if (w_stall_q) begin
                if (!vif.wvalid)
                    `uvm_fatal("AXILVIP", "WVALID dropped before WREADY")
                if (vif.wdata !== wdata_hold || vif.wstrb !== wstrb_hold)
                    `uvm_fatal("AXILVIP", "W payload changed while stalled")
            end
            if (ar_stall_q) begin
                if (!vif.arvalid)
                    `uvm_fatal("AXILVIP", "ARVALID dropped before ARREADY")
                if (vif.araddr !== araddr_hold)
                    `uvm_fatal("AXILVIP", "ARADDR changed while stalled")
            end
            if (r_stall_q) begin
                if (!vif.rvalid)
                    `uvm_fatal("AXILVIP", "RVALID dropped before RREADY")
                if (vif.rdata !== rdata_hold || vif.rresp !== rresp_hold)
                    `uvm_fatal("AXILVIP", "R payload changed while stalled")
            end

            if (vif.wvalid && vif.wready && vif.wstrb == '0)
                `uvm_fatal("AXILVIP", "Zero WSTRB write is outside this verification plan")
            if (vif.bvalid && vif.bresp != 2'b00)
                `uvm_fatal("AXILVIP", "AXI4-Lite BRESP was not OKAY")
            if (vif.rvalid && vif.rresp != 2'b00)
                `uvm_fatal("AXILVIP", "AXI4-Lite RRESP was not OKAY")
        endfunction

        function void sample_transactions();
            fa_axil_reg_item tr;

            if (vif.awvalid && vif.awready && vif.wvalid && vif.wready) begin
                tr = fa_axil_reg_item::type_id::create("axil_write_tr");
                tr.write = 1'b1;
                tr.addr  = vif.awaddr;
                tr.data  = vif.wdata;
                tr.strb  = vif.wstrb;
                tr.resp  = 2'b00;
                ap.write(tr);
            end

            if (vif.arvalid && vif.arready)
                pending_ar.push_back(vif.araddr);

            if (vif.rvalid && vif.rready) begin
                tr = fa_axil_reg_item::type_id::create("axil_read_tr");
                tr.write = 1'b0;
                tr.addr  = (pending_ar.size() != 0) ? pending_ar.pop_front() : 8'h00;
                tr.data  = '0;
                tr.strb  = 4'h0;
                tr.rdata = vif.rdata;
                tr.resp  = vif.rresp;
                ap.write(tr);
            end
        endfunction

        function void update_stall_state();
            if (vif.awvalid && !vif.awready) begin
                aw_stall_q  = 1'b1;
                awaddr_hold = vif.awaddr;
            end else begin
                aw_stall_q  = 1'b0;
            end

            if (vif.wvalid && !vif.wready) begin
                w_stall_q  = 1'b1;
                wdata_hold = vif.wdata;
                wstrb_hold = vif.wstrb;
            end else begin
                w_stall_q  = 1'b0;
            end

            if (vif.arvalid && !vif.arready) begin
                ar_stall_q  = 1'b1;
                araddr_hold = vif.araddr;
            end else begin
                ar_stall_q  = 1'b0;
            end

            if (vif.rvalid && !vif.rready) begin
                r_stall_q  = 1'b1;
                rdata_hold = vif.rdata;
                rresp_hold = vif.rresp;
            end else begin
                r_stall_q  = 1'b0;
            end
        endfunction
    endclass

    class fa_axi_master_monitor extends uvm_component;
        `uvm_component_utils(fa_axi_master_monitor)

        virtual fa_axi4_master_if vif;
        uvm_analysis_port #(fa_axi_dma_item) ap;

        bit aw_stall_q;
        bit w_stall_q;
        bit ar_stall_q;
        bit r_stall_q;
        bit wr_active;
        bit rd_active;
        bit [8:0] wr_expected_beats;
        bit [8:0] wr_seen_beats;
        bit [8:0] rd_expected_beats;
        bit [8:0] rd_seen_beats;

        bit [3:0]   awid_hold;
        bit [63:0]  awaddr_hold;
        bit [7:0]   awlen_hold;
        bit [2:0]   awsize_hold;
        bit [1:0]   awburst_hold;
        bit [127:0] wdata_hold;
        bit [15:0]  wstrb_hold;
        bit         wlast_hold;
        bit [3:0]   arid_hold;
        bit [63:0]  araddr_hold;
        bit [7:0]   arlen_hold;
        bit [2:0]   arsize_hold;
        bit [1:0]   arburst_hold;
        bit [3:0]   rid_hold;
        bit [127:0] rdata_hold;
        bit [1:0]   rresp_hold;
        bit         rlast_hold;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_axi4_master_if)::get(this, "", "axi_vif", vif))
                `uvm_fatal("NOVIF", "fa_axi_master_monitor requires axi_vif")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    reset_state();
                end else begin
                    check_protocol();
                    sample_bursts();
                    update_stall_state();
                end
            end
        endtask

        function void reset_state();
            aw_stall_q = 1'b0;
            w_stall_q  = 1'b0;
            ar_stall_q = 1'b0;
            r_stall_q  = 1'b0;
            wr_active  = 1'b0;
            rd_active  = 1'b0;
            wr_expected_beats = '0;
            wr_seen_beats     = '0;
            rd_expected_beats = '0;
            rd_seen_beats     = '0;
        endfunction

        function bit [12:0] offset_plus_bytes(bit [63:0] addr, bit [7:0] len, bit [2:0] size);
            offset_plus_bytes = {1'b0, addr[11:0]} + ((({5'd0, len} + 13'd1) << size));
        endfunction

        function void check_protocol();
            if (vif.awvalid && $isunknown({vif.awid, vif.awaddr, vif.awlen, vif.awsize, vif.awburst, vif.awvalid, vif.awready}))
                `uvm_fatal("AXIVIP", "X/Z on AXI4 AW channel")
            if (vif.wvalid && $isunknown({vif.wdata, vif.wstrb, vif.wlast, vif.wvalid, vif.wready}))
                `uvm_fatal("AXIVIP", "X/Z on AXI4 W channel")
            if (vif.bvalid && $isunknown({vif.bid, vif.bresp, vif.bvalid, vif.bready}))
                `uvm_fatal("AXIVIP", "X/Z on AXI4 B channel")
            if (vif.arvalid && $isunknown({vif.arid, vif.araddr, vif.arlen, vif.arsize, vif.arburst, vif.arvalid, vif.arready}))
                `uvm_fatal("AXIVIP", "X/Z on AXI4 AR channel")
            if (vif.rvalid && $isunknown({vif.rid, vif.rdata, vif.rresp, vif.rlast, vif.rvalid, vif.rready}))
                `uvm_fatal("AXIVIP", "X/Z on AXI4 R channel")

            if (aw_stall_q) begin
                if (!vif.awvalid)
                    `uvm_fatal("AXIVIP", "AWVALID dropped before AWREADY")
                if (vif.awid !== awid_hold || vif.awaddr !== awaddr_hold ||
                    vif.awlen !== awlen_hold || vif.awsize !== awsize_hold ||
                    vif.awburst !== awburst_hold)
                    `uvm_fatal("AXIVIP", "AW payload changed while stalled")
            end
            if (w_stall_q) begin
                if (!vif.wvalid)
                    `uvm_fatal("AXIVIP", "WVALID dropped before WREADY")
                if (vif.wdata !== wdata_hold || vif.wstrb !== wstrb_hold || vif.wlast !== wlast_hold)
                    `uvm_fatal("AXIVIP", "W payload changed while stalled")
            end
            if (ar_stall_q) begin
                if (!vif.arvalid)
                    `uvm_fatal("AXIVIP", "ARVALID dropped before ARREADY")
                if (vif.arid !== arid_hold || vif.araddr !== araddr_hold ||
                    vif.arlen !== arlen_hold || vif.arsize !== arsize_hold ||
                    vif.arburst !== arburst_hold)
                    `uvm_fatal("AXIVIP", "AR payload changed while stalled")
            end
            if (r_stall_q) begin
                if (!vif.rvalid)
                    `uvm_fatal("AXIVIP", "RVALID dropped before RREADY")
                if (vif.rid !== rid_hold || vif.rdata !== rdata_hold ||
                    vif.rresp !== rresp_hold || vif.rlast !== rlast_hold)
                    `uvm_fatal("AXIVIP", "R payload changed while stalled")
            end

            if (vif.bvalid && vif.bresp != 2'b00)
                `uvm_fatal("AXIVIP", "AXI4 BRESP was not OKAY")
            if (vif.rvalid && vif.rresp != 2'b00)
                `uvm_fatal("AXIVIP", "AXI4 RRESP was not OKAY")
        endfunction

        function void sample_bursts();
            fa_axi_dma_item tr;

            if (vif.awvalid && vif.awready) begin
                if (wr_active)
                    `uvm_fatal("AXIVIP", "New AW before previous write burst completed")
                if (vif.awsize != 3'd4)
                    `uvm_fatal("AXIVIP", "Unexpected AWSIZE")
                if (vif.awburst != 2'b01)
                    `uvm_fatal("AXIVIP", "Unexpected AWBURST")
                if (vif.awaddr[3:0] != 4'h0)
                    `uvm_fatal("AXIVIP", "Unaligned AWADDR")
                if (offset_plus_bytes(vif.awaddr, vif.awlen, vif.awsize) > 13'd4096)
                    `uvm_fatal("AXIVIP", "Write burst crosses 4KB boundary")

                wr_active = 1'b1;
                wr_expected_beats = {1'b0, vif.awlen} + 9'd1;
                wr_seen_beats = '0;

                tr = fa_axi_dma_item::type_id::create("axi_aw_burst");
                tr.is_write = 1'b1;
                tr.addr     = vif.awaddr;
                tr.len      = vif.awlen;
                tr.size     = vif.awsize;
                tr.burst    = vif.awburst;
                tr.beats    = vif.awlen + 1;
                tr.bytes    = fa_burst_byte_count(vif.awlen, vif.awsize);
                ap.write(tr);
            end

            if (vif.wvalid && vif.wready) begin
                if (!wr_active)
                    `uvm_fatal("AXIVIP", "W beat without active AW burst")
                if (vif.wstrb != 16'hFFFF)
                    `uvm_fatal("AXIVIP", "AXI4 WSTRB is not full for writeback")
                if (vif.wlast != (wr_seen_beats == wr_expected_beats - 1))
                    `uvm_fatal("AXIVIP", "WLAST does not match AWLEN")
                wr_seen_beats++;
                if (vif.wlast)
                    wr_active = 1'b0;
            end

            if (vif.arvalid && vif.arready) begin
                if (rd_active)
                    `uvm_fatal("AXIVIP", "New AR before previous read burst completed")
                if (vif.arsize != 3'd4)
                    `uvm_fatal("AXIVIP", "Unexpected ARSIZE")
                if (vif.arburst != 2'b01)
                    `uvm_fatal("AXIVIP", "Unexpected ARBURST")
                if (vif.araddr[3:0] != 4'h0)
                    `uvm_fatal("AXIVIP", "Unaligned ARADDR")
                if (offset_plus_bytes(vif.araddr, vif.arlen, vif.arsize) > 13'd4096)
                    `uvm_fatal("AXIVIP", "Read burst crosses 4KB boundary")

                rd_active = 1'b1;
                rd_expected_beats = {1'b0, vif.arlen} + 9'd1;
                rd_seen_beats = '0;

                tr = fa_axi_dma_item::type_id::create("axi_ar_burst");
                tr.is_write = 1'b0;
                tr.addr     = vif.araddr;
                tr.len      = vif.arlen;
                tr.size     = vif.arsize;
                tr.burst    = vif.arburst;
                tr.beats    = vif.arlen + 1;
                tr.bytes    = fa_burst_byte_count(vif.arlen, vif.arsize);
                ap.write(tr);
            end

            if (vif.rvalid && vif.rready) begin
                if (!rd_active)
                    `uvm_fatal("AXIVIP", "R beat without active AR burst")
                if (vif.rlast != (rd_seen_beats == rd_expected_beats - 1))
                    `uvm_fatal("AXIVIP", "RLAST does not match ARLEN")
                rd_seen_beats++;
                if (vif.rlast)
                    rd_active = 1'b0;
            end
        endfunction

        function void update_stall_state();
            if (vif.awvalid && !vif.awready) begin
                aw_stall_q   = 1'b1;
                awid_hold    = vif.awid;
                awaddr_hold  = vif.awaddr;
                awlen_hold   = vif.awlen;
                awsize_hold  = vif.awsize;
                awburst_hold = vif.awburst;
            end else begin
                aw_stall_q = 1'b0;
            end

            if (vif.wvalid && !vif.wready) begin
                w_stall_q  = 1'b1;
                wdata_hold = vif.wdata;
                wstrb_hold = vif.wstrb;
                wlast_hold = vif.wlast;
            end else begin
                w_stall_q = 1'b0;
            end

            if (vif.arvalid && !vif.arready) begin
                ar_stall_q   = 1'b1;
                arid_hold    = vif.arid;
                araddr_hold  = vif.araddr;
                arlen_hold   = vif.arlen;
                arsize_hold  = vif.arsize;
                arburst_hold = vif.arburst;
            end else begin
                ar_stall_q = 1'b0;
            end

            if (vif.rvalid && !vif.rready) begin
                r_stall_q  = 1'b1;
                rid_hold   = vif.rid;
                rdata_hold = vif.rdata;
                rresp_hold = vif.rresp;
                rlast_hold = vif.rlast;
            end else begin
                r_stall_q = 1'b0;
            end
        endfunction
    endclass

    class fa_axis_monitor extends uvm_component;
        `uvm_component_utils(fa_axis_monitor)

        virtual fa_axis_if vif;
        uvm_analysis_port #(fa_axis_item) ap;

        bit s_stall_q;
        bit m_stall_q;
        bit [127:0] s_data_hold;
        bit [15:0]  s_keep_hold;
        bit         s_last_hold;
        bit [127:0] m_data_hold;
        bit [15:0]  m_keep_hold;
        bit         m_last_hold;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_axis_if)::get(this, "", "axis_vif", vif))
                `uvm_fatal("NOVIF", "fa_axis_monitor requires axis_vif")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    s_stall_q = 1'b0;
                    m_stall_q = 1'b0;
                end else begin
                    check_protocol();
                    sample_output();
                    update_stall_state();
                end
            end
        endtask

        function void check_protocol();
            if (vif.s_tvalid && $isunknown({vif.s_tdata, vif.s_tkeep, vif.s_tlast, vif.s_tvalid, vif.s_tready}))
                `uvm_fatal("AXISVIP", "X/Z on AXI4-Stream sink channel")
            if (vif.m_tvalid && $isunknown({vif.m_tdata, vif.m_tkeep, vif.m_tlast, vif.m_tvalid, vif.m_tready}))
                `uvm_fatal("AXISVIP", "X/Z on AXI4-Stream source channel")
            if (s_stall_q) begin
                if (!vif.s_tvalid)
                    `uvm_fatal("AXISVIP", "S_AXIS TVALID dropped before TREADY")
                if (vif.s_tdata !== s_data_hold || vif.s_tkeep !== s_keep_hold || vif.s_tlast !== s_last_hold)
                    `uvm_fatal("AXISVIP", "S_AXIS payload changed while stalled")
            end
            if (m_stall_q) begin
                if (!vif.m_tvalid)
                    `uvm_fatal("AXISVIP", "M_AXIS TVALID dropped before TREADY")
                if (vif.m_tdata !== m_data_hold || vif.m_tkeep !== m_keep_hold || vif.m_tlast !== m_last_hold)
                    `uvm_fatal("AXISVIP", "M_AXIS payload changed while stalled")
            end
        endfunction

        function void sample_output();
            fa_axis_item tr;
            if (vif.m_tvalid && vif.m_tready) begin
                tr = fa_axis_item::type_id::create("axis_out_tr");
                tr.data = vif.m_tdata;
                tr.keep = vif.m_tkeep;
                tr.last = vif.m_tlast;
                ap.write(tr);
            end
        endfunction

        function void update_stall_state();
            if (vif.s_tvalid && !vif.s_tready) begin
                s_stall_q = 1'b1;
                s_data_hold = vif.s_tdata;
                s_keep_hold = vif.s_tkeep;
                s_last_hold = vif.s_tlast;
            end else begin
                s_stall_q = 1'b0;
            end

            if (vif.m_tvalid && !vif.m_tready) begin
                m_stall_q = 1'b1;
                m_data_hold = vif.m_tdata;
                m_keep_hold = vif.m_tkeep;
                m_last_hold = vif.m_tlast;
            end else begin
                m_stall_q = 1'b0;
            end
        endfunction
    endclass

    class fa_axil_agent extends uvm_agent;
        `uvm_component_utils(fa_axil_agent)

        fa_axil_sequencer sequencer;
        fa_axil_driver    driver;
        fa_axil_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = fa_axil_monitor::type_id::create("monitor", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sequencer = fa_axil_sequencer::type_id::create("sequencer", this);
                driver    = fa_axil_driver::type_id::create("driver", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class fa_axi_dma_agent extends uvm_agent;
        `uvm_component_utils(fa_axi_dma_agent)

        fa_axi_master_monitor monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            monitor = fa_axi_master_monitor::type_id::create("monitor", this);
            is_active = UVM_PASSIVE;
        endfunction
    endclass

    class fa_uvm_scoreboard extends uvm_component;
        `uvm_component_utils(fa_uvm_scoreboard)

        virtual fa_mem_access_if mem_vif;
        uvm_analysis_imp_axil #(fa_axil_reg_item, fa_uvm_scoreboard) axil_export;
        uvm_analysis_imp_dma  #(fa_axi_dma_item,  fa_uvm_scoreboard) dma_export;
        uvm_analysis_imp_axis #(fa_axis_item,     fa_uvm_scoreboard) axis_export;

        longint unsigned dma_q_read_bytes;
        longint unsigned dma_k_read_bytes;
        longint unsigned dma_v_read_bytes;
        longint unsigned dma_o_write_bytes;
        longint unsigned dma_total_read_bytes;
        longint unsigned dma_total_write_bytes;
        longint unsigned dma_ar_count;
        longint unsigned dma_aw_count;

        longint unsigned axil_write_count;
        longint unsigned axil_read_count;
        bit seen_start;
        bit seen_done;
        bit seen_done_clear;
        bit seen_error;

        fa_attention_job_item expected_jobs[$];
        fa_axis_item expected_axis_items[$];
        int unsigned axis_observed_count;

        real q_f[0:FA_MAX_SCOREBOARD_JOBS-1][0:FA_MAX_HEADS-1][0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real k_f[0:FA_MAX_SCOREBOARD_JOBS-1][0:FA_MAX_HEADS-1][0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real v_f[0:FA_MAX_SCOREBOARD_JOBS-1][0:FA_MAX_HEADS-1][0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real golden_o[0:FA_MAX_SCOREBOARD_JOBS-1][0:FA_MAX_HEADS-1][0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];

        bit [31:0] last_cycles;
        bit [31:0] last_rd_bytes;
        bit [31:0] last_wr_bytes;
        real last_mean_err;
        real last_max_err;
        real last_row0_causal_err;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axil_export = new("axil_export", this);
            dma_export  = new("dma_export", this);
            axis_export = new("axis_export", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_mem_access_if)::get(this, "", "mem_vif", mem_vif))
                `uvm_fatal("NOVIF", "fa_uvm_scoreboard requires mem_vif")
            reset_dma_stats();
        endfunction

        function automatic int unsigned valid_len_eff(fa_attention_job_item job);
            if (job.valid_len == 0 || job.valid_len > FA_SEQ_LEN)
                valid_len_eff = FA_SEQ_LEN;
            else
                valid_len_eff = job.valid_len;
        endfunction

        function automatic int unsigned head_count_eff(fa_attention_job_item job);
            int unsigned hc;
            hc = (job.head_count == 0) ? 1 : job.head_count;
            if (hc > FA_MAX_HEADS)
                hc = FA_MAX_HEADS;
            head_count_eff = hc;
        endfunction

        function automatic longint unsigned head_stride_eff(fa_attention_job_item job);
            head_stride_eff = (job.head_stride_bytes == 0) ? FA_TENSOR_BYTES : job.head_stride_bytes;
        endfunction

        function automatic int unsigned format_eff(fa_attention_job_item job);
            if (job.format_mode > FA_FORMAT_BF16)
                format_eff = FA_FORMAT_Q8_8;
            else
                format_eff = job.format_mode;
        endfunction

        function automatic int unsigned dropout_rate_eff(fa_attention_job_item job);
            if (!job.dropout_en)
                dropout_rate_eff = 0;
            else if (job.dropout_rate[7:0] == 8'hFF)
                dropout_rate_eff = 254;
            else
                dropout_rate_eff = job.dropout_rate[7:0];
        endfunction

        function automatic longint signed sb_round_shift_right_signed(
            input longint signed value,
            input int unsigned shift
        );
            longint signed mag;
            begin
                if (shift == 0)
                    sb_round_shift_right_signed = value;
                else if (value >= 0)
                    sb_round_shift_right_signed = (value + (64'sd1 <<< (shift - 1))) >>> shift;
                else begin
                    mag = -value;
                    sb_round_shift_right_signed = -((mag + (64'sd1 <<< (shift - 1))) >>> shift);
                end
            end
        endfunction

        function automatic longint signed sb_apply_signed_shift(
            input longint signed value,
            input int signed shift
        );
            if (shift >= 0)
                sb_apply_signed_shift = value <<< shift;
            else
                sb_apply_signed_shift = sb_round_shift_right_signed(value, int'(-shift));
        endfunction

        function automatic longint unsigned sb_round_shift_right_unsigned(
            input longint unsigned value,
            input int unsigned shift
        );
            if (shift == 0)
                sb_round_shift_right_unsigned = value;
            else
                sb_round_shift_right_unsigned = (value + (64'd1 << (shift - 1))) >> shift;
        endfunction

        function automatic longint unsigned sb_apply_unsigned_shift(
            input longint unsigned value,
            input int signed shift
        );
            if (shift >= 0)
                sb_apply_unsigned_shift = value << shift;
            else
                sb_apply_unsigned_shift = sb_round_shift_right_unsigned(value, int'(-shift));
        endfunction

        function automatic shortint signed sb_saturate_q8(input longint signed value);
            if (value > 64'sd32767)
                sb_saturate_q8 = 16'sh7FFF;
            else if (value < -64'sd32768)
                sb_saturate_q8 = 16'sh8000;
            else
                sb_saturate_q8 = value[15:0];
        endfunction

        function automatic byte signed sb_saturate_i8(input longint signed value);
            if (value > 64'sd127)
                sb_saturate_i8 = 8'sh7F;
            else if (value < -64'sd128)
                sb_saturate_i8 = 8'sh80;
            else
                sb_saturate_i8 = value[7:0];
        endfunction

        function automatic int sb_msb_index(input longint unsigned value);
            begin
                sb_msb_index = 0;
                for (int i = 0; i < 63; i++) begin
                    if (value[i])
                        sb_msb_index = i;
                end
            end
        endfunction

        function automatic shortint signed sb_fp16_to_q8(input bit [15:0] raw);
            bit sign;
            int exp_raw;
            int frac;
            int exp_unbiased;
            int shift;
            longint signed mant;
            longint signed scaled;
            begin
                sign = raw[15];
                exp_raw = raw[14:10];
                frac = raw[9:0];
                if (exp_raw == 31)
                    return sign ? 16'sh8000 : 16'sh7FFF;
                if (exp_raw == 0 && frac == 0)
                    return 16'sh0000;
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -14;
                end else begin
                    mant = 1024 + frac;
                    exp_unbiased = exp_raw - 15;
                end
                shift = exp_unbiased - 2;
                scaled = sb_apply_signed_shift(mant, shift);
                return sb_saturate_q8(sign ? -scaled : scaled);
            end
        endfunction

        function automatic shortint signed sb_bf16_to_q8(input bit [15:0] raw);
            bit sign;
            int exp_raw;
            int frac;
            int exp_unbiased;
            int shift;
            longint signed mant;
            longint signed scaled;
            begin
                sign = raw[15];
                exp_raw = raw[14:7];
                frac = raw[6:0];
                if (exp_raw == 255)
                    return sign ? 16'sh8000 : 16'sh7FFF;
                if (exp_raw == 0 && frac == 0)
                    return 16'sh0000;
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -126;
                end else begin
                    mant = 128 + frac;
                    exp_unbiased = exp_raw - 127;
                end
                shift = exp_unbiased + 1;
                scaled = sb_apply_signed_shift(mant, shift);
                return sb_saturate_q8(sign ? -scaled : scaled);
            end
        endfunction

        function automatic shortint signed sb_fp8_e4m3_to_q8(input bit [7:0] raw);
            bit sign;
            int exp_raw;
            int frac;
            int exp_unbiased;
            int shift;
            longint signed mant;
            longint signed scaled;
            begin
                sign = raw[7];
                exp_raw = raw[6:3];
                frac = raw[2:0];
                if (exp_raw == 15)
                    return sign ? 16'sh8000 : 16'sh7FFF;
                if (exp_raw == 0 && frac == 0)
                    return 16'sh0000;
                if (exp_raw == 0) begin
                    mant = frac;
                    exp_unbiased = -6;
                end else begin
                    mant = 8 + frac;
                    exp_unbiased = exp_raw - 7;
                end
                shift = exp_unbiased + 5;
                scaled = sb_apply_signed_shift(mant, shift);
                return sb_saturate_q8(sign ? -scaled : scaled);
            end
        endfunction

        function automatic bit [15:0] sb_q8_to_fp16(input shortint signed value);
            bit sign;
            longint unsigned mag;
            int exp_unbiased;
            int exp_raw;
            int shift;
            longint unsigned sig;
            begin
                if (value == 0)
                    return 16'h0000;
                sign = value[15];
                mag = sign ? longint'(-longint'(value)) : longint'(value);
                exp_unbiased = sb_msb_index(mag) - 8;
                if (exp_unbiased > 15)
                    return {sign, 5'd30, 10'h3FF};
                if (exp_unbiased < -14) begin
                    sig = sb_apply_unsigned_shift(mag, 16);
                    if (sig > 1023)
                        sig = 1023;
                    return {sign, 5'd0, sig[9:0]};
                end
                shift = 10 - exp_unbiased - 8;
                sig = sb_apply_unsigned_shift(mag, shift);
                if (sig >= 2048) begin
                    sig = sig >> 1;
                    exp_unbiased++;
                end
                exp_raw = exp_unbiased + 15;
                if (exp_raw >= 31)
                    return {sign, 5'd30, 10'h3FF};
                return {sign, exp_raw[4:0], sig[9:0]};
            end
        endfunction

        function automatic bit [15:0] sb_q8_to_bf16(input shortint signed value);
            bit sign;
            longint unsigned mag;
            int exp_unbiased;
            int exp_raw;
            int shift;
            longint unsigned sig;
            begin
                if (value == 0)
                    return 16'h0000;
                sign = value[15];
                mag = sign ? longint'(-longint'(value)) : longint'(value);
                exp_unbiased = sb_msb_index(mag) - 8;
                shift = 7 - exp_unbiased - 8;
                sig = sb_apply_unsigned_shift(mag, shift);
                if (sig >= 256) begin
                    sig = sig >> 1;
                    exp_unbiased++;
                end
                exp_raw = exp_unbiased + 127;
                if (exp_raw >= 255)
                    return {sign, 8'd254, 7'h7F};
                if (exp_raw <= 0)
                    return {sign, 8'd0, 7'd0};
                return {sign, exp_raw[7:0], sig[6:0]};
            end
        endfunction

        function automatic bit [7:0] sb_q8_to_fp8_e4m3(input shortint signed value);
            bit sign;
            longint unsigned mag;
            int exp_unbiased;
            int exp_raw;
            int shift;
            longint unsigned sig;
            begin
                if (value == 0)
                    return 8'h00;
                sign = value[15];
                mag = sign ? longint'(-longint'(value)) : longint'(value);
                exp_unbiased = sb_msb_index(mag) - 8;
                if (exp_unbiased < -6) begin
                    sig = sb_apply_unsigned_shift(mag, 1);
                    if (sig > 7)
                        sig = 7;
                    return {sign, 4'd0, sig[2:0]};
                end
                shift = 3 - exp_unbiased - 8;
                sig = sb_apply_unsigned_shift(mag, shift);
                if (sig >= 16) begin
                    sig = sig >> 1;
                    exp_unbiased++;
                end
                exp_raw = exp_unbiased + 7;
                if (exp_raw >= 15)
                    return {sign, 4'd14, 3'h7};
                return {sign, exp_raw[3:0], sig[2:0]};
            end
        endfunction

        function automatic bit [15:0] encode_external_from_q8(
            input int unsigned fmt,
            input shortint signed q8_value
        );
            byte signed i8;
            begin
                case (fmt)
                    FA_FORMAT_Q6_10: encode_external_from_q8 = sb_saturate_q8(longint'(q8_value) <<< 2);
                    FA_FORMAT_Q4_12: encode_external_from_q8 = sb_saturate_q8(longint'(q8_value) <<< 4);
                    FA_FORMAT_INT8_Q4_4: begin
                        i8 = sb_saturate_i8(sb_round_shift_right_signed(q8_value, 4));
                        encode_external_from_q8 = {8'h00, i8};
                    end
                    FA_FORMAT_FP8_E4M3: encode_external_from_q8 = {8'h00, sb_q8_to_fp8_e4m3(q8_value)};
                    FA_FORMAT_FP16:     encode_external_from_q8 = sb_q8_to_fp16(q8_value);
                    FA_FORMAT_BF16:     encode_external_from_q8 = sb_q8_to_bf16(q8_value);
                    default:            encode_external_from_q8 = q8_value[15:0];
                endcase
            end
        endfunction

        function automatic shortint signed decode_external_to_q8(
            input int unsigned fmt,
            input bit [15:0] raw
        );
            shortint signed raw_signed;
            byte signed i8;
            begin
                raw_signed = raw;
                i8 = raw[7:0];
                case (fmt)
                    FA_FORMAT_Q6_10:     decode_external_to_q8 = sb_saturate_q8(sb_round_shift_right_signed(raw_signed, 2));
                    FA_FORMAT_Q4_12:     decode_external_to_q8 = sb_saturate_q8(sb_round_shift_right_signed(raw_signed, 4));
                    FA_FORMAT_INT8_Q4_4: decode_external_to_q8 = sb_saturate_q8(longint'(i8) <<< 4);
                    FA_FORMAT_FP8_E4M3:  decode_external_to_q8 = sb_fp8_e4m3_to_q8(raw[7:0]);
                    FA_FORMAT_FP16:      decode_external_to_q8 = sb_fp16_to_q8(raw);
                    FA_FORMAT_BF16:      decode_external_to_q8 = sb_bf16_to_q8(raw);
                    default:             decode_external_to_q8 = raw_signed;
                endcase
            end
        endfunction

        function automatic real q8_to_real(input shortint signed value);
            q8_to_real = $itor(value) / 256.0;
        endfunction

        function automatic logic [31:0] dropout_hash(
            input fa_attention_job_item job,
            input int unsigned abs_row,
            input int unsigned abs_col
        );
            logic [31:0] h;
            begin
                h = job.dropout_seed ^ (32'(abs_row + 1) * 32'h9E37_79B1) ^
                    (32'(abs_col + 1) * 32'h85EB_CA6B);
                h = h ^ (h >> 16);
                h = h * 32'h7FEB_352D;
                h = h ^ (h >> 15);
                dropout_hash = h;
            end
        endfunction

        function automatic real apply_dropout_to_prob(
            input fa_attention_job_item job,
            input int unsigned abs_row,
            input int unsigned abs_col,
            input real prob
        );
            int unsigned rate;
            real keep_prob;
            begin
                rate = dropout_rate_eff(job);
                if (rate == 0 || prob == 0.0) begin
                    apply_dropout_to_prob = prob;
                end else if (dropout_hash(job, abs_row, abs_col)[7:0] < rate) begin
                    apply_dropout_to_prob = 0.0;
                end else begin
                    keep_prob = (256.0 - $itor(rate)) / 256.0;
                    apply_dropout_to_prob = prob / keep_prob;
                end
            end
        endfunction

        function automatic real mean_limit_for_jobs();
            real limit;
            begin
                limit = FA_MEAN_LIMIT;
                foreach (expected_jobs[j]) begin
                    if (format_eff(expected_jobs[j]) == FA_FORMAT_INT8_Q4_4 ||
                        format_eff(expected_jobs[j]) == FA_FORMAT_FP8_E4M3)
                        limit = 0.06;
                    if (expected_jobs[j].dropout_en)
                        limit = 0.08;
                end
                mean_limit_for_jobs = limit;
            end
        endfunction

        function automatic real max_limit_for_jobs();
            real limit;
            begin
                limit = FA_MAX_LIMIT;
                foreach (expected_jobs[j]) begin
                    if (format_eff(expected_jobs[j]) == FA_FORMAT_INT8_Q4_4 ||
                        format_eff(expected_jobs[j]) == FA_FORMAT_FP8_E4M3)
                        limit = 0.18;
                    if (expected_jobs[j].dropout_en)
                        limit = 0.22;
                end
                max_limit_for_jobs = limit;
            end
        endfunction

        function automatic shortint signed sample_raw(input int kind, input int unsigned job_id,
                                                       input int head, input int row, input int col);
            int val;
            begin
                case (kind)
                    0: val = (row * 13 + col * 7  + 3 + head * 19 + job_id * 23) % 64;
                    1: val = (row * 5  + col * 11 + 9 + head * 17 + job_id * 29) % 64;
                    default: val = (row * 17 + col * 3 + 1 + head * 13 + job_id * 31) % 64;
                endcase
                sample_raw = shortint'(val);
            end
        endfunction

        function automatic bit [63:0] tensor_addr(input bit [63:0] base,
                                                  input longint unsigned head_stride,
                                                  input int head,
                                                  input int row,
                                                  input int col);
            longint unsigned offset;
            begin
                offset = (head_stride * head) + ((row * FA_HEAD_DIM + col) * 2);
                tensor_addr = base + offset;
            end
        endfunction

        function automatic fa_attention_job_item clone_job(fa_attention_job_item job);
            fa_attention_job_item cloned;
            cloned = fa_attention_job_item::type_id::create("expected_job");
            cloned.q_base = job.q_base;
            cloned.k_base = job.k_base;
            cloned.v_base = job.v_base;
            cloned.o_base = job.o_base;
            cloned.causal_en = job.causal_en;
            cloned.stride_bytes = job.stride_bytes;
            cloned.neg_large = job.neg_large;
            cloned.scale = job.scale;
            cloned.valid_len = job.valid_len;
            cloned.head_count = job.head_count;
            cloned.head_stride_bytes = job.head_stride_bytes;
            cloned.format_mode = job.format_mode;
            cloned.dropout_en = job.dropout_en;
            cloned.dropout_rate = job.dropout_rate;
            cloned.dropout_seed = job.dropout_seed;
            cloned.job_id = job.job_id;
            clone_job = cloned;
        endfunction

        function void clear_expected_jobs();
            expected_jobs.delete();
        endfunction

        function void add_expected_job(fa_attention_job_item job);
            if (expected_jobs.size() >= FA_MAX_SCOREBOARD_JOBS)
                `uvm_fatal("JOBLIST", "Scoreboard expected job capacity exceeded")
            expected_jobs.push_back(clone_job(job));
        endfunction

        function automatic int find_expected_region(input bit is_write,
                                                    input bit [63:0] addr,
                                                    input longint unsigned bytes);
            longint unsigned stride;
            bit [63:0] q0;
            bit [63:0] k0;
            bit [63:0] v0;
            bit [63:0] o0;
            begin
                find_expected_region = -1;
                foreach (expected_jobs[j]) begin
                    stride = head_stride_eff(expected_jobs[j]);
                    for (int h = 0; h < head_count_eff(expected_jobs[j]); h++) begin
                        q0 = expected_jobs[j].q_base + (stride * h);
                        k0 = expected_jobs[j].k_base + (stride * h);
                        v0 = expected_jobs[j].v_base + (stride * h);
                        o0 = expected_jobs[j].o_base + (stride * h);
                        if (!is_write && addr >= q0 && (addr + bytes) <= (q0 + FA_TENSOR_BYTES))
                            return 0;
                        if (!is_write && addr >= k0 && (addr + bytes) <= (k0 + FA_TENSOR_BYTES))
                            return 1;
                        if (!is_write && addr >= v0 && (addr + bytes) <= (v0 + FA_TENSOR_BYTES))
                            return 2;
                        if (is_write && addr >= o0 && (addr + bytes) <= (o0 + FA_TENSOR_BYTES))
                            return 3;
                    end
                end
            end
        endfunction

        function void expected_dma_totals(output longint unsigned q_bytes,
                                          output longint unsigned k_bytes,
                                          output longint unsigned v_bytes,
                                          output longint unsigned o_bytes,
                                          output longint unsigned rd_bytes,
                                          output longint unsigned wr_bytes);
            int unsigned valid_len_local;
            int unsigned q_tiles;
            int unsigned max_kv;
            int unsigned q_last;
            begin
                q_bytes = 0;
                k_bytes = 0;
                v_bytes = 0;
                o_bytes = 0;
                foreach (expected_jobs[j]) begin
                    valid_len_local = valid_len_eff(expected_jobs[j]);
                    q_tiles = (valid_len_local + FA_TILE_BR - 1) / FA_TILE_BR;
                    for (int h = 0; h < head_count_eff(expected_jobs[j]); h++) begin
                        q_bytes += q_tiles * FA_TILE_QO_BYTES;
                        o_bytes += q_tiles * FA_TILE_QO_BYTES;
                        for (int qt = 0; qt < q_tiles; qt++) begin
                            q_last = qt * FA_TILE_BR + (FA_TILE_BR - 1);
                            if (q_last >= valid_len_local)
                                q_last = valid_len_local - 1;
                            if (expected_jobs[j].causal_en)
                                max_kv = q_last / FA_TILE_BC;
                            else
                                max_kv = ((valid_len_local + FA_TILE_BC - 1) / FA_TILE_BC) - 1;
                            k_bytes += (max_kv + 1) * FA_TILE_KV_BYTES;
                            v_bytes += (max_kv + 1) * FA_TILE_KV_BYTES;
                        end
                    end
                end
                rd_bytes = q_bytes + k_bytes + v_bytes;
                wr_bytes = o_bytes;
            end
        endfunction

        function void write_axil(fa_axil_reg_item tr);
            if (tr.write) begin
                axil_write_count++;
                if (tr.addr == FA_REG_CTRL && tr.data[FA_CTRL_START])
                    seen_start = 1'b1;
                if (tr.addr == FA_REG_STATUS && tr.data[FA_STATUS_DONE])
                    seen_done_clear = 1'b1;
            end else begin
                axil_read_count++;
                if (tr.addr == FA_REG_STATUS) begin
                    if (tr.rdata[FA_STATUS_DONE])
                        seen_done = 1'b1;
                    if (tr.rdata[FA_STATUS_ERROR])
                        seen_error = 1'b1;
                end
            end
        endfunction

        function void write_dma(fa_axi_dma_item tr);
            int region;
            region = find_expected_region(tr.is_write, tr.addr, tr.bytes);

            if (region < 0) begin
                `uvm_fatal("DMARANGE", $sformatf("DMA range outside expected tensors is_write=%0d addr=0x%016h bytes=%0d",
                    tr.is_write, tr.addr, tr.bytes))
            end

            if (tr.is_write) begin
                if (region != 3)
                    `uvm_fatal("DMARANGE", "AXI write burst was not in O region")
                dma_aw_count++;
                dma_o_write_bytes += tr.bytes;
                dma_total_write_bytes += tr.bytes;
            end else begin
                dma_ar_count++;
                dma_total_read_bytes += tr.bytes;
                case (region)
                    0: dma_q_read_bytes += tr.bytes;
                    1: dma_k_read_bytes += tr.bytes;
                    2: dma_v_read_bytes += tr.bytes;
                    default: `uvm_fatal("DMARANGE", "AXI read burst was not in Q/K/V region")
                endcase
            end
        endfunction

        function void clear_expected_axis();
            expected_axis_items.delete();
            axis_observed_count = 0;
        endfunction

        function void add_expected_axis(input bit [127:0] data, input bit [15:0] keep, input bit last);
            fa_axis_item tr;
            tr = fa_axis_item::type_id::create("expected_axis");
            tr.data = data;
            tr.keep = keep;
            tr.last = last;
            expected_axis_items.push_back(tr);
        endfunction

        function void write_axis(fa_axis_item tr);
            fa_axis_item exp;
            if (expected_axis_items.size() == 0)
                `uvm_fatal("AXISSB", $sformatf("Unexpected AXIS output data=0x%032h", tr.data))
            exp = expected_axis_items.pop_front();
            if (tr.data !== exp.data || tr.keep !== exp.keep || tr.last !== exp.last) begin
                `uvm_fatal("AXISSB", $sformatf(
                    "AXIS mismatch data actual=0x%032h expected=0x%032h keep actual=0x%04h expected=0x%04h last actual=%0d expected=%0d",
                    tr.data, exp.data, tr.keep, exp.keep, tr.last, exp.last))
            end
            axis_observed_count++;
        endfunction

        function void check_axis_complete(input int unsigned expected_count);
            if (axis_observed_count != expected_count || expected_axis_items.size() != 0) begin
                `uvm_fatal("AXISSB", $sformatf(
                    "AXIS observed_count=%0d expected_count=%0d remaining=%0d",
                    axis_observed_count, expected_count, expected_axis_items.size()))
            end
        endfunction

        function void reset_dma_stats();
            dma_q_read_bytes      = 0;
            dma_k_read_bytes      = 0;
            dma_v_read_bytes      = 0;
            dma_o_write_bytes     = 0;
            dma_total_read_bytes  = 0;
            dma_total_write_bytes = 0;
            dma_ar_count          = 0;
            dma_aw_count          = 0;
        endfunction

        task load_vectors_and_compute_golden(bit causal);
            fa_attention_job_item default_job;
            default_job = fa_attention_job_item::type_id::create("default_job");
            default_job.causal_en = causal;
            clear_expected_jobs();
            add_expected_job(default_job);
            load_job_vectors_and_compute_golden(default_job, 0);
        endtask

        task load_job_vectors_and_compute_golden(fa_attention_job_item job, int job_slot = 0);
            shortint signed q_raw;
            shortint signed k_raw;
            shortint signed v_raw;
            shortint signed q_q8;
            shortint signed k_q8;
            shortint signed v_q8;
            bit [15:0] q_ext;
            bit [15:0] k_ext;
            bit [15:0] v_ext;
            longint unsigned stride;

            `uvm_info("DATA", $sformatf("Loading job_id=%0d heads=%0d valid_len=%0d format=%0d dropout_en=%0d rate=%0d",
                job.job_id, head_count_eff(job), valid_len_eff(job), format_eff(job),
                job.dropout_en, dropout_rate_eff(job)), UVM_LOW)
            stride = head_stride_eff(job);
            for (int h = 0; h < head_count_eff(job); h++) begin
                for (int i = 0; i < FA_SEQ_LEN; i++) begin
                    for (int j = 0; j < FA_HEAD_DIM; j++) begin
                        q_raw = sample_raw(0, job.job_id, h, i, j);
                        k_raw = sample_raw(1, job.job_id, h, i, j);
                        v_raw = sample_raw(2, job.job_id, h, i, j);
                        q_ext = encode_external_from_q8(format_eff(job), q_raw);
                        k_ext = encode_external_from_q8(format_eff(job), k_raw);
                        v_ext = encode_external_from_q8(format_eff(job), v_raw);
                        q_q8 = decode_external_to_q8(format_eff(job), q_ext);
                        k_q8 = decode_external_to_q8(format_eff(job), k_ext);
                        v_q8 = decode_external_to_q8(format_eff(job), v_ext);
                        q_f[job_slot][h][i][j] = q8_to_real(q_q8);
                        k_f[job_slot][h][i][j] = q8_to_real(k_q8);
                        v_f[job_slot][h][i][j] = q8_to_real(v_q8);
                        mem_vif.write16(tensor_addr(job.q_base, stride, h, i, j), q_ext);
                        mem_vif.write16(tensor_addr(job.k_base, stride, h, i, j), k_ext);
                        mem_vif.write16(tensor_addr(job.v_base, stride, h, i, j), v_ext);
                        mem_vif.write16(tensor_addr(job.o_base, stride, h, i, j), 16'h0000);
                    end
                end
                compute_golden_for_head(job, h, job_slot);
            end
        endtask

        task compute_golden(bit causal);
            fa_attention_job_item default_job;
            default_job = fa_attention_job_item::type_id::create("default_golden_job");
            default_job.causal_en = causal;
            compute_golden_for_head(default_job, 0, 0);
        endtask

        task compute_golden_for_head(fa_attention_job_item job, int head, int job_slot = 0);
            real s_val;
            real row_max;
            real row_sum;
            real p_val;
            real scale;
            int unsigned valid_len_local;

            `uvm_info("GOLDEN", "Computing FP32 scaled dot-product attention golden model", UVM_LOW)
            scale = 1.0 / $sqrt(64.0);
            valid_len_local = valid_len_eff(job);
            for (int i = 0; i < FA_SEQ_LEN; i++) begin
                for (int k = 0; k < FA_HEAD_DIM; k++)
                    golden_o[job_slot][head][i][k] = 0.0;
                if (i >= valid_len_local)
                    continue;

                row_max = -1e30;
                for (int j = 0; j < valid_len_local; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[job_slot][head][i][k] * k_f[job_slot][head][j][k];
                    s_val *= scale;
                    if (job.causal_en && j > i)
                        s_val = -1e9;
                    if (s_val > row_max)
                        row_max = s_val;
                end

                row_sum = 0.0;
                for (int j = 0; j < valid_len_local; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[job_slot][head][i][k] * k_f[job_slot][head][j][k];
                    s_val *= scale;
                    if (job.causal_en && j > i)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max);
                    row_sum += p_val;
                end

                for (int j = 0; j < valid_len_local; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[job_slot][head][i][k] * k_f[job_slot][head][j][k];
                    s_val *= scale;
                    if (job.causal_en && j > i)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max) / row_sum;
                    p_val = apply_dropout_to_prob(job, i, j, p_val);
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        golden_o[job_slot][head][i][k] += p_val * v_f[job_slot][head][j][k];
                end
            end
        endtask

        task check_final_status(
            input bit [31:0] status_val,
            input bit        busy_seen,
            input bit [31:0] cycles_val,
            input bit [31:0] rd_bytes_val,
            input bit [31:0] wr_bytes_val
        );
            longint unsigned exp_q;
            longint unsigned exp_k;
            longint unsigned exp_v;
            longint unsigned exp_o;
            longint unsigned exp_rd;
            longint unsigned exp_wr;
            int unsigned cycle_limit;

            if (!status_val[FA_STATUS_DONE])
                `uvm_fatal("STATUS", $sformatf("STATUS.DONE was not set, STATUS=0x%08h", status_val))
            if (status_val[FA_STATUS_ERROR])
                `uvm_fatal("STATUS", $sformatf("STATUS.ERROR was set, STATUS=0x%08h", status_val))
            if (!busy_seen)
                `uvm_fatal("STATUS", "STATUS.BUSY was never observed during polling")
            if (!seen_start)
                `uvm_fatal("STATUS", "Scoreboard did not observe a CTRL.START write")

            last_cycles  = cycles_val;
            last_rd_bytes = rd_bytes_val;
            last_wr_bytes = wr_bytes_val;

            expected_dma_totals(exp_q, exp_k, exp_v, exp_o, exp_rd, exp_wr);
            cycle_limit = 300000;
            if (expected_jobs.size() != 0) begin
                cycle_limit = 300000 * head_count_eff(expected_jobs[0]);
                if (FA_SEQ_LEN > 256 || valid_len_eff(expected_jobs[0]) > 256)
                    cycle_limit = 700000 * head_count_eff(expected_jobs[0]);
            end
            if (cycles_val >= cycle_limit)
                `uvm_fatal("PERF", $sformatf("CYCLES=%0d, expected < %0d", cycles_val, cycle_limit))
            if (rd_bytes_val != exp_rd[31:0])
                `uvm_fatal("BYTES", $sformatf("RD_BYTES=%0d, expected %0d", rd_bytes_val, exp_rd))
            if (wr_bytes_val != exp_wr[31:0])
                `uvm_fatal("BYTES", $sformatf("WR_BYTES=%0d, expected %0d", wr_bytes_val, exp_wr))
        endtask

        task check_outputs_and_dma();
            logic [15:0] raw_o;
            shortint signed o_val;
            real dut_val;
            real gold_val;
            real abs_err;
            real row0_abs_err;
            real mean_limit;
            real max_limit;
            int err_count;
            longint unsigned stride;

            `uvm_info("CHECK", "Reading O memory and comparing against golden model", UVM_LOW)
            last_mean_err = 0.0;
            last_max_err = 0.0;
            last_row0_causal_err = 0.0;
            err_count = 0;
            mean_limit = mean_limit_for_jobs();
            max_limit = max_limit_for_jobs();

            foreach (expected_jobs[job_idx]) begin
                stride = head_stride_eff(expected_jobs[job_idx]);
                for (int h = 0; h < head_count_eff(expected_jobs[job_idx]); h++) begin
                    for (int i = 0; i < FA_SEQ_LEN; i++) begin
                        for (int j = 0; j < FA_HEAD_DIM; j++) begin
                            mem_vif.read16(tensor_addr(expected_jobs[job_idx].o_base, stride, h, i, j), raw_o);
                            o_val = decode_external_to_q8(format_eff(expected_jobs[job_idx]), raw_o);
                            dut_val = q8_to_real(o_val);
                            gold_val = golden_o[job_idx][h][i][j];
                            abs_err = dut_val - gold_val;
                            if (abs_err < 0.0)
                                abs_err = -abs_err;
                            last_mean_err += abs_err;
                            if (abs_err > last_max_err)
                                last_max_err = abs_err;

                            if (expected_jobs[job_idx].causal_en && i == 0) begin
                                row0_abs_err = dut_val - v_f[job_idx][h][0][j];
                                if (row0_abs_err < 0.0)
                                    row0_abs_err = -row0_abs_err;
                                if (row0_abs_err > last_row0_causal_err)
                                    last_row0_causal_err = row0_abs_err;
                            end
                            err_count++;
                        end
                    end
                end
            end

            last_mean_err = last_mean_err / $itor(err_count);

            if (last_mean_err > mean_limit)
                `uvm_fatal("GOLDEN", $sformatf("mean_abs_error=%0.6f, expected <= %0.6f", last_mean_err, mean_limit))
            if (last_max_err > max_limit)
                `uvm_fatal("GOLDEN", $sformatf("max_abs_error=%0.6f, expected <= %0.6f", last_max_err, max_limit))
            if (!expected_jobs[0].dropout_en && last_row0_causal_err > FA_CAUSAL_ROW0_LIMIT)
                `uvm_fatal("GOLDEN", $sformatf("row0_causal=%0.6f, expected <= %0.6f",
                    last_row0_causal_err, FA_CAUSAL_ROW0_LIMIT))

            check_dma_totals();
        endtask

        function void check_dma_totals();
            longint unsigned exp_q;
            longint unsigned exp_k;
            longint unsigned exp_v;
            longint unsigned exp_o;
            longint unsigned exp_rd;
            longint unsigned exp_wr;
            expected_dma_totals(exp_q, exp_k, exp_v, exp_o, exp_rd, exp_wr);
            if (dma_q_read_bytes != exp_q)
                `uvm_fatal("DMA", $sformatf("Q read bytes=%0d, expected %0d", dma_q_read_bytes, exp_q))
            if (dma_k_read_bytes != exp_k)
                `uvm_fatal("DMA", $sformatf("K read bytes=%0d, expected %0d", dma_k_read_bytes, exp_k))
            if (dma_v_read_bytes != exp_v)
                `uvm_fatal("DMA", $sformatf("V read bytes=%0d, expected %0d", dma_v_read_bytes, exp_v))
            if (dma_o_write_bytes != exp_o)
                `uvm_fatal("DMA", $sformatf("O write bytes=%0d, expected %0d", dma_o_write_bytes, exp_o))
            if (dma_total_read_bytes != exp_rd)
                `uvm_fatal("DMA", $sformatf("Total DMA read bytes=%0d, expected %0d", dma_total_read_bytes, exp_rd))
            if (dma_total_write_bytes != exp_wr)
                `uvm_fatal("DMA", $sformatf("Total DMA write bytes=%0d, expected %0d", dma_total_write_bytes, exp_wr))
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("FA_UVM_SUMMARY", $sformatf(
                "Cycles=%0d RD_BYTES=%0d WR_BYTES=%0d DMA_Q/K/V=%0d/%0d/%0d DMA_O=%0d AXI_AR/AW=%0d/%0d mean_abs_error=%0.6f max_abs_error=%0.6f row0_causal=%0.6f",
                last_cycles, last_rd_bytes, last_wr_bytes,
                dma_q_read_bytes, dma_k_read_bytes, dma_v_read_bytes,
                dma_o_write_bytes, dma_ar_count, dma_aw_count,
                last_mean_err, last_max_err, last_row0_causal_err), UVM_NONE)
        endfunction
    endclass

    class fa_uvm_coverage extends uvm_component;
        `uvm_component_utils(fa_uvm_coverage)

        uvm_analysis_imp_axil #(fa_axil_reg_item, fa_uvm_coverage) axil_export;
        uvm_analysis_imp_dma  #(fa_axi_dma_item,  fa_uvm_coverage) dma_export;

        covergroup reg_access_cg with function sample(bit is_write, bit [7:0] addr, bit [3:0] strb);
            option.per_instance = 1;
            cp_kind: coverpoint is_write {
                bins read  = {0};
                bins write = {1};
            }
            cp_addr: coverpoint addr {
                bins ctrl       = {FA_REG_CTRL};
                bins status     = {FA_REG_STATUS};
                bins cfg        = {FA_REG_CFG};
                bins q_base_l   = {FA_REG_Q_BASE_L};
                bins q_base_h   = {FA_REG_Q_BASE_H};
                bins k_base_l   = {FA_REG_K_BASE_L};
                bins k_base_h   = {FA_REG_K_BASE_H};
                bins v_base_l   = {FA_REG_V_BASE_L};
                bins v_base_h   = {FA_REG_V_BASE_H};
                bins o_base_l   = {FA_REG_O_BASE_L};
                bins o_base_h   = {FA_REG_O_BASE_H};
                bins stride     = {FA_REG_STRIDE_BYTES};
                bins neg_large  = {FA_REG_NEG_LARGE};
                bins scale      = {FA_REG_SCALE};
                bins cycles     = {FA_REG_CYCLES};
                bins rd_bytes   = {FA_REG_RD_BYTES};
                bins wr_bytes   = {FA_REG_WR_BYTES};
                bins valid_len  = {FA_REG_VALID_LEN};
                bins head_count = {FA_REG_HEAD_COUNT};
                bins head_stride = {FA_REG_HEAD_STRIDE};
                bins queue_status = {FA_REG_QUEUE_STATUS};
                bins format = {FA_REG_FORMAT};
                bins dropout_ctrl = {FA_REG_DROPOUT_CTRL};
                bins dropout_rate = {FA_REG_DROPOUT_RATE};
                bins dropout_seed = {FA_REG_DROPOUT_SEED};
            }
            cp_strb: coverpoint strb iff (is_write) {
                bins full     = {4'hF};
                bins low_half = {4'h3};
                bins byte0    = {4'h1};
                bins partial  = default;
            }
            cross cp_kind, cp_addr;
        endgroup

        covergroup flow_cg with function sample(int event_id);
            option.per_instance = 1;
            cp_event: coverpoint event_id {
                bins soft_reset = {0};
                bins start      = {1};
                bins busy       = {2};
                bins done       = {3};
                bins done_clear = {4};
                bins causal     = {5};
                bins error_free = {6};
                bins padding    = {7};
                bins multi_head = {8};
                bins queue      = {9};
                bins format     = {10};
                bins dropout    = {11};
                bins seq512     = {12};
                bins axis       = {13};
            }
        endgroup

        covergroup dma_cg with function sample(int region, bit is_write, int beats);
            option.per_instance = 1;
            cp_region: coverpoint region {
                bins q_read  = {0};
                bins k_read  = {1};
                bins v_read  = {2};
                bins o_write = {3};
            }
            cp_kind: coverpoint is_write {
                bins read  = {0};
                bins write = {1};
            }
            cp_beats: coverpoint beats {
                bins q_o_tile = {32};
                bins kv_tile  = {128};
            }
        endgroup

        covergroup axi_burst_cg with function sample(bit is_write, int beats, int size_code);
            option.per_instance = 1;
            cp_kind: coverpoint is_write {
                bins read  = {0};
                bins write = {1};
            }
            cp_beats: coverpoint beats {
                bins q_o_tile = {32};
                bins kv_tile  = {128};
                bins other    = default;
            }
            cp_size: coverpoint size_code {
                bins bytes16 = {4};
            }
        endgroup

        covergroup perf_cg with function sample(int cycles, int mean_bucket, int max_bucket, int causal_bucket);
            option.per_instance = 1;
            cp_cycles: coverpoint cycles {
                bins under_300k = {[0:299999]};
                bins under_600k = {[300000:599999]};
                bins over_600k = {[600000:$]};
            }
            cp_mean: coverpoint mean_bucket {
                bins pass = {0};
                illegal_bins fail = {1};
            }
            cp_max: coverpoint max_bucket {
                bins pass = {0};
                illegal_bins fail = {1};
            }
            cp_causal: coverpoint causal_bucket {
                bins pass = {0};
                illegal_bins fail = {1};
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axil_export  = new("axil_export", this);
            dma_export   = new("dma_export", this);
            reg_access_cg = new();
            flow_cg      = new();
            dma_cg       = new();
            axi_burst_cg = new();
            perf_cg      = new();
        endfunction

        function void write_axil(fa_axil_reg_item tr);
            reg_access_cg.sample(tr.write, tr.addr, tr.strb);
            if (tr.write && tr.addr == FA_REG_CTRL && tr.data[FA_CTRL_SOFT_RESET])
                flow_cg.sample(0);
            if (tr.write && tr.addr == FA_REG_CTRL && tr.data[FA_CTRL_START])
                flow_cg.sample(1);
            if (tr.write && tr.addr == FA_REG_STATUS && tr.data[FA_STATUS_DONE])
                flow_cg.sample(4);
            if (tr.write && tr.addr == FA_REG_CFG && tr.data[FA_CFG_CAUSAL_EN])
                flow_cg.sample(5);
            if (tr.write && tr.addr == FA_REG_VALID_LEN && tr.data != FA_SEQ_LEN)
                flow_cg.sample(7);
            if (tr.write && tr.addr == FA_REG_HEAD_COUNT && tr.data > 1)
                flow_cg.sample(8);
            if (!tr.write && tr.addr == FA_REG_QUEUE_STATUS && tr.rdata[15:8] >= 2)
                flow_cg.sample(9);
            if (tr.write && tr.addr == FA_REG_FORMAT && tr.data[2:0] != FA_FORMAT_Q8_8)
                flow_cg.sample(10);
            if (tr.write && tr.addr == FA_REG_DROPOUT_CTRL && tr.data[0])
                flow_cg.sample(11);
            if (tr.write && tr.addr == FA_REG_VALID_LEN && tr.data > 256)
                flow_cg.sample(12);
            if (!tr.write && tr.addr == FA_REG_STATUS) begin
                if (tr.rdata[FA_STATUS_BUSY])
                    flow_cg.sample(2);
                if (tr.rdata[FA_STATUS_DONE])
                    flow_cg.sample(3);
                if (!tr.rdata[FA_STATUS_ERROR])
                    flow_cg.sample(6);
            end
        endfunction

        function void write_dma(fa_axi_dma_item tr);
            int region;
            region = fa_dma_region(tr.is_write, tr.addr, tr.bytes);
            if (region >= 0)
                dma_cg.sample(region, tr.is_write, tr.beats);
            axi_burst_cg.sample(tr.is_write, tr.beats, tr.size);
        endfunction

        function void sample_perf(int cycles, real mean_err, real max_err, real causal_err);
            perf_cg.sample(cycles,
                (mean_err <= 0.10) ? 0 : 1,
                (max_err <= 0.25) ? 0 : 1,
                (causal_err <= 0.25) ? 0 : 1);
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("FA_UVM_COVERAGE", $sformatf(
                "Functional coverage reg/flow/dma/axi/perf: %0.2f %0.2f %0.2f %0.2f %0.2f",
                reg_access_cg.get_inst_coverage(), flow_cg.get_inst_coverage(),
                dma_cg.get_inst_coverage(), axi_burst_cg.get_inst_coverage(),
                perf_cg.get_inst_coverage()), UVM_NONE)
        endfunction
    endclass

    class fa_uvm_env extends uvm_env;
        `uvm_component_utils(fa_uvm_env)

        virtual fa_axil_if        axil_vif;
        virtual fa_axi4_master_if axi_vif;
        virtual fa_mem_access_if  mem_vif;
        virtual fa_axis_if        axis_vif;

        fa_axil_agent    axil_agent;
        fa_axi_dma_agent dma_agent;
        fa_axis_monitor  axis_monitor;
        fa_uvm_scoreboard scoreboard;
        fa_uvm_coverage   coverage;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_axil_if)::get(this, "", "axil_vif", axil_vif))
                `uvm_fatal("NOVIF", "fa_uvm_env requires axil_vif")
            if (!uvm_config_db#(virtual fa_axi4_master_if)::get(this, "", "axi_vif", axi_vif))
                `uvm_fatal("NOVIF", "fa_uvm_env requires axi_vif")
            if (!uvm_config_db#(virtual fa_mem_access_if)::get(this, "", "mem_vif", mem_vif))
                `uvm_fatal("NOVIF", "fa_uvm_env requires mem_vif")
            if (!uvm_config_db#(virtual fa_axis_if)::get(this, "", "axis_vif", axis_vif))
                `uvm_fatal("NOVIF", "fa_uvm_env requires axis_vif")

            axil_agent = fa_axil_agent::type_id::create("axil_agent", this);
            dma_agent  = fa_axi_dma_agent::type_id::create("dma_agent", this);
            axis_monitor = fa_axis_monitor::type_id::create("axis_monitor", this);
            scoreboard = fa_uvm_scoreboard::type_id::create("scoreboard", this);
            coverage   = fa_uvm_coverage::type_id::create("coverage", this);
            axil_agent.is_active = UVM_ACTIVE;
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            axil_agent.monitor.ap.connect(scoreboard.axil_export);
            axil_agent.monitor.ap.connect(coverage.axil_export);
            dma_agent.monitor.ap.connect(scoreboard.dma_export);
            dma_agent.monitor.ap.connect(coverage.dma_export);
            axis_monitor.ap.connect(scoreboard.axis_export);
        endfunction
    endclass

    class fa_axil_base_sequence extends uvm_sequence #(fa_axil_reg_item);
        `uvm_object_utils(fa_axil_base_sequence)

        function new(string name = "fa_axil_base_sequence");
            super.new(name);
        endfunction

        task automatic axil_write(input bit [7:0] addr, input bit [31:0] data, input bit [3:0] strb = 4'hF);
            fa_axil_reg_item tr;
            tr = fa_axil_reg_item::type_id::create("wr");
            tr.write = 1'b1;
            tr.addr  = addr;
            tr.data  = data;
            tr.strb  = strb;
            start_item(tr);
            finish_item(tr);
            if (tr.resp != 2'b00)
                `uvm_fatal("AXIL", $sformatf("AXI4-Lite write failed addr=0x%02h resp=%0d", addr, tr.resp))
        endtask

        task automatic axil_read(input bit [7:0] addr, output bit [31:0] data);
            fa_axil_reg_item tr;
            tr = fa_axil_reg_item::type_id::create("rd");
            tr.write = 1'b0;
            tr.addr  = addr;
            tr.data  = '0;
            tr.strb  = 4'h0;
            start_item(tr);
            finish_item(tr);
            if (tr.resp != 2'b00)
                `uvm_fatal("AXIL", $sformatf("AXI4-Lite read failed addr=0x%02h resp=%0d", addr, tr.resp))
            data = tr.rdata;
        endtask

        task automatic axil_read_check(input bit [7:0] addr, input bit [31:0] expected, input string name);
            bit [31:0] actual;
            axil_read(addr, actual);
            if (actual !== expected)
                `uvm_fatal("REGCHECK", $sformatf("%s failed addr=0x%02h actual=0x%08h expected=0x%08h",
                    name, addr, actual, expected))
        endtask

        task automatic program_attention_job(input fa_attention_job_item job);
            axil_write(FA_REG_Q_BASE_L, job.q_base[31:0]);
            axil_write(FA_REG_Q_BASE_H, job.q_base[63:32]);
            axil_write(FA_REG_K_BASE_L, job.k_base[31:0]);
            axil_write(FA_REG_K_BASE_H, job.k_base[63:32]);
            axil_write(FA_REG_V_BASE_L, job.v_base[31:0]);
            axil_write(FA_REG_V_BASE_H, job.v_base[63:32]);
            axil_write(FA_REG_O_BASE_L, job.o_base[31:0]);
            axil_write(FA_REG_O_BASE_H, job.o_base[63:32]);
            axil_write(FA_REG_STRIDE_BYTES, job.stride_bytes);
            axil_write(FA_REG_NEG_LARGE, job.neg_large);
            axil_write(FA_REG_SCALE, job.scale);
            axil_write(FA_REG_VALID_LEN, job.valid_len);
            axil_write(FA_REG_HEAD_COUNT, job.head_count);
            axil_write(FA_REG_HEAD_STRIDE, job.head_stride_bytes);
            axil_write(FA_REG_FORMAT, job.format_mode);
            axil_write(FA_REG_DROPOUT_CTRL, {31'd0, job.dropout_en});
            axil_write(FA_REG_DROPOUT_RATE, job.dropout_rate);
            axil_write(FA_REG_DROPOUT_SEED, job.dropout_seed);
            axil_write(FA_REG_CFG, {31'd0, job.causal_en});
        endtask
    endclass

    class fa_uvm_reg_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_reg_sequence)

        fa_uvm_env env;

        function new(string name = "fa_uvm_reg_sequence");
            super.new(name);
        endfunction

        task body();
            `uvm_info("REGSEQ", "Checking reset defaults, RW, RO, W1C, byte strobe, and soft reset behavior", UVM_LOW)
            axil_read_check(FA_REG_CTRL,         32'h0000_0000, "CTRL reset");
            axil_read_check(FA_REG_STATUS,       32'h0000_0000, "STATUS reset");
            axil_read_check(FA_REG_CFG,          32'h0000_0000, "CFG reset");
            axil_read_check(FA_REG_Q_BASE_L,     32'h0000_0000, "Q_BASE_L reset");
            axil_read_check(FA_REG_Q_BASE_H,     32'h0000_0000, "Q_BASE_H reset");
            axil_read_check(FA_REG_K_BASE_L,     32'h0000_0000, "K_BASE_L reset");
            axil_read_check(FA_REG_K_BASE_H,     32'h0000_0000, "K_BASE_H reset");
            axil_read_check(FA_REG_V_BASE_L,     32'h0000_0000, "V_BASE_L reset");
            axil_read_check(FA_REG_V_BASE_H,     32'h0000_0000, "V_BASE_H reset");
            axil_read_check(FA_REG_O_BASE_L,     32'h0000_0000, "O_BASE_L reset");
            axil_read_check(FA_REG_O_BASE_H,     32'h0000_0000, "O_BASE_H reset");
            axil_read_check(FA_REG_STRIDE_BYTES, 32'd128,       "STRIDE reset");
            axil_read_check(FA_REG_NEG_LARGE,    32'hFFFF_8000, "NEG_LARGE reset");
            axil_read_check(FA_REG_SCALE,        32'h0000_0020, "SCALE reset");
            axil_read_check(FA_REG_CYCLES,       32'h0000_0000, "CYCLES reset");
            axil_read_check(FA_REG_RD_BYTES,     32'h0000_0000, "RD_BYTES reset");
            axil_read_check(FA_REG_WR_BYTES,     32'h0000_0000, "WR_BYTES reset");
            axil_read_check(FA_REG_VALID_LEN,    32'(FA_SEQ_LEN), "VALID_LEN reset");
            axil_read_check(FA_REG_HEAD_COUNT,   32'd1,         "HEAD_COUNT reset");
            axil_read_check(FA_REG_HEAD_STRIDE,  32'(FA_TENSOR_BYTES), "HEAD_STRIDE reset");
            axil_read_check(FA_REG_QUEUE_STATUS, 32'h0000_0000, "QUEUE_STATUS reset");
            axil_read_check(FA_REG_FORMAT,       32'h0000_0000, "FORMAT reset");
            axil_read_check(FA_REG_DROPOUT_CTRL, 32'h0000_0000, "DROPOUT_CTRL reset");
            axil_read_check(FA_REG_DROPOUT_RATE, 32'h0000_0000, "DROPOUT_RATE reset");
            axil_read_check(FA_REG_DROPOUT_SEED, 32'h0000_0001, "DROPOUT_SEED reset");

            axil_write(FA_REG_CFG, 32'h0000_0001);
            axil_read_check(FA_REG_CFG, 32'h0000_0001, "CFG causal write");

            axil_write(FA_REG_Q_BASE_L, 32'h1122_3344);
            axil_read_check(FA_REG_Q_BASE_L, 32'h1122_3344, "Q_BASE_L full write");
            axil_write(FA_REG_Q_BASE_L, 32'h0000_AA55, 4'h3);
            axil_read_check(FA_REG_Q_BASE_L, 32'h1122_AA55, "Q_BASE_L byte strobe");

            axil_write(FA_REG_NEG_LARGE, 32'hFFFF_9000);
            axil_read_check(FA_REG_NEG_LARGE, 32'hFFFF_9000, "NEG_LARGE write");
            axil_write(FA_REG_SCALE, 32'h0000_0020);
            axil_read_check(FA_REG_SCALE, 32'h0000_0020, "SCALE write");
            axil_write(FA_REG_SCALE, 32'h0000_0021, 4'h1);
            axil_read_check(FA_REG_SCALE, 32'h0000_0021, "SCALE byte0 strobe");
            axil_write(FA_REG_VALID_LEN, 32'd130);
            axil_read_check(FA_REG_VALID_LEN, 32'd130, "VALID_LEN write");
            axil_write(FA_REG_HEAD_COUNT, 32'd2);
            axil_read_check(FA_REG_HEAD_COUNT, 32'd2, "HEAD_COUNT write");
            axil_write(FA_REG_HEAD_STRIDE, 32'(FA_TENSOR_BYTES));
            axil_read_check(FA_REG_HEAD_STRIDE, 32'(FA_TENSOR_BYTES), "HEAD_STRIDE write");
            axil_write(FA_REG_FORMAT, 32'(FA_FORMAT_Q6_10));
            axil_read_check(FA_REG_FORMAT, 32'(FA_FORMAT_Q6_10), "FORMAT write");
            axil_write(FA_REG_DROPOUT_CTRL, 32'h0000_0001);
            axil_read_check(FA_REG_DROPOUT_CTRL, 32'h0000_0001, "DROPOUT_CTRL write");
            axil_write(FA_REG_DROPOUT_RATE, 32'd64);
            axil_read_check(FA_REG_DROPOUT_RATE, 32'd64, "DROPOUT_RATE write");
            axil_write(FA_REG_DROPOUT_SEED, 32'hCAFE_1234);
            axil_read_check(FA_REG_DROPOUT_SEED, 32'hCAFE_1234, "DROPOUT_SEED write");

            axil_write(FA_REG_CYCLES, 32'hDEAD_BEEF);
            axil_read_check(FA_REG_CYCLES, 32'h0000_0000, "CYCLES RO write ignored");
            axil_write(FA_REG_RD_BYTES, 32'hCAFE_BABE);
            axil_read_check(FA_REG_RD_BYTES, 32'h0000_0000, "RD_BYTES RO write ignored");
            axil_write(FA_REG_WR_BYTES, 32'hFEED_1234);
            axil_read_check(FA_REG_WR_BYTES, 32'h0000_0000, "WR_BYTES RO write ignored");

            axil_write(FA_REG_STATUS, 32'h0000_0002);
            axil_read_check(FA_REG_STATUS, 32'h0000_0000, "STATUS W1C before done");

            axil_write(FA_REG_CTRL, 32'h0000_0002);
            if (env != null) begin
                repeat (4) @(posedge env.axil_vif.clk);
            end
            axil_read_check(FA_REG_CTRL,   32'h0000_0000, "CTRL soft_reset pulse");
            axil_read_check(FA_REG_STATUS, 32'h0000_0000, "STATUS after soft_reset");
            `uvm_info("REGSEQ", "Register model checks passed", UVM_LOW)
        endtask
    endclass

    class fa_uvm_attention_job_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_attention_job_sequence)

        fa_uvm_env env;
        fa_attention_job_item job;

        function new(string name = "fa_uvm_attention_job_sequence");
            super.new(name);
            job = fa_attention_job_item::type_id::create("job");
        endfunction

        task body();
            bit [31:0] status_val;
            bit [31:0] cycles_val;
            bit [31:0] rd_bytes_val;
            bit [31:0] wr_bytes_val;
            int timeout_cnt;
            bit busy_seen;

            if (env == null)
                `uvm_fatal("NOENV", "fa_uvm_attention_job_sequence requires env handle")

            env.scoreboard.reset_dma_stats();
            env.scoreboard.clear_expected_jobs();
            env.scoreboard.add_expected_job(job);
            env.scoreboard.load_job_vectors_and_compute_golden(job, 0);

            `uvm_info("JOBSEQ", "Programming attention job registers", UVM_LOW)
            program_attention_job(job);

            `uvm_info("JOBSEQ", "Starting DUT and polling STATUS.DONE", UVM_LOW)
            axil_write(FA_REG_CTRL, 32'h0000_0001);

            timeout_cnt = 0;
            status_val = 32'h0;
            busy_seen = 1'b0;
            while (!status_val[FA_STATUS_DONE] && timeout_cnt < 1000000) begin
                repeat (100) @(posedge env.axil_vif.clk);
                axil_read(FA_REG_STATUS, status_val);
                timeout_cnt += 100;
                if (status_val[FA_STATUS_BUSY])
                    busy_seen = 1'b1;
                if ((timeout_cnt % 50000) == 0)
                    `uvm_info("JOBSEQ", $sformatf("poll_cycles=%0d STATUS=0x%08h", timeout_cnt, status_val), UVM_LOW)
            end

            if (!status_val[FA_STATUS_DONE])
                `uvm_fatal("TIMEOUT", $sformatf("Timed out waiting for STATUS.DONE, STATUS=0x%08h", status_val))

            axil_read(FA_REG_CYCLES, cycles_val);
            axil_read(FA_REG_RD_BYTES, rd_bytes_val);
            axil_read(FA_REG_WR_BYTES, wr_bytes_val);

            env.scoreboard.check_final_status(status_val, busy_seen, cycles_val, rd_bytes_val, wr_bytes_val);
            env.scoreboard.check_outputs_and_dma();
            env.coverage.sample_perf(cycles_val,
                env.scoreboard.last_mean_err,
                env.scoreboard.last_max_err,
                env.scoreboard.last_row0_causal_err);

            axil_write(FA_REG_STATUS, 32'h0000_0002);
            axil_read(FA_REG_STATUS, status_val);
            if (status_val[FA_STATUS_DONE])
                `uvm_fatal("STATUS", "STATUS.DONE did not clear after W1C write")

            `uvm_info("JOBSEQ", $sformatf(
                "UVM causal E2E PASS cycles=%0d rd_bytes=%0d wr_bytes=%0d mean_abs_error=%0.6f max_abs_error=%0.6f row0_causal=%0.6f",
                cycles_val, rd_bytes_val, wr_bytes_val,
                env.scoreboard.last_mean_err, env.scoreboard.last_max_err,
                env.scoreboard.last_row0_causal_err), UVM_NONE)
        endtask
    endclass

    class fa_uvm_causal_e2e_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_causal_e2e_sequence)

        fa_uvm_env env;

        function new(string name = "fa_uvm_causal_e2e_sequence");
            super.new(name);
        endfunction

        task body();
            fa_uvm_reg_sequence reg_seq;
            fa_uvm_attention_job_sequence job_seq;

            if (env == null)
                `uvm_fatal("NOENV", "fa_uvm_causal_e2e_sequence requires env handle")

            wait (env.axil_vif.rst_n === 1'b1);
            repeat (10) @(posedge env.axil_vif.clk);

            reg_seq = fa_uvm_reg_sequence::type_id::create("reg_seq");
            reg_seq.env = env;
            reg_seq.start(m_sequencer);

            job_seq = fa_uvm_attention_job_sequence::type_id::create("job_seq");
            job_seq.env = env;
            job_seq.start(m_sequencer);
        endtask
    endclass

    class fa_uvm_bonus_job_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_bonus_job_sequence)

        fa_uvm_env env;
        fa_attention_job_item job;

        function new(string name = "fa_uvm_bonus_job_sequence");
            super.new(name);
            job = fa_attention_job_item::type_id::create("job");
        endfunction

        task body();
            fa_uvm_attention_job_sequence job_seq;
            if (env == null)
                `uvm_fatal("NOENV", "fa_uvm_bonus_job_sequence requires env handle")
            wait (env.axil_vif.rst_n === 1'b1);
            repeat (10) @(posedge env.axil_vif.clk);
            job_seq = fa_uvm_attention_job_sequence::type_id::create("job_seq");
            job_seq.env = env;
            job_seq.job = job;
            job_seq.start(m_sequencer);
        endtask
    endclass

    class fa_uvm_axis_smoke_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_axis_smoke_sequence)

        fa_uvm_env env;

        function new(string name = "fa_uvm_axis_smoke_sequence");
            super.new(name);
        endfunction

        task automatic drive_axis_beat(input bit [127:0] data, input bit [15:0] keep, input bit last);
            @(posedge env.axis_vif.clk);
            env.axis_vif.s_tdata  <= data;
            env.axis_vif.s_tkeep  <= keep;
            env.axis_vif.s_tlast  <= last;
            env.axis_vif.s_tvalid <= 1'b1;
            do begin
                @(posedge env.axis_vif.clk);
            end while (!env.axis_vif.s_tready);
            env.axis_vif.s_tvalid <= 1'b0;
            env.axis_vif.s_tlast  <= 1'b0;
        endtask

        task body();
            const int NUM_BEATS = 8;
            int timeout_cnt;

            if (env == null)
                `uvm_fatal("NOENV", "fa_uvm_axis_smoke_sequence requires env handle")

            wait (env.axis_vif.rst_n === 1'b1);
            repeat (10) @(posedge env.axis_vif.clk);
            env.scoreboard.clear_expected_axis();
            env.axis_vif.s_tdata  <= '0;
            env.axis_vif.s_tkeep  <= '0;
            env.axis_vif.s_tlast  <= 1'b0;
            env.axis_vif.s_tvalid <= 1'b0;
            env.axis_vif.m_tready <= 1'b0;

            fork
                begin
                    forever begin
                        @(posedge env.axis_vif.clk);
                        env.axis_vif.m_tready <= (($time / 2) % 5) != 1;
                    end
                end
            join_none

            for (int i = 0; i < NUM_BEATS; i++) begin
                bit [127:0] data;
                bit [15:0] keep;
                bit last;
                data = {32'hA500_0000 | i[31:0], 32'h5A00_1000 | i[31:0],
                        32'hC300_2000 | i[31:0], 32'h3C00_3000 | i[31:0]};
                keep = (i == NUM_BEATS - 1) ? 16'h00FF : 16'hFFFF;
                last = (i == NUM_BEATS - 1);
                env.scoreboard.add_expected_axis(data, keep, last);
                drive_axis_beat(data, keep, last);
                repeat ((i % 3) + 1) @(posedge env.axis_vif.clk);
            end

            timeout_cnt = 0;
            while (env.scoreboard.axis_observed_count < NUM_BEATS && timeout_cnt < 1000) begin
                @(posedge env.axis_vif.clk);
                timeout_cnt++;
            end
            env.scoreboard.check_axis_complete(NUM_BEATS);
            env.coverage.flow_cg.sample(13);
            env.axis_vif.m_tready <= 1'b0;
            `uvm_info("AXISSEQ", $sformatf("AXI4-Stream bridge PASS beats=%0d", NUM_BEATS), UVM_NONE)
        endtask
    endclass

    class fa_uvm_task_queue_sequence extends fa_axil_base_sequence;
        `uvm_object_utils(fa_uvm_task_queue_sequence)

        fa_uvm_env env;

        function new(string name = "fa_uvm_task_queue_sequence");
            super.new(name);
        endfunction

        task body();
            fa_attention_job_item job0;
            fa_attention_job_item job1;
            bit [31:0] status_val;
            bit [31:0] queue_status;
            bit [31:0] cycles_val;
            bit [31:0] rd_bytes_val;
            bit [31:0] wr_bytes_val;
            int timeout_cnt;
            bit busy_seen;

            if (env == null)
                `uvm_fatal("NOENV", "fa_uvm_task_queue_sequence requires env handle")
            wait (env.axil_vif.rst_n === 1'b1);
            repeat (10) @(posedge env.axil_vif.clk);

            job0 = fa_attention_job_item::type_id::create("job0");
            job1 = fa_attention_job_item::type_id::create("job1");
            job0.valid_len = 32'd64;
            job0.job_id = 0;
            job1.q_base = FA_Q_BASE_JOB1;
            job1.k_base = FA_K_BASE_JOB1;
            job1.v_base = FA_V_BASE_JOB1;
            job1.o_base = FA_O_BASE_JOB1;
            job1.valid_len = 32'd64;
            job1.job_id = 1;

            env.scoreboard.reset_dma_stats();
            env.scoreboard.clear_expected_jobs();
            env.scoreboard.add_expected_job(job0);
            env.scoreboard.add_expected_job(job1);
            env.scoreboard.load_job_vectors_and_compute_golden(job0, 0);
            env.scoreboard.load_job_vectors_and_compute_golden(job1, 1);

            `uvm_info("QUEUESEQ", "Starting job0, then enqueueing job1 while DUT is busy", UVM_LOW)
            program_attention_job(job0);
            axil_write(FA_REG_CTRL, 32'h0000_0001);

            busy_seen = 1'b0;
            for (int i = 0; i < 20; i++) begin
                repeat (20) @(posedge env.axil_vif.clk);
                axil_read(FA_REG_STATUS, status_val);
                if (status_val[FA_STATUS_BUSY])
                    busy_seen = 1'b1;
            end
            if (!busy_seen)
                `uvm_fatal("QUEUE", "Job0 did not enter BUSY before enqueue attempt")

            program_attention_job(job1);
            axil_write(FA_REG_CTRL, 32'h0000_0001);

            timeout_cnt = 0;
            queue_status = 32'h0;
            while (queue_status[15:8] < 8'd2 && timeout_cnt < 1000000) begin
                repeat (100) @(posedge env.axil_vif.clk);
                axil_read(FA_REG_QUEUE_STATUS, queue_status);
                axil_read(FA_REG_STATUS, status_val);
                if (status_val[FA_STATUS_ERROR])
                    `uvm_fatal("QUEUE", $sformatf("STATUS.ERROR set during queue run STATUS=0x%08h QSTAT=0x%08h",
                        status_val, queue_status))
                timeout_cnt += 100;
            end
            if (queue_status[15:8] < 8'd2)
                `uvm_fatal("QUEUE", $sformatf("Timed out waiting for two completed jobs, QUEUE_STATUS=0x%08h",
                    queue_status))

            axil_read(FA_REG_CYCLES, cycles_val);
            axil_read(FA_REG_RD_BYTES, rd_bytes_val);
            axil_read(FA_REG_WR_BYTES, wr_bytes_val);
            env.scoreboard.last_cycles = cycles_val;
            env.scoreboard.last_rd_bytes = rd_bytes_val;
            env.scoreboard.last_wr_bytes = wr_bytes_val;
            env.scoreboard.check_outputs_and_dma();
            env.coverage.sample_perf(cycles_val,
                env.scoreboard.last_mean_err,
                env.scoreboard.last_max_err,
                env.scoreboard.last_row0_causal_err);

            axil_write(FA_REG_STATUS, 32'h0000_0002);
            `uvm_info("QUEUESEQ", $sformatf(
                "UVM task queue PASS queue_status=0x%08h aggregate_dma_rd=%0d aggregate_dma_wr=%0d mean_abs_error=%0.6f max_abs_error=%0.6f",
                queue_status, env.scoreboard.dma_total_read_bytes,
                env.scoreboard.dma_total_write_bytes,
                env.scoreboard.last_mean_err, env.scoreboard.last_max_err), UVM_NONE)
        endtask
    endclass

    class fa_uvm_base_test extends uvm_test;
        `uvm_component_utils(fa_uvm_base_test)

        fa_uvm_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = fa_uvm_env::type_id::create("env", this);
        endfunction
    endclass

    class fa_uvm_causal_e2e_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_causal_e2e_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_causal_e2e_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_causal_e2e_sequence::type_id::create("seq");
            seq.env = env;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM VERIFICATION TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_smoke_test extends fa_uvm_causal_e2e_test;
        `uvm_component_utils(fa_uvm_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class fa_uvm_padding_mask_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_padding_mask_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_bonus_job_sequence::type_id::create("seq");
            seq.env = env;
            seq.job.valid_len = 32'd130;
            seq.job.job_id = 0;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM PADDING MASK TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_multi_head_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_multi_head_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_bonus_job_sequence::type_id::create("seq");
            seq.env = env;
            seq.job.head_count = 32'd2;
            seq.job.head_stride_bytes = 32'(FA_TENSOR_BYTES);
            seq.job.valid_len = FA_SEQ_LEN;
            seq.job.job_id = 0;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM MULTI-HEAD TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_task_queue_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_task_queue_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_task_queue_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_task_queue_sequence::type_id::create("seq");
            seq.env = env;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM TASK QUEUE TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_bf16_fp16_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_bf16_fp16_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            for (int fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
                seq = fa_uvm_bonus_job_sequence::type_id::create($sformatf("seq_fp_%0d", fmt_idx));
                seq.env = env;
                seq.job.valid_len = 32'd64;
                seq.job.format_mode = (fmt_idx == 0) ? FA_FORMAT_FP16 : FA_FORMAT_BF16;
                seq.job.job_id = fmt_idx;
                seq.start(env.axil_agent.sequencer);
            end
            `uvm_info("FA_UVM_PASS", ">>> UVM BF16/FP16 EXTERNAL I/O FORMAT TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_fixed_format_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_fixed_format_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            for (int fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
                seq = fa_uvm_bonus_job_sequence::type_id::create($sformatf("seq_fixed_%0d", fmt_idx));
                seq.env = env;
                seq.job.valid_len = 32'd64;
                seq.job.format_mode = (fmt_idx == 0) ? FA_FORMAT_Q6_10 : FA_FORMAT_Q4_12;
                seq.job.job_id = fmt_idx;
                seq.start(env.axil_agent.sequencer);
            end
            `uvm_info("FA_UVM_PASS", ">>> UVM Q6.10/Q4.12 FORMAT TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_int8_fp8_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_int8_fp8_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            for (int fmt_idx = 0; fmt_idx < 2; fmt_idx++) begin
                seq = fa_uvm_bonus_job_sequence::type_id::create($sformatf("seq_lowp_%0d", fmt_idx));
                seq.env = env;
                seq.job.valid_len = 32'd64;
                seq.job.format_mode = (fmt_idx == 0) ? FA_FORMAT_INT8_Q4_4 : FA_FORMAT_FP8_E4M3;
                seq.job.job_id = fmt_idx;
                seq.start(env.axil_agent.sequencer);
            end
            `uvm_info("FA_UVM_PASS", ">>> UVM INT8/FP8 EXTERNAL I/O FORMAT TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_dropout_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_dropout_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_bonus_job_sequence::type_id::create("seq_dropout");
            seq.env = env;
            seq.job.valid_len = 32'd64;
            seq.job.dropout_en = 1'b1;
            seq.job.dropout_rate = 32'd64;
            seq.job.dropout_seed = 32'hC0DE_5EED;
            seq.job.job_id = 0;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM DETERMINISTIC DROPOUT TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_seq512_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_seq512_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_bonus_job_sequence seq;
            phase.raise_objection(this);
            if (FA_SEQ_LEN < 512)
                `uvm_fatal("SEQ512", $sformatf("fa_uvm_seq512_test requires FA_SEQ_LEN>=512, got %0d", FA_SEQ_LEN))
            seq = fa_uvm_bonus_job_sequence::type_id::create("seq512");
            seq.env = env;
            seq.job.valid_len = 32'd260;
            seq.job.job_id = 0;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM SEQ_LEN=512 BOUNDED TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass

    class fa_uvm_axis_smoke_test extends fa_uvm_base_test;
        `uvm_component_utils(fa_uvm_axis_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            fa_uvm_axis_smoke_sequence seq;
            phase.raise_objection(this);
            seq = fa_uvm_axis_smoke_sequence::type_id::create("seq_axis");
            seq.env = env;
            seq.start(env.axil_agent.sequencer);
            `uvm_info("FA_UVM_PASS", ">>> UVM AXI4-STREAM SMOKE TESTS PASSED <<<", UVM_NONE)
            phase.drop_objection(this);
        endtask
    endclass
endpackage
