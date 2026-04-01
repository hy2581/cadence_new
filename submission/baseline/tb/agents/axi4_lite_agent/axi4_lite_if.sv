// AXI4-Lite Interface
interface axi4_lite_if (input logic clk, input logic rst_n);
    // Write Address
    logic [7:0]  s_axil_awaddr;
    logic        s_axil_awvalid;
    logic        s_axil_awready;

    // Write Data
    logic [31:0] s_axil_wdata;
    logic [3:0]  s_axil_wstrb;
    logic        s_axil_wvalid;
    logic        s_axil_wready;

    // Write Response
    logic [1:0]  s_axil_bresp;
    logic        s_axil_bvalid;
    logic        s_axil_bready;

    // Read Address
    logic [7:0]  s_axil_araddr;
    logic        s_axil_arvalid;
    logic        s_axil_arready;

    // Read Data
    logic [31:0] s_axil_rdata;
    logic [1:0]  s_axil_rresp;
    logic        s_axil_rvalid;
    logic        s_axil_rready;
endinterface
