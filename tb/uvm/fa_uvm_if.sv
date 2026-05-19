`timescale 1ns/1ps

interface fa_axil_if(input logic clk, input logic rst_n);
    logic [7:0]  awaddr;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [7:0]  araddr;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;
endinterface

interface fa_axi4_master_if(input logic clk, input logic rst_n);
    logic [3:0]   awid;
    logic [63:0]  awaddr;
    logic [7:0]   awlen;
    logic [2:0]   awsize;
    logic [1:0]   awburst;
    logic         awvalid;
    logic         awready;
    logic [127:0] wdata;
    logic [15:0]  wstrb;
    logic         wlast;
    logic         wvalid;
    logic         wready;
    logic [3:0]   bid;
    logic [1:0]   bresp;
    logic         bvalid;
    logic         bready;
    logic [3:0]   arid;
    logic [63:0]  araddr;
    logic [7:0]   arlen;
    logic [2:0]   arsize;
    logic [1:0]   arburst;
    logic         arvalid;
    logic         arready;
    logic [3:0]   rid;
    logic [127:0] rdata;
    logic [1:0]   rresp;
    logic         rlast;
    logic         rvalid;
    logic         rready;
endinterface

interface fa_mem_access_if(input logic clk);
    logic        mem_wr_en;
    logic [63:0] mem_wr_addr;
    logic [15:0] mem_wr_data16;
    logic        mem_rd_en;
    logic [63:0] mem_rd_addr;
    logic [15:0] mem_rd_data16;

    initial begin
        mem_wr_en     = 1'b0;
        mem_wr_addr   = '0;
        mem_wr_data16 = '0;
        mem_rd_en     = 1'b0;
        mem_rd_addr   = '0;
    end

    task automatic write16(input logic [63:0] addr, input logic [15:0] data);
        @(negedge clk);
        mem_wr_addr   <= addr;
        mem_wr_data16 <= data;
        mem_wr_en     <= 1'b1;
        @(negedge clk);
        mem_wr_en     <= 1'b0;
    endtask

    task automatic read16(input logic [63:0] addr, output logic [15:0] data);
        @(negedge clk);
        mem_rd_addr <= addr;
        mem_rd_en   <= 1'b1;
        @(posedge clk);
        data = mem_rd_data16;
        @(negedge clk);
        mem_rd_en <= 1'b0;
    endtask
endinterface
