// AXI4 Memory Agent — Slave responder simulating external memory
// Uses associative array for large address space

// AXI4 burst transaction for monitoring
class axi4_burst_txn extends uvm_sequence_item;
    `uvm_object_utils(axi4_burst_txn)

    bit [63:0]  addr;
    bit [7:0]   len;
    bit [2:0]   size;
    bit [1:0]   burst;
    bit [3:0]   id;
    bit         is_write;
    int         byte_count;

    function new(string name = "axi4_burst_txn");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s id=%0d addr=0x%016h len=%0d size=%0d bytes=%0d",
                         is_write ? "WR" : "RD", id, addr, len, size, byte_count);
    endfunction
endclass

class axi4_mem_agent extends uvm_component;
    `uvm_component_utils(axi4_mem_agent)

    virtual axi4_mem_if vif;

    // Memory model: byte-addressable associative array
    bit [7:0] mem [bit [63:0]];

    // Analysis port for write monitoring
    uvm_analysis_port #(axi4_lite_txn) wr_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        wr_ap = new("wr_ap", this);
        if (!uvm_config_db#(virtual axi4_mem_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axi4_mem_if not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        vif.m_axi_arready <= 1'b0;
        vif.m_axi_rvalid  <= 1'b0;
        vif.m_axi_awready <= 1'b0;
        vif.m_axi_wready  <= 1'b0;
        vif.m_axi_bvalid  <= 1'b0;
        wait(vif.rst_n === 1'b1);
        @(posedge vif.clk);
        fork
            handle_reads();
            handle_writes();
        join
    endtask

    // --- Memory access helpers ---
    function void write_byte(bit [63:0] addr, bit [7:0] data);
        mem[addr] = data;
    endfunction

    function bit [7:0] read_byte(bit [63:0] addr);
        if (mem.exists(addr)) return mem[addr];
        else return 8'h00;
    endfunction

    function void write_half(bit [63:0] addr, bit [15:0] data);
        write_byte(addr,     data[7:0]);
        write_byte(addr + 1, data[15:8]);
    endfunction

    function bit [15:0] read_half(bit [63:0] addr);
        return {read_byte(addr + 1), read_byte(addr)};
    endfunction

    function void preload_matrix(input bit [63:0] base_addr, input int rows, input int cols,
                                  input shortint data[][]);
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
                write_half(base_addr + (r * cols + c) * 2, data[r][c]);
    endfunction

    function void readback_matrix(input bit [63:0] base_addr, input int rows, input int cols,
                                   ref shortint data[][]);
        data = new[rows];
        for (int r = 0; r < rows; r++) begin
            data[r] = new[cols];
            for (int c = 0; c < cols; c++)
                data[r][c] = shortint'(read_half(base_addr + (r * cols + c) * 2));
        end
    endfunction

    function void clear_region(bit [63:0] base_addr, int num_bytes);
        for (int i = 0; i < num_bytes; i++)
            if (mem.exists(base_addr + i)) mem.delete(base_addr + i);
    endfunction

    function int count_nonzero_region(bit [63:0] base_addr, int num_halfwords);
        int cnt = 0;
        for (int i = 0; i < num_halfwords; i++)
            if (read_half(base_addr + i * 2) != 0) cnt++;
        return cnt;
    endfunction

    // --- AXI4 Read Response ---
    task handle_reads();
        forever begin
            bit [63:0] addr;
            int        burst_len;
            int        beat_size;

            @(posedge vif.clk);
            while (!vif.m_axi_arvalid) @(posedge vif.clk);

            addr      = vif.m_axi_araddr;
            burst_len = vif.m_axi_arlen + 1;
            beat_size = 1 << vif.m_axi_arsize;

            vif.m_axi_arready <= 1'b1;
            @(posedge vif.clk);
            vif.m_axi_arready <= 1'b0;

            for (int i = 0; i < burst_len; i++) begin
                logic [127:0] rdata;
                for (int b = 0; b < beat_size; b++)
                    rdata[b*8 +: 8] = read_byte(addr + b);

                vif.m_axi_rdata  <= rdata;
                vif.m_axi_rid    <= vif.m_axi_arid;
                vif.m_axi_rresp  <= 2'b00;
                vif.m_axi_rlast  <= (i == burst_len - 1);
                vif.m_axi_rvalid <= 1'b1;

                @(posedge vif.clk);
                while (!vif.m_axi_rready) @(posedge vif.clk);

                addr += beat_size;
            end
            vif.m_axi_rvalid <= 1'b0;
            vif.m_axi_rlast  <= 1'b0;
        end
    endtask

    // --- AXI4 Write Response ---
    task handle_writes();
        forever begin
            bit [63:0] addr;
            int        burst_len;
            int        beat_size;

            @(posedge vif.clk);
            while (!vif.m_axi_awvalid) @(posedge vif.clk);

            addr      = vif.m_axi_awaddr;
            burst_len = vif.m_axi_awlen + 1;
            beat_size = 1 << vif.m_axi_awsize;

            vif.m_axi_awready <= 1'b1;
            @(posedge vif.clk);
            vif.m_axi_awready <= 1'b0;

            for (int i = 0; i < burst_len; i++) begin
                vif.m_axi_wready <= 1'b1;
                @(posedge vif.clk);
                while (!vif.m_axi_wvalid) @(posedge vif.clk);

                for (int b = 0; b < beat_size; b++)
                    if (vif.m_axi_wstrb[b])
                        write_byte(addr + b, vif.m_axi_wdata[b*8 +: 8]);

                addr += beat_size;
            end
            vif.m_axi_wready <= 1'b0;

            vif.m_axi_bid    <= 4'd0;
            vif.m_axi_bresp  <= 2'b00;
            vif.m_axi_bvalid <= 1'b1;
            @(posedge vif.clk);
            while (!vif.m_axi_bready) @(posedge vif.clk);
            vif.m_axi_bvalid <= 1'b0;
        end
    endtask
endclass
