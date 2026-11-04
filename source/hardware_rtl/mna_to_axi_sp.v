//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : mna_to_axi.v
// Author        : Li Xiayu
// Project       : NB1917
// Create Date   : 2020.01.07
// Description   : Master Mini-AXI to Slave AXI interface
//
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module mna_to_axi_sp #( parameter IDW=6, DW=64, AW=32)(
    input     [  AW-1 : 0]    s_mna_araddr      ,
    input                     s_mna_arvalid     ,
    output                    s_mna_arready     ,
    output    [  DW-1 : 0]    s_mna_rdata       ,
    output                    s_mna_rlast       ,
    output                    s_mna_rvalid      ,
    input                     s_mna_rready      ,
    input     [  AW-1 : 0]    s_mna_awaddr      ,
    input                     s_mna_awvalid     ,
    output                    s_mna_awready     ,
    input     [  DW-1 : 0]    s_mna_wdata       ,
    input     [   8-1 : 0]    s_mna_wen         ,
    input                     s_mna_wvalid      ,
    output                    s_mna_wready      ,

    output    [  AW-1 : 0]    m_axi_araddr      ,
    output    [     1 : 0]    m_axi_arburst     ,
    output    [     3 : 0]    m_axi_arcache     ,
    output    [ IDW-1 : 0]    m_axi_arid        ,
    output    [     3 : 0]    m_axi_arlen       ,
    output    [     1 : 0]    m_axi_arlock      ,
    output    [     2 : 0]    m_axi_arprot      ,
    output    [     3 : 0]    m_axi_arqos       ,
    input                     m_axi_arready     ,
    output    [     2 : 0]    m_axi_arsize      ,
    output                    m_axi_arvalid     ,
    output    [  AW-1 : 0]    m_axi_awaddr      ,
    output    [     1 : 0]    m_axi_awburst     ,
    output    [     3 : 0]    m_axi_awcache     ,
    output    [ IDW-1 : 0]    m_axi_awid        ,
    output    [     3 : 0]    m_axi_awlen       ,
    output    [     1 : 0]    m_axi_awlock      ,
    output    [     2 : 0]    m_axi_awprot      ,
    output    [     3 : 0]    m_axi_awqos       ,
    input                     m_axi_awready     ,
    output    [     2 : 0]    m_axi_awsize      ,
    output                    m_axi_awvalid     ,
    input     [ IDW-1 : 0]    m_axi_bid         ,
    output                    m_axi_bready      ,
    input     [     1 : 0]    m_axi_bresp       ,
    input                     m_axi_bvalid      ,
    input     [  DW-1 : 0]    m_axi_rdata       ,
    input     [ IDW-1 : 0]    m_axi_rid         ,
    input                     m_axi_rlast       ,
    output                    m_axi_rready      ,
    input     [     1 : 0]    m_axi_rresp       ,
    input                     m_axi_rvalid      ,
    output    [  DW-1 : 0]    m_axi_wdata       ,
    output    [ IDW-1 : 0]    m_axi_wid         ,
    output                    m_axi_wlast       ,
    input                     m_axi_wready      ,
    output    [DW/8-1 : 0]    m_axi_wstrb       ,
    output                    m_axi_wvalid      ,

    input                     m_axi_clk_rst     ,
    input                     m_axi_clk
);

    localparam BL      =  1;
    localparam BL_LOG2 =  0;

    // axsize  : byte size of 1 transfer, 64 bit-width -> 8 bytes (size code = 3)
    // axlen   : burst length-1
    // axburst : burst mode, 0->fixed, 1->incr, 2->wrap, 3->reserved
    //
    //reg [BL_LOG2-1:0] burst_cnt;
    reg  burst_cnt;

    assign m_axi_arlen   = BL-1 ;
    assign m_axi_awlen   = BL-1 ;

    //assign m_axi_wlast   = s_mna_wvalid && (burst_cnt==BL-1);
    assign m_axi_wlast   = s_mna_wvalid ;//&& (burst_cnt==BL-1);

    always@(posedge m_axi_clk)begin
        if(m_axi_clk_rst)
            burst_cnt <= 0;
        else if(m_axi_wvalid & m_axi_wready)
            burst_cnt <= burst_cnt + 1;
    end

    // ----------------------------------------------------
    assign m_axi_araddr  = s_mna_araddr   ;
    assign m_axi_arvalid = s_mna_arvalid  ;
    assign s_mna_arready = m_axi_arready  ;

    assign m_axi_arburst = 2'b01          ;
    assign m_axi_arcache = 4'b0011        ;
    assign m_axi_arid    = 0              ;
    assign m_axi_arlock  = 2'b00          ;
    assign m_axi_arprot  = 3'b000         ;
    assign m_axi_arqos   = 4'h0           ;
    assign m_axi_arsize  = 3'b011         ;
    assign m_axi_awburst = 2'b01          ;
    assign m_axi_awcache = 4'b0011        ;
    assign m_axi_awid    = 0              ;
    assign m_axi_awlock  = 2'b00          ;
    assign m_axi_awprot  = 3'b000         ;
    assign m_axi_awqos   = 4'h0           ;
    assign m_axi_awsize  = 3'b011         ;

    assign m_axi_bready  = 1'b1           ;

    assign s_mna_rdata   = m_axi_rdata    ;
    assign s_mna_rlast   = m_axi_rlast    ;
    assign s_mna_rvalid  = m_axi_rvalid   ;
    assign m_axi_rready  = s_mna_rready   ;

    assign m_axi_awaddr  = s_mna_awaddr   ;
    assign m_axi_awvalid = s_mna_awvalid  ;
    assign s_mna_awready = m_axi_awready  ;

    assign m_axi_wdata   = s_mna_wdata    ;
    assign s_mna_wready  = m_axi_wready   ;
    assign m_axi_wvalid  = s_mna_wvalid   ;

    assign m_axi_wid     = 0              ;
    assign m_axi_wstrb   = s_mna_wen;//{DW/8{1'b1}}   ;

endmodule
