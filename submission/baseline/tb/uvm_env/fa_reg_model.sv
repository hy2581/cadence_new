// ============================================================
// FlashAttention — UVM Register Model (RAL)
// ============================================================

// --- Individual Register Definitions ---

class fa_reg_ctrl extends uvm_reg;
    `uvm_object_utils(fa_reg_ctrl)
    rand uvm_reg_field start_bit;
    rand uvm_reg_field soft_reset;
    rand uvm_reg_field irq_en;

    function new(string name = "fa_reg_ctrl");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        start_bit = uvm_reg_field::type_id::create("start_bit");
        start_bit.configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 0);
        soft_reset = uvm_reg_field::type_id::create("soft_reset");
        soft_reset.configure(this, 1, 1, "RW", 0, 1'h0, 1, 1, 0);
        irq_en = uvm_reg_field::type_id::create("irq_en");
        irq_en.configure(this, 1, 2, "RW", 0, 1'h0, 1, 1, 0);
    endfunction
endclass

class fa_reg_status extends uvm_reg;
    `uvm_object_utils(fa_reg_status)
    rand uvm_reg_field busy;
    rand uvm_reg_field done;
    rand uvm_reg_field error_bit;

    function new(string name = "fa_reg_status");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        busy = uvm_reg_field::type_id::create("busy");
        busy.configure(this, 1, 0, "RO", 0, 1'h0, 1, 0, 0);
        done = uvm_reg_field::type_id::create("done");
        done.configure(this, 1, 1, "W1C", 0, 1'h0, 1, 0, 0);
        error_bit = uvm_reg_field::type_id::create("error_bit");
        error_bit.configure(this, 1, 2, "RO", 0, 1'h0, 1, 0, 0);
    endfunction
endclass

class fa_reg_cfg extends uvm_reg;
    `uvm_object_utils(fa_reg_cfg)
    rand uvm_reg_field causal_en;

    function new(string name = "fa_reg_cfg");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        causal_en = uvm_reg_field::type_id::create("causal_en");
        causal_en.configure(this, 1, 0, "RW", 0, 1'h0, 1, 1, 0);
    endfunction
endclass

class fa_reg_data32 extends uvm_reg;
    `uvm_object_utils(fa_reg_data32)
    rand uvm_reg_field data;

    function new(string name = "fa_reg_data32");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        data = uvm_reg_field::type_id::create("data");
        data.configure(this, 32, 0, "RW", 0, 32'h0, 1, 1, 0);
    endfunction
endclass

class fa_reg_cycles extends uvm_reg;
    `uvm_object_utils(fa_reg_cycles)
    rand uvm_reg_field count;

    function new(string name = "fa_reg_cycles");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        count = uvm_reg_field::type_id::create("count");
        count.configure(this, 32, 0, "RO", 0, 32'h0, 1, 0, 0);
    endfunction
endclass

// --- Register Block ---
class fa_reg_block extends uvm_reg_block;
    `uvm_object_utils(fa_reg_block)

    rand fa_reg_ctrl    ctrl;
    rand fa_reg_status  status;
    rand fa_reg_cfg     cfg;
    rand fa_reg_data32  q_base_l, q_base_h;
    rand fa_reg_data32  k_base_l, k_base_h;
    rand fa_reg_data32  v_base_l, v_base_h;
    rand fa_reg_data32  o_base_l, o_base_h;
    rand fa_reg_data32  stride_bytes;
    rand fa_reg_data32  neg_large;
    rand fa_reg_data32  scale;
    rand fa_reg_cycles  cycles;

    uvm_reg_map default_map;

    function new(string name = "fa_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        ctrl = fa_reg_ctrl::type_id::create("ctrl");
        ctrl.configure(this, null, "");
        ctrl.build();

        status = fa_reg_status::type_id::create("status");
        status.configure(this, null, "");
        status.build();

        cfg = fa_reg_cfg::type_id::create("cfg");
        cfg.configure(this, null, "");
        cfg.build();

        q_base_l = fa_reg_data32::type_id::create("q_base_l");
        q_base_l.configure(this, null, "");
        q_base_l.build();

        q_base_h = fa_reg_data32::type_id::create("q_base_h");
        q_base_h.configure(this, null, "");
        q_base_h.build();

        k_base_l = fa_reg_data32::type_id::create("k_base_l");
        k_base_l.configure(this, null, "");
        k_base_l.build();

        k_base_h = fa_reg_data32::type_id::create("k_base_h");
        k_base_h.configure(this, null, "");
        k_base_h.build();

        v_base_l = fa_reg_data32::type_id::create("v_base_l");
        v_base_l.configure(this, null, "");
        v_base_l.build();

        v_base_h = fa_reg_data32::type_id::create("v_base_h");
        v_base_h.configure(this, null, "");
        v_base_h.build();

        o_base_l = fa_reg_data32::type_id::create("o_base_l");
        o_base_l.configure(this, null, "");
        o_base_l.build();

        o_base_h = fa_reg_data32::type_id::create("o_base_h");
        o_base_h.configure(this, null, "");
        o_base_h.build();

        stride_bytes = fa_reg_data32::type_id::create("stride_bytes");
        stride_bytes.configure(this, null, "");
        stride_bytes.build();

        neg_large = fa_reg_data32::type_id::create("neg_large");
        neg_large.configure(this, null, "");
        neg_large.build();

        scale = fa_reg_data32::type_id::create("scale");
        scale.configure(this, null, "");
        scale.build();

        cycles = fa_reg_cycles::type_id::create("cycles");
        cycles.configure(this, null, "");
        cycles.build();

        default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);
        default_map.add_reg(ctrl,         'h00, "RW");
        default_map.add_reg(status,       'h04, "RW");
        default_map.add_reg(cfg,          'h08, "RW");
        default_map.add_reg(q_base_l,     'h14, "RW");
        default_map.add_reg(q_base_h,     'h18, "RW");
        default_map.add_reg(k_base_l,     'h1C, "RW");
        default_map.add_reg(k_base_h,     'h20, "RW");
        default_map.add_reg(v_base_l,     'h24, "RW");
        default_map.add_reg(v_base_h,     'h28, "RW");
        default_map.add_reg(o_base_l,     'h2C, "RW");
        default_map.add_reg(o_base_h,     'h30, "RW");
        default_map.add_reg(stride_bytes, 'h34, "RW");
        default_map.add_reg(neg_large,    'h38, "RW");
        default_map.add_reg(scale,        'h3C, "RW");
        default_map.add_reg(cycles,       'h40, "RO");

        lock_model();
    endfunction
endclass

// --- RAL Adapter for AXI4-Lite ---
class fa_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(fa_reg_adapter)

    function new(string name = "fa_reg_adapter");
        super.new(name);
        supports_byte_enable = 0;
        provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        axi4_lite_txn txn = axi4_lite_txn::type_id::create("txn");
        txn.addr     = rw.addr[7:0];
        txn.is_write = (rw.kind == UVM_WRITE);
        txn.data     = rw.data[31:0];
        return txn;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item,
                                   ref uvm_reg_bus_op rw);
        axi4_lite_txn txn;
        if (!$cast(txn, bus_item)) begin
            `uvm_fatal("ADAPT", "Failed to cast bus_item to axi4_lite_txn")
            return;
        end
        rw.kind   = txn.is_write ? UVM_WRITE : UVM_READ;
        rw.addr   = {56'd0, txn.addr};
        rw.data   = txn.is_write ? txn.data : txn.rdata;
        rw.status = UVM_IS_OK;
    endfunction
endclass
