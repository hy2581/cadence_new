`timescale 1ns/1ps
package fa_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int FA_SEQ_LEN  = 256;
    localparam int FA_HEAD_DIM = 64;

    localparam bit [63:0] FA_Q_BASE = 64'h0000_0000_0001_0000;
    localparam bit [63:0] FA_K_BASE = 64'h0000_0000_0002_0000;
    localparam bit [63:0] FA_V_BASE = 64'h0000_0000_0003_0000;
    localparam bit [63:0] FA_O_BASE = 64'h0000_0000_0004_0000;

    localparam longint unsigned FA_TENSOR_BYTES        = 32768;
    localparam longint unsigned FA_EXPECT_Q_READ_BYTES = 32768;
    localparam longint unsigned FA_EXPECT_K_READ_BYTES = 1114112;
    localparam longint unsigned FA_EXPECT_V_READ_BYTES = 1114112;
    localparam longint unsigned FA_EXPECT_O_WR_BYTES   = 32768;
    localparam longint unsigned FA_EXPECT_RD_BYTES     = 2260992;
    localparam longint unsigned FA_EXPECT_WR_BYTES     = 32768;

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

    localparam int FA_CTRL_START      = 0;
    localparam int FA_CTRL_SOFT_RESET = 1;
    localparam int FA_STATUS_BUSY     = 0;
    localparam int FA_STATUS_DONE     = 1;
    localparam int FA_STATUS_ERROR    = 2;
    localparam int FA_CFG_CAUSAL_EN   = 0;

    `uvm_analysis_imp_decl(_axil)
    `uvm_analysis_imp_decl(_dma)

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

        `uvm_object_utils_begin(fa_attention_job_item)
            `uvm_field_int(q_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(k_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(v_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(o_base,       UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(causal_en,    UVM_DEFAULT)
            `uvm_field_int(stride_bytes, UVM_DEFAULT)
            `uvm_field_int(neg_large,    UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(scale,        UVM_DEFAULT | UVM_HEX)
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

        real q_f[0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real k_f[0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real v_f[0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];
        real golden_o[0:FA_SEQ_LEN-1][0:FA_HEAD_DIM-1];

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
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fa_mem_access_if)::get(this, "", "mem_vif", mem_vif))
                `uvm_fatal("NOVIF", "fa_uvm_scoreboard requires mem_vif")
            reset_dma_stats();
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
            region = fa_dma_region(tr.is_write, tr.addr, tr.bytes);

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
            shortint signed q_raw;
            shortint signed k_raw;
            shortint signed v_raw;

            `uvm_info("DATA", "Loading deterministic Q/K/V vectors through memory access interface", UVM_LOW)
            for (int i = 0; i < FA_SEQ_LEN; i++) begin
                for (int j = 0; j < FA_HEAD_DIM; j++) begin
                    q_raw = shortint'((i * 13 + j * 7 + 3) % 64);
                    k_raw = shortint'((i * 5  + j * 11 + 9) % 64);
                    v_raw = shortint'((i * 17 + j * 3 + 1) % 64);
                    q_f[i][j] = $itor(q_raw) / 256.0;
                    k_f[i][j] = $itor(k_raw) / 256.0;
                    v_f[i][j] = $itor(v_raw) / 256.0;
                    mem_vif.write16(FA_Q_BASE + ((i * FA_HEAD_DIM + j) * 2), q_raw[15:0]);
                    mem_vif.write16(FA_K_BASE + ((i * FA_HEAD_DIM + j) * 2), k_raw[15:0]);
                    mem_vif.write16(FA_V_BASE + ((i * FA_HEAD_DIM + j) * 2), v_raw[15:0]);
                end
            end

            compute_golden(causal);
        endtask

        task compute_golden(bit causal);
            real s_val;
            real row_max;
            real row_sum;
            real p_val;
            real scale;

            `uvm_info("GOLDEN", "Computing FP32 scaled dot-product attention golden model", UVM_LOW)
            scale = 1.0 / $sqrt(64.0);
            for (int i = 0; i < FA_SEQ_LEN; i++) begin
                row_max = -1e30;
                for (int j = 0; j < FA_SEQ_LEN; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[i][k] * k_f[j][k];
                    s_val *= scale;
                    if (causal && j > i)
                        s_val = -1e9;
                    if (s_val > row_max)
                        row_max = s_val;
                end

                row_sum = 0.0;
                for (int j = 0; j < FA_SEQ_LEN; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[i][k] * k_f[j][k];
                    s_val *= scale;
                    if (causal && j > i)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max);
                    row_sum += p_val;
                end

                for (int k = 0; k < FA_HEAD_DIM; k++)
                    golden_o[i][k] = 0.0;

                for (int j = 0; j < FA_SEQ_LEN; j++) begin
                    s_val = 0.0;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        s_val += q_f[i][k] * k_f[j][k];
                    s_val *= scale;
                    if (causal && j > i)
                        s_val = -1e9;
                    p_val = $exp(s_val - row_max) / row_sum;
                    for (int k = 0; k < FA_HEAD_DIM; k++)
                        golden_o[i][k] += p_val * v_f[j][k];
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

            if (cycles_val >= 32'd300000)
                `uvm_fatal("PERF", $sformatf("CYCLES=%0d, expected < 300000", cycles_val))
            if (rd_bytes_val != FA_EXPECT_RD_BYTES[31:0])
                `uvm_fatal("BYTES", $sformatf("RD_BYTES=%0d, expected %0d", rd_bytes_val, FA_EXPECT_RD_BYTES))
            if (wr_bytes_val != FA_EXPECT_WR_BYTES[31:0])
                `uvm_fatal("BYTES", $sformatf("WR_BYTES=%0d, expected %0d", wr_bytes_val, FA_EXPECT_WR_BYTES))
        endtask

        task check_outputs_and_dma();
            logic [15:0] raw_o;
            shortint signed o_val;
            real dut_val;
            real gold_val;
            real abs_err;
            real row0_abs_err;
            int err_count;

            `uvm_info("CHECK", "Reading O memory and comparing against golden model", UVM_LOW)
            last_mean_err = 0.0;
            last_max_err = 0.0;
            last_row0_causal_err = 0.0;
            err_count = 0;

            for (int i = 0; i < FA_SEQ_LEN; i++) begin
                for (int j = 0; j < FA_HEAD_DIM; j++) begin
                    mem_vif.read16(FA_O_BASE + ((i * FA_HEAD_DIM + j) * 2), raw_o);
                    o_val = shortint'(raw_o);
                    dut_val = $itor(o_val) / 256.0;
                    gold_val = golden_o[i][j];
                    abs_err = dut_val - gold_val;
                    if (abs_err < 0.0)
                        abs_err = -abs_err;
                    last_mean_err += abs_err;
                    if (abs_err > last_max_err)
                        last_max_err = abs_err;

                    if (i == 0) begin
                        row0_abs_err = dut_val - v_f[0][j];
                        if (row0_abs_err < 0.0)
                            row0_abs_err = -row0_abs_err;
                        if (row0_abs_err > last_row0_causal_err)
                            last_row0_causal_err = row0_abs_err;
                    end
                    err_count++;
                end
            end

            last_mean_err = last_mean_err / $itor(err_count);

            if (last_mean_err > FA_MEAN_LIMIT)
                `uvm_fatal("GOLDEN", $sformatf("mean_abs_error=%0.6f, expected <= %0.6f", last_mean_err, FA_MEAN_LIMIT))
            if (last_max_err > FA_MAX_LIMIT)
                `uvm_fatal("GOLDEN", $sformatf("max_abs_error=%0.6f, expected <= %0.6f", last_max_err, FA_MAX_LIMIT))
            if (last_row0_causal_err > FA_CAUSAL_ROW0_LIMIT)
                `uvm_fatal("GOLDEN", $sformatf("row0_causal=%0.6f, expected <= %0.6f",
                    last_row0_causal_err, FA_CAUSAL_ROW0_LIMIT))

            check_dma_totals();
        endtask

        function void check_dma_totals();
            if (dma_q_read_bytes != FA_EXPECT_Q_READ_BYTES)
                `uvm_fatal("DMA", $sformatf("Q read bytes=%0d, expected %0d", dma_q_read_bytes, FA_EXPECT_Q_READ_BYTES))
            if (dma_k_read_bytes != FA_EXPECT_K_READ_BYTES)
                `uvm_fatal("DMA", $sformatf("K read bytes=%0d, expected %0d", dma_k_read_bytes, FA_EXPECT_K_READ_BYTES))
            if (dma_v_read_bytes != FA_EXPECT_V_READ_BYTES)
                `uvm_fatal("DMA", $sformatf("V read bytes=%0d, expected %0d", dma_v_read_bytes, FA_EXPECT_V_READ_BYTES))
            if (dma_o_write_bytes != FA_EXPECT_O_WR_BYTES)
                `uvm_fatal("DMA", $sformatf("O write bytes=%0d, expected %0d", dma_o_write_bytes, FA_EXPECT_O_WR_BYTES))
            if (dma_total_read_bytes != FA_EXPECT_RD_BYTES)
                `uvm_fatal("DMA", $sformatf("Total DMA read bytes=%0d, expected %0d", dma_total_read_bytes, FA_EXPECT_RD_BYTES))
            if (dma_total_write_bytes != FA_EXPECT_WR_BYTES)
                `uvm_fatal("DMA", $sformatf("Total DMA write bytes=%0d, expected %0d", dma_total_write_bytes, FA_EXPECT_WR_BYTES))
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
                illegal_bins over_300k = {[300000:$]};
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
                (mean_err <= FA_MEAN_LIMIT) ? 0 : 1,
                (max_err <= FA_MAX_LIMIT) ? 0 : 1,
                (causal_err <= FA_CAUSAL_ROW0_LIMIT) ? 0 : 1);
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

        fa_axil_agent    axil_agent;
        fa_axi_dma_agent dma_agent;
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

            axil_agent = fa_axil_agent::type_id::create("axil_agent", this);
            dma_agent  = fa_axi_dma_agent::type_id::create("dma_agent", this);
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
            env.scoreboard.load_vectors_and_compute_golden(job.causal_en);

            `uvm_info("JOBSEQ", "Programming attention job registers", UVM_LOW)
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
            axil_write(FA_REG_CFG, {31'd0, job.causal_en});

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
endpackage
