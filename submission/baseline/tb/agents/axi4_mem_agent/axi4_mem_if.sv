// AXI4 Memory Interface (connects to DUT's AXI4 Master ports)
interface axi4_mem_if (input logic clk, input logic rst_n);
    // Write Address
    logic [3:0]   m_axi_awid;
    logic [63:0]  m_axi_awaddr;
    logic [7:0]   m_axi_awlen;
    logic [2:0]   m_axi_awsize;
    logic [1:0]   m_axi_awburst;
    logic         m_axi_awvalid;
    logic         m_axi_awready;
    // Write Data
    logic [127:0] m_axi_wdata;
    logic [15:0]  m_axi_wstrb;
    logic         m_axi_wlast;
    logic         m_axi_wvalid;
    logic         m_axi_wready;
    // Write Response
    logic [3:0]   m_axi_bid;
    logic [1:0]   m_axi_bresp;
    logic         m_axi_bvalid;
    logic         m_axi_bready;
    // Read Address
    logic [3:0]   m_axi_arid;
    logic [63:0]  m_axi_araddr;
    logic [7:0]   m_axi_arlen;
    logic [2:0]   m_axi_arsize;
    logic [1:0]   m_axi_arburst;
    logic         m_axi_arvalid;
    logic         m_axi_arready;
    // Read Data
    logic [3:0]   m_axi_rid;
    logic [127:0] m_axi_rdata;
    logic [1:0]   m_axi_rresp;
    logic         m_axi_rlast;
    logic         m_axi_rvalid;
    logic         m_axi_rready;
endinterface
