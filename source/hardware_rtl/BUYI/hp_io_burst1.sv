//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : hp_io_burst1
// Author        : Xu Yun
// Project       : NB2240
// Create Date   : 2022.11.23
// Description   :
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module hp_io_burst1(
    // HP
    input              S_AXI_HP_ARREADY               ,
    input              S_AXI_HP_AWREADY               ,
    input              S_AXI_HP_BVALID                ,
    input              S_AXI_HP_RLAST                 ,
    input              S_AXI_HP_RVALID                ,
    input              S_AXI_HP_WREADY                ,
    input    [1 : 0  ] S_AXI_HP_BRESP                 ,
    input    [1 : 0  ] S_AXI_HP_RRESP                 ,
    input    [5 : 0  ] S_AXI_HP_BID                   ,
    input    [5 : 0  ] S_AXI_HP_RID                   ,
    input    [63: 0  ] S_AXI_HP_RDATA                 ,
    input    [7 : 0  ] S_AXI_HP_RCOUNT                ,
    input    [7 : 0  ] S_AXI_HP_WCOUNT                ,
    input    [2 : 0  ] S_AXI_HP_RACOUNT               ,
    input    [5 : 0  ] S_AXI_HP_WACOUNT               ,
    output             S_AXI_HP_ACLK                  ,
    output             S_AXI_HP_ARVALID               ,
    output             S_AXI_HP_AWVALID               ,
    output             S_AXI_HP_BREADY                ,
    output             S_AXI_HP_RDISSUECAP1_EN        ,
    output             S_AXI_HP_RREADY                ,
    output             S_AXI_HP_WLAST                 ,
    output             S_AXI_HP_WRISSUECAP1_EN        ,
    output             S_AXI_HP_WVALID                ,
    output   [1 : 0  ] S_AXI_HP_ARBURST               ,
    output   [1 : 0  ] S_AXI_HP_ARLOCK                ,
    output   [2 : 0  ] S_AXI_HP_ARSIZE                ,
    output   [1 : 0  ] S_AXI_HP_AWBURST               ,
    output   [1 : 0  ] S_AXI_HP_AWLOCK                ,
    output   [2 : 0  ] S_AXI_HP_AWSIZE                ,
    output   [2 : 0  ] S_AXI_HP_ARPROT                ,
    output   [2 : 0  ] S_AXI_HP_AWPROT                ,
    output   [31: 0  ] S_AXI_HP_ARADDR                ,
    output   [31: 0  ] S_AXI_HP_AWADDR                ,
    output   [3 : 0  ] S_AXI_HP_ARCACHE               ,
    output   [3 : 0  ] S_AXI_HP_ARLEN                 ,
    output   [3 : 0  ] S_AXI_HP_ARQOS                 ,
    output   [3 : 0  ] S_AXI_HP_AWCACHE               ,
    output   [3 : 0  ] S_AXI_HP_AWLEN                 ,
    output   [3 : 0  ] S_AXI_HP_AWQOS                 ,
    output   [5 : 0  ] S_AXI_HP_ARID                  ,
    output   [5 : 0  ] S_AXI_HP_AWID                  ,
    output   [5 : 0  ] S_AXI_HP_WID                   ,
    output   [63: 0  ] S_AXI_HP_WDATA                 ,
    output   [7 : 0  ] S_AXI_HP_WSTRB                 ,

    // hp
    mna_hp_std_itf.slave             hp               ,
  
    // clk & rst
    input                            hp_clk_rst       ,
    input                            hp_clk           
);
    //------------ HP IO ------------
    wire    [ 31 : 0]    hp_araddr        ;
    wire                 hp_arvalid       ;
    wire                 hp_arready       ;
    wire    [ 63 : 0]    hp_rdata         ;
    wire                 hp_rvalid        ;
    wire                 hp_rready        ;
    wire    [ 31 : 0]    hp_awaddr        ;
    wire                 hp_awvalid       ;
    wire                 hp_awready       ;
    wire    [ 63 : 0]    hp_wdata         ;
    wire                 hp_wvalid        ;
    wire                 hp_wready        ;
    wire    [ 63 : 0]    s_hp_wdata       ;      
    wire                 s_hp_wvalid      ;      
    wire                 s_hp_wready      ;      
    wire    [ 63 : 0]    m_hp_rdata       ;
    wire                 m_hp_rvalid      ;
    wire                 m_hp_rready      ;

   // ************************************************************************************
   //   PS-PL IO :  HP  
   // ************************************************************************************
    assign S_AXI_HP_ACLK = hp_clk;

    //hp
    assign hp_araddr  = hp.araddr   ;
    assign hp_arvalid = hp.arvalid  ;    
    assign hp_rready  = hp.rready   ;
    assign hp_awaddr  = hp.awaddr   ;
    assign hp_awvalid = hp.awvalid  ;    
    assign hp_wdata   = hp.wdata    ;
    assign hp_wvalid  = hp.wvalid   ;

    assign hp.arready = hp_arready  ;
    assign hp.rdata   = hp_rdata    ;
    assign hp.rvalid  = hp_rvalid   ;
    assign hp.awready = hp_awready  ;
    assign hp.wready  = hp_wready   ;

    avr_rs #(.DW(64)) avr_rs_u0(
      .m_data  ( hp_wdata      ),
      .m_valid ( hp_wvalid     ),
      .m_ready ( hp_wready     ),
 
      .s_data  ( s_hp_wdata    ),
      .s_valid ( s_hp_wvalid   ),
      .s_ready ( s_hp_wready   ),

      .clk     ( hp_clk        ),
      .rst_n   ( ~hp_clk_rst   )
    );

    avr_rs #(.DW(64)) avr_rs_u1(
      .m_data  ( m_hp_rdata  ),
      .m_valid ( m_hp_rvalid ),
      .m_ready ( m_hp_rready ),
 
      .s_data  ( hp_rdata    ),
      .s_valid ( hp_rvalid   ),
      .s_ready ( hp_rready   ),

      .clk     ( hp_clk      ),
      .rst_n   ( ~hp_clk_rst )
    );

    mna_to_axi_sp #(.IDW(6), .DW(64), .AW(32)) mna_to_axi_u0(
        .s_mna_araddr      (hp_araddr        ),
        .s_mna_arvalid     (hp_arvalid       ),
        .s_mna_arready     (hp_arready       ),
        .s_mna_rdata       (m_hp_rdata       ),
        .s_mna_rvalid      (m_hp_rvalid      ),
        .s_mna_rready      (m_hp_rready      ),
        .s_mna_awaddr      (hp_awaddr        ),
        .s_mna_awvalid     (hp_awvalid       ),
        .s_mna_awready     (hp_awready       ),
        .s_mna_wdata       (s_hp_wdata       ),
        .s_mna_wen         (8'hff            ),
        .s_mna_wvalid      (s_hp_wvalid      ),
        .s_mna_wready      (s_hp_wready      ),

        .m_axi_araddr      (S_AXI_HP_ARADDR  ),
        .m_axi_arburst     (S_AXI_HP_ARBURST ),
        .m_axi_arcache     (S_AXI_HP_ARCACHE ),
        .m_axi_arid        (S_AXI_HP_ARID    ),
        .m_axi_arlen       (S_AXI_HP_ARLEN   ),
        .m_axi_arlock      (S_AXI_HP_ARLOCK  ),
        .m_axi_arprot      (S_AXI_HP_ARPROT  ),
        .m_axi_arqos       (S_AXI_HP_ARQOS   ),
        .m_axi_arready     (S_AXI_HP_ARREADY ),
        .m_axi_arsize      (S_AXI_HP_ARSIZE  ),
        .m_axi_arvalid     (S_AXI_HP_ARVALID ),
        .m_axi_awaddr      (S_AXI_HP_AWADDR  ),
        .m_axi_awburst     (S_AXI_HP_AWBURST ),
        .m_axi_awcache     (S_AXI_HP_AWCACHE ),
        .m_axi_awid        (S_AXI_HP_AWID    ),
        .m_axi_awlen       (S_AXI_HP_AWLEN   ),
        .m_axi_awlock      (S_AXI_HP_AWLOCK  ),
        .m_axi_awprot      (S_AXI_HP_AWPROT  ),
        .m_axi_awqos       (S_AXI_HP_AWQOS   ),
        .m_axi_awready     (S_AXI_HP_AWREADY ),
        .m_axi_awsize      (S_AXI_HP_AWSIZE  ),
        .m_axi_awvalid     (S_AXI_HP_AWVALID ),
        .m_axi_bid         (S_AXI_HP_BID     ),
        .m_axi_bready      (S_AXI_HP_BREADY  ),
        .m_axi_bresp       (S_AXI_HP_BRESP   ),
        .m_axi_bvalid      (S_AXI_HP_BVALID  ),
        .m_axi_rdata       (S_AXI_HP_RDATA   ),
        .m_axi_rid         (S_AXI_HP_RID     ),
        .m_axi_rlast       (S_AXI_HP_RLAST   ),
        .m_axi_rready      (S_AXI_HP_RREADY  ),
        .m_axi_rresp       (S_AXI_HP_RRESP   ),
        .m_axi_rvalid      (S_AXI_HP_RVALID  ),
        .m_axi_wdata       (S_AXI_HP_WDATA   ),
        .m_axi_wid         (S_AXI_HP_WID     ),
        .m_axi_wlast       (S_AXI_HP_WLAST   ),
        .m_axi_wready      (S_AXI_HP_WREADY  ),
        .m_axi_wstrb       (S_AXI_HP_WSTRB   ),
        .m_axi_wvalid      (S_AXI_HP_WVALID  ),

        .m_axi_clk_rst     (hp_clk_rst       ),
        .m_axi_clk         (hp_clk           )
    );

endmodule    
