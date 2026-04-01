// AXI4-Lite Transaction
class axi4_lite_txn extends uvm_sequence_item;
    `uvm_object_utils(axi4_lite_txn)

    rand bit [7:0]  addr;
    rand bit [31:0] data;
    rand bit        is_write;  // 1=write, 0=read
    bit [31:0]      rdata;     // read response data
    bit [1:0]       resp;

    constraint addr_align_c { addr[1:0] == 2'b00; }

    function new(string name = "axi4_lite_txn");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%02h data=0x%08h rdata=0x%08h resp=%0d",
                         is_write ? "WR" : "RD", addr, data, rdata, resp);
    endfunction
endclass
