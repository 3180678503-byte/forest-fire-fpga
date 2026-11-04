//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : ai7030_top.v
// Author        : Wang Yinglin
// Project       : NB2430
// Create Date   : 2025.06.23
// Description   :
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
`include"ddr_width.v"
module ai7030_top #(parameter MIPI_AI_INPUT = 1)( 
  // PS
  inout     [53 : 0]     FIXED_IO_0_mio             ,
  inout     [14 : 0]     DDR_0_addr                 , 
  inout     [2  : 0]     DDR_0_ba                   , 
  inout                  DDR_0_cas_n                , 
  inout                  DDR_0_ck_n                 , 
  inout                  DDR_0_ck_p                 , 
  inout                  DDR_0_cke                  , 
  inout                  DDR_0_cs_n                 , 
  inout     [3  : 0]     DDR_0_dm                   , 
  inout     [31 : 0]     DDR_0_dq                   , 
  inout     [3  : 0]     DDR_0_dqs_n                , 
  inout     [3  : 0]     DDR_0_dqs_p                , 
  inout                  DDR_0_odt                  , 
  inout                  DDR_0_ras_n                , 
  inout                  DDR_0_reset_n              , 
  inout                  DDR_0_we_n                 , 
  inout                  FIXED_IO_0_ddr_vrn         , 
  inout                  FIXED_IO_0_ddr_vrp         , 
  inout                  FIXED_IO_0_ps_clk          ,
  inout                  FIXED_IO_0_ps_porb         ,
  inout                  FIXED_IO_0_ps_srstb        ,
  inout      [  0 : 0]   GPIO_0_tri_io              ,
  output                 npu_en                     ,
         
  // PL DDR       
  `ifdef  DDR16
  inout     [ 15 : 0]    ddr3_dq                    ,
  inout     [  1 : 0]    ddr3_dqs_n                 ,
  inout     [  1 : 0]    ddr3_dqs_p                 ,
  output    [  1 : 0]    ddr3_dm                    ,
  `elsif  DDR32
  inout     [ 31 : 0]    ddr3_dq                    ,
  inout     [  3 : 0]    ddr3_dqs_n                 ,
  inout     [  3 : 0]    ddr3_dqs_p                 ,
  output    [  3 : 0]    ddr3_dm                    , 
  `elsif  DDR64
  inout     [ 63 : 0]    ddr3_dq                    ,
  inout     [  7 : 0]    ddr3_dqs_n                 ,
  inout     [  7 : 0]    ddr3_dqs_p                 ,
  output    [  7 : 0]    ddr3_dm                    ,
  `endif
  output    [ 14 : 0]    ddr3_addr                  ,
  output    [  2 : 0]    ddr3_ba                    ,
  output                 ddr3_ras_n                 ,
  output                 ddr3_cas_n                 ,
  output                 ddr3_we_n                  ,
  output                 ddr3_reset_n               ,
  output    [  0 : 0]    ddr3_ck_p                  ,
  output    [  0 : 0]    ddr3_ck_n                  ,
  output    [  0 : 0]    ddr3_cke                   ,
  output    [  0 : 0]    ddr3_cs_n                  ,
  output    [  0 : 0]    ddr3_odt                   ,
  input      wire        uart_rtl_0_rxd              ,
  output     wire        uart_rtl_0_txd              ,
       
  input                  mode_button_f8             ,
  input                  sys_clk_p                  ,
  input                  sys_clk_n                  ,

// MIPI CSI-2 D-PHY
   input                 mipi_phy_if_0_clk_hs_n     ,
   input                 mipi_phy_if_0_clk_hs_p     ,
   input                 mipi_phy_if_0_clk_lp_n     ,
   input                 mipi_phy_if_0_clk_lp_p     ,
   input      [  1 : 0]  mipi_phy_if_0_data_hs_n    ,
   input      [  1 : 0]  mipi_phy_if_0_data_hs_p    ,
   input      [  1 : 0]  mipi_phy_if_0_data_lp_n    ,
   input      [  1 : 0]  mipi_phy_if_0_data_lp_p    ,
	 //inout                  si5368_i2c_scl_io          , 
   //inout                  si5368_i2c_sda_io          , 
   //output                 si5368_rst_n               ,

	 output                HDMI_CLK_P                 ,    
   output                HDMI_CLK_N                 , 
   output [2:0]          HDMI_TX_P                  , 
   output [2:0]          HDMI_TX_N                  ,      
 
   output    [  1 : 0]    led                       ,
   output     [  1 : 0]   led_test                  ,

   // PL Ethernet RGMII
   output                pl_phy_txc                 ,
   output                pl_phy_tx_ctl              ,
   output    [  3 : 0]   pl_phy_txd                 ,
   input                 pl_phy_rxc                 ,
   input                 pl_phy_rx_ctl              ,
   input     [  3 : 0]   pl_phy_rxd                 ,
   output                pl_phy_mdc                 ,
   inout                 pl_phy_mdio                ,
   output                pl_phy_reset_n             ,
   inout                 IIC_0_scl_io               ,
   inout                 IIC_0_sda_io               ,
   input                  PJTAG_TCK                 ,
   input                  PJTAG_TMS                 ,
   input                  PJTAG_TDI                 ,
   output                 PJTAG_TDO                 
);

  // ************************************************************************************
  //   BUYI AI
  // ************************************************************************************
    wire          [      26 : 0]   pl_awaddr        ;
    wire          [     511 : 0]   pl_awdata        ;
    wire          [      63 : 0]   pl_awen          ;
    wire          [       5 : 0]   pl_awinfo        ; // {awdbg_4, awsts_1, awstv_1}
    wire                           pl_awlast        ;
    wire                           pl_awvalid       ;
    wire                           pl_awready       ;
    wire          [      26 : 0]   pl_araddr        ;
    wire          [       5 : 0]   pl_arinfo        ; // {ardbg_4, arstc_1, arstv_1}
    wire                           pl_arlast        ;
    wire                           pl_arvalid       ;
    wire                           pl_arready       ;
    wire          [     511 : 0]   pl_rdata         ;
    wire                           pl_rvalid        ;
    wire                           pl_rlast         ;
    wire                           pl_rready        ;
    wire          [      15 : 0]   pl_ra_awaddr     ;  //{broadcast_1, col_id_4, row_id_4, offset_7}  
    wire          [      31 : 0]   pl_ra_awdata     ;
    wire                           pl_ra_awvalid    ;
    wire                           pl_ra_awready    ;
    wire          [      15 : 0]   pl_ra_araddr     ;  //{NA_1, col_id_4, row_id_4, offset_7}  
    wire                           pl_ra_arvalid    ;
    wire                           pl_ra_arready    ;
    wire          [      31 : 0]   pl_ra_rdata      ;
    wire                           pl_ra_rvalid     ;
    wire                           pl_ra_rready     ;
    wire          [      17 : 0]   pl_int_info      ;
    wire                           pl_int_valid     ;
    wire                           pl_int_ready     ;
    wire                           pl_ra_clk        ;
    wire                           pl_itf_clk       ;
    wire                           pl_rst_n         ;
    wire                           pl_clk_en_b      ;
    wire                           pl_bist_clk      ;
    wire                           pl_bist_rstn     ;
    wire                           pl_bist_en       ;
    wire                           pl_bist_err      ;
    wire                           pl_bist_done     ;
    wire                           pl_repair_done   ;  
    wire                           pl_repair_fail   ; 
    wire                           pl_clk_div_out   ;   // for clk check, you can set false path for this signal
    wire                           pl_scan_mode_b   ;
    wire                           pl_scan_en       ;
    wire                           pl_scan_clk      ;
    wire                           pl_scan_rst_n    ;
    wire                           pl_scan_pipe_clk ;
    wire          [    83 : 0  ]   pl_scan_i        ;    
    wire          [    63 : 0  ]   pl_scan_o        ;

	  wire                           si5368_i2c_scl_io; 
    wire                           si5368_i2c_sda_io; 
    wire                           si5368_rst_n     ;    

    wire          [    31 : 0  ]    gp0_ar_cnt      ;        
    wire          [    31 : 0  ]    gp0_r_cnt       ;        
    wire          [    31 : 0  ]    gp0_aw_cnt      ;           
    wire          [    31 : 0  ]    gp0_w_cnt       ;        
    wire          [    31 : 0  ]    gp0_b_cnt       ;        
   
    wire          [    31 : 0  ]    gp1_ar_cnt      ;        
    wire          [    31 : 0  ]    gp1_r_cnt       ;        
    wire          [    31 : 0  ]    gp1_aw_cnt      ;        
    wire          [    31 : 0  ]    gp1_w_cnt       ;          
    wire          [    31 : 0  ]    gp1_b_cnt       ; 

    wire          [     3 : 0  ]    hp_disable      ; 

  // ************************************************************************************
  //   PS-PL
  // ************************************************************************************
    wire              BYolo_GP0_ARVALID;
    wire              BYolo_GP0_AWVALID;
    wire              BYolo_GP0_BREADY ;
    wire              BYolo_GP0_RREADY ;
    wire              BYolo_GP0_WLAST  ;
    wire              BYolo_GP0_WVALID ;
    wire     [11 : 0] BYolo_GP0_ARID   ;
    wire     [11 : 0] BYolo_GP0_AWID   ;
    wire     [11 : 0] BYolo_GP0_WID    ;
    wire     [1 : 0]  BYolo_GP0_ARBURST;
    wire     [1 : 0]  BYolo_GP0_ARLOCK ;
    wire     [2 : 0]  BYolo_GP0_ARSIZE ;
    wire     [1 : 0]  BYolo_GP0_AWBURST;
    wire     [1 : 0]  BYolo_GP0_AWLOCK ;
    wire     [2 : 0]  BYolo_GP0_AWSIZE ;
    wire     [2 : 0]  BYolo_GP0_ARPROT ;
    wire     [2 : 0]  BYolo_GP0_AWPROT ;
    wire     [31 : 0] BYolo_GP0_ARADDR ;
    wire     [31 : 0] BYolo_GP0_AWADDR ;
    wire     [31 : 0] BYolo_GP0_WDATA  ;
    wire     [3 : 0]  BYolo_GP0_ARCACHE;
    wire     [3 : 0]  BYolo_GP0_ARLEN  ;
    wire     [3 : 0]  BYolo_GP0_ARQOS  ;
    wire     [3 : 0]  BYolo_GP0_AWCACHE;
    wire     [3 : 0]  BYolo_GP0_AWLEN  ;
    wire     [3 : 0]  BYolo_GP0_AWQOS  ;
    wire     [3 : 0]  BYolo_GP0_WSTRB  ;
    wire              BYolo_GP0_ARREADY;
    wire              BYolo_GP0_AWREADY;
    wire              BYolo_GP0_BVALID ;
    wire              BYolo_GP0_RLAST  ;
    wire              BYolo_GP0_RVALID ;
    wire              BYolo_GP0_WREADY ;
    wire     [11 : 0] BYolo_GP0_BID    ;
    wire     [11 : 0] BYolo_GP0_RID    ;
    wire     [1 : 0]  BYolo_GP0_BRESP  ;
    wire     [1 : 0]  BYolo_GP0_RRESP  ;
    wire     [31 : 0] BYolo_GP0_RDATA  ;
    
    wire              BYolo_GP1_ARVALID;
    wire              BYolo_GP1_AWVALID;
    wire              BYolo_GP1_BREADY ;
    wire              BYolo_GP1_RREADY ;
    wire              BYolo_GP1_WLAST  ;
    wire              BYolo_GP1_WVALID ;
    wire     [11 : 0] BYolo_GP1_ARID   ;
    wire     [11 : 0] BYolo_GP1_AWID   ;
    wire     [11 : 0] BYolo_GP1_WID    ;
    wire     [1 : 0]  BYolo_GP1_ARBURST;
    wire     [1 : 0]  BYolo_GP1_ARLOCK ;
    wire     [2 : 0]  BYolo_GP1_ARSIZE ;
    wire     [1 : 0]  BYolo_GP1_AWBURST;
    wire     [1 : 0]  BYolo_GP1_AWLOCK ;
    wire     [2 : 0]  BYolo_GP1_AWSIZE ;
    wire     [2 : 0]  BYolo_GP1_ARPROT ;
    wire     [2 : 0]  BYolo_GP1_AWPROT ;
    wire     [31 : 0] BYolo_GP1_ARADDR ;
    wire     [31 : 0] BYolo_GP1_AWADDR ;
    wire     [31 : 0] BYolo_GP1_WDATA  ;
    wire     [3 : 0]  BYolo_GP1_ARCACHE;
    wire     [3 : 0]  BYolo_GP1_ARLEN  ;
    wire     [3 : 0]  BYolo_GP1_ARQOS  ;
    wire     [3 : 0]  BYolo_GP1_AWCACHE;
    wire     [3 : 0]  BYolo_GP1_AWLEN  ;
    wire     [3 : 0]  BYolo_GP1_AWQOS  ;
    wire     [3 : 0]  BYolo_GP1_WSTRB  ;
    wire              BYolo_GP1_ARREADY;
    wire              BYolo_GP1_AWREADY;
    wire              BYolo_GP1_BVALID ;
    wire              BYolo_GP1_RLAST  ;
    wire              BYolo_GP1_RVALID ;
    wire              BYolo_GP1_WREADY ;
    wire     [11 : 0] BYolo_GP1_BID    ;
    wire     [11 : 0] BYolo_GP1_RID    ;
    wire     [1 : 0]  BYolo_GP1_BRESP  ;
    wire     [1 : 0]  BYolo_GP1_RRESP  ;
    wire     [31 : 0] BYolo_GP1_RDATA  ;

    wire              User_GP0_ARVALID;
    wire              User_GP0_AWVALID;
    wire              User_GP0_BREADY ;
    wire              User_GP0_RREADY ;
    wire              User_GP0_WLAST  ;
    wire              User_GP0_WVALID ;
    wire     [11 : 0] User_GP0_ARID   ;
    wire     [11 : 0] User_GP0_AWID   ;
    wire     [11 : 0] User_GP0_WID    ;
    wire     [1 : 0]  User_GP0_ARBURST;
    wire     [1 : 0]  User_GP0_ARLOCK ;
    wire     [2 : 0]  User_GP0_ARSIZE ;
    wire     [1 : 0]  User_GP0_AWBURST;
    wire     [1 : 0]  User_GP0_AWLOCK ;
    wire     [2 : 0]  User_GP0_AWSIZE ;
    wire     [2 : 0]  User_GP0_ARPROT ;
    wire     [2 : 0]  User_GP0_AWPROT ;
    wire     [31 : 0] User_GP0_ARADDR ;
    wire     [31 : 0] User_GP0_AWADDR ;
    wire     [31 : 0] User_GP0_WDATA  ;
    wire     [3 : 0]  User_GP0_ARCACHE;
    wire     [3 : 0]  User_GP0_ARLEN  ;
    wire     [3 : 0]  User_GP0_ARQOS  ;
    wire     [3 : 0]  User_GP0_AWCACHE;
    wire     [3 : 0]  User_GP0_AWLEN  ;
    wire     [3 : 0]  User_GP0_AWQOS  ;
    wire     [3 : 0]  User_GP0_WSTRB  ;
    wire              User_GP0_ACLK   ;
    wire              User_GP0_ARREADY;
    wire              User_GP0_AWREADY;
    wire              User_GP0_BVALID ;
    wire              User_GP0_RLAST  ;
    wire              User_GP0_RVALID ;
    wire              User_GP0_WREADY ;
    wire     [11 : 0] User_GP0_BID    ;
    wire     [11 : 0] User_GP0_RID    ;
    wire     [1 : 0]  User_GP0_BRESP  ;
    wire     [1 : 0]  User_GP0_RRESP  ;
    wire     [31 : 0] User_GP0_RDATA  ;
    
    wire              User_GP1_ARVALID;
    wire              User_GP1_AWVALID;
    wire              User_GP1_BREADY ;
    wire              User_GP1_RREADY ;
    wire              User_GP1_WLAST  ;
    wire              User_GP1_WVALID ;
    wire     [11 : 0] User_GP1_ARID   ;
    wire     [11 : 0] User_GP1_AWID   ;
    wire     [11 : 0] User_GP1_WID    ;
    wire     [1 : 0]  User_GP1_ARBURST;
    wire     [1 : 0]  User_GP1_ARLOCK ;
    wire     [2 : 0]  User_GP1_ARSIZE ;
    wire     [1 : 0]  User_GP1_AWBURST;
    wire     [1 : 0]  User_GP1_AWLOCK ;
    wire     [2 : 0]  User_GP1_AWSIZE ;
    wire     [2 : 0]  User_GP1_ARPROT ;
    wire     [2 : 0]  User_GP1_AWPROT ;
    wire     [31 : 0] User_GP1_ARADDR ;
    wire     [31 : 0] User_GP1_AWADDR ;
    wire     [31 : 0] User_GP1_WDATA  ;
    wire     [3 : 0]  User_GP1_ARCACHE;
    wire     [3 : 0]  User_GP1_ARLEN  ;
    wire     [3 : 0]  User_GP1_ARQOS  ;
    wire     [3 : 0]  User_GP1_AWCACHE;
    wire     [3 : 0]  User_GP1_AWLEN  ;
    wire     [3 : 0]  User_GP1_AWQOS  ;
    wire     [3 : 0]  User_GP1_WSTRB  ;
    wire              User_GP1_ACLK   ;
    wire              User_GP1_ARREADY;
    wire              User_GP1_AWREADY;
    wire              User_GP1_BVALID ;
    wire              User_GP1_RLAST  ;
    wire              User_GP1_RVALID ;
    wire              User_GP1_WREADY ;
    wire     [11 : 0] User_GP1_BID    ;
    wire     [11 : 0] User_GP1_RID    ;
    wire     [1 : 0]  User_GP1_BRESP  ;
    wire     [1 : 0]  User_GP1_RRESP  ;
    wire     [31 : 0] User_GP1_RDATA  ;

    wire              S_AXI_HP0_ARREADY       ;
    wire              S_AXI_HP0_AWREADY       ;
    wire              S_AXI_HP0_BVALID        ;
    wire              S_AXI_HP0_RLAST         ;
    wire              S_AXI_HP0_RVALID        ;
    wire              S_AXI_HP0_WREADY        ;
    wire     [1 : 0]  S_AXI_HP0_BRESP         ;
    wire     [1 : 0]  S_AXI_HP0_RRESP         ;
    wire     [4 : 0]  S_AXI_HP0_BID           ;
    wire     [4 : 0]  S_AXI_HP0_RID           ;
    wire     [63 : 0] S_AXI_HP0_RDATA         ;
    wire     [7 : 0]  S_AXI_HP0_RCOUNT        ;
    wire     [7 : 0]  S_AXI_HP0_WCOUNT        ;
    wire     [2 : 0]  S_AXI_HP0_RACOUNT       ;
    wire     [5 : 0]  S_AXI_HP0_WACOUNT       ;
    wire              S_AXI_HP0_ACLK          ;
    wire              S_AXI_HP0_ARVALID       ;
    wire              S_AXI_HP0_AWVALID       ;
    wire              S_AXI_HP0_BREADY        ;
    wire              S_AXI_HP0_RDISSUECAP1_EN;
    wire              S_AXI_HP0_RREADY        ;
    wire              S_AXI_HP0_WLAST         ;
    wire              S_AXI_HP0_WRISSUECAP1_EN;
    wire              S_AXI_HP0_WVALID        ;
    wire    [1 : 0]   S_AXI_HP0_ARBURST       ;
    wire    [1 : 0]   S_AXI_HP0_ARLOCK        ;
    wire    [2 : 0]   S_AXI_HP0_ARSIZE        ;
    wire    [1 : 0]   S_AXI_HP0_AWBURST       ;
    wire    [1 : 0]   S_AXI_HP0_AWLOCK        ;
    wire    [2 : 0]   S_AXI_HP0_AWSIZE        ;
    wire    [2 : 0]   S_AXI_HP0_ARPROT        ;
    wire    [2 : 0]   S_AXI_HP0_AWPROT        ;
    wire    [31 : 0]  S_AXI_HP0_ARADDR        ;
    wire    [31 : 0]  S_AXI_HP0_AWADDR        ;
    wire    [3 : 0]   S_AXI_HP0_ARCACHE       ;
    wire    [3 : 0]   S_AXI_HP0_ARLEN         ;
    wire    [3 : 0]   S_AXI_HP0_ARQOS         ;
    wire    [3 : 0]   S_AXI_HP0_AWCACHE       ;
    wire    [3 : 0]   S_AXI_HP0_AWLEN         ;
    wire    [3 : 0]   S_AXI_HP0_AWQOS         ;
    wire    [4 : 0]   S_AXI_HP0_ARID          ;
    wire    [4 : 0]   S_AXI_HP0_AWID          ;
    wire    [4 : 0]   S_AXI_HP0_WID           ;
    wire    [63 : 0]  S_AXI_HP0_WDATA         ;
    wire    [7 : 0]   S_AXI_HP0_WSTRB         ;

    wire              S_AXI_HP1_ARREADY       ;
    wire              S_AXI_HP1_AWREADY       ;
    wire              S_AXI_HP1_BVALID        ;
    wire              S_AXI_HP1_RLAST         ;
    wire              S_AXI_HP1_RVALID        ;
    wire              S_AXI_HP1_WREADY        ;
    wire     [1 : 0]  S_AXI_HP1_BRESP         ;
    wire     [1 : 0]  S_AXI_HP1_RRESP         ;
    wire     [4 : 0]  S_AXI_HP1_BID           ;
    wire     [4 : 0]  S_AXI_HP1_RID           ;
    wire     [63 : 0] S_AXI_HP1_RDATA         ;
    wire     [7 : 0]  S_AXI_HP1_RCOUNT        ;
    wire     [7 : 0]  S_AXI_HP1_WCOUNT        ;
    wire     [2 : 0]  S_AXI_HP1_RACOUNT       ;
    wire     [5 : 0]  S_AXI_HP1_WACOUNT       ;
    wire              S_AXI_HP1_ARVALID       ;
    wire              S_AXI_HP1_AWVALID       ;
    wire              S_AXI_HP1_BREADY        ;
    wire              S_AXI_HP1_RDISSUECAP1_EN;
    wire              S_AXI_HP1_RREADY        ;
    wire              S_AXI_HP1_WLAST         ;
    wire              S_AXI_HP1_WRISSUECAP1_EN;
    wire              S_AXI_HP1_WVALID        ;
    wire    [1 : 0]   S_AXI_HP1_ARBURST       ;
    wire    [1 : 0]   S_AXI_HP1_ARLOCK        ;
    wire    [2 : 0]   S_AXI_HP1_ARSIZE        ;
    wire    [1 : 0]   S_AXI_HP1_AWBURST       ;
    wire    [1 : 0]   S_AXI_HP1_AWLOCK        ;
    wire    [2 : 0]   S_AXI_HP1_AWSIZE        ;
    wire    [2 : 0]   S_AXI_HP1_ARPROT        ;
    wire    [2 : 0]   S_AXI_HP1_AWPROT        ;
    wire    [31 : 0]  S_AXI_HP1_ARADDR        ;
    wire    [31 : 0]  S_AXI_HP1_AWADDR        ;
    wire    [3 : 0]   S_AXI_HP1_ARCACHE       ;
    wire    [3 : 0]   S_AXI_HP1_ARLEN         ;
    wire    [3 : 0]   S_AXI_HP1_ARQOS         ;
    wire    [3 : 0]   S_AXI_HP1_AWCACHE       ;
    wire    [3 : 0]   S_AXI_HP1_AWLEN         ;
    wire    [3 : 0]   S_AXI_HP1_AWQOS         ;
    wire    [4 : 0]   S_AXI_HP1_ARID          ;
    wire    [4 : 0]   S_AXI_HP1_AWID          ;
    wire    [4 : 0]   S_AXI_HP1_WID           ;
    wire    [63 : 0]  S_AXI_HP1_WDATA         ;
    wire    [7 : 0]   S_AXI_HP1_WSTRB         ;

    wire              S_AXI_HP2_ARREADY       ;
    wire              S_AXI_HP2_AWREADY       ;
    wire              S_AXI_HP2_BVALID        ;
    wire              S_AXI_HP2_RLAST         ;
    wire              S_AXI_HP2_RVALID        ;
    wire              S_AXI_HP2_WREADY        ;
    wire     [1 : 0]  S_AXI_HP2_BRESP         ;
    wire     [1 : 0]  S_AXI_HP2_RRESP         ;
    wire     [4 : 0]  S_AXI_HP2_BID           ;
    wire     [4 : 0]  S_AXI_HP2_RID           ;
    wire     [63 : 0] S_AXI_HP2_RDATA         ;
    wire     [7 : 0]  S_AXI_HP2_RCOUNT        ;
    wire     [7 : 0]  S_AXI_HP2_WCOUNT        ;
    wire     [2 : 0]  S_AXI_HP2_RACOUNT       ;
    wire     [5 : 0]  S_AXI_HP2_WACOUNT       ;
    wire              S_AXI_HP2_ARVALID       ;
    wire              S_AXI_HP2_AWVALID       ;
    wire              S_AXI_HP2_BREADY        ;
    wire              S_AXI_HP2_RDISSUECAP1_EN;
    wire              S_AXI_HP2_RREADY        ;
    wire              S_AXI_HP2_WLAST         ;
    wire              S_AXI_HP2_WRISSUECAP1_EN;
    wire              S_AXI_HP2_WVALID        ;
    wire    [1 : 0]   S_AXI_HP2_ARBURST       ;
    wire    [1 : 0]   S_AXI_HP2_ARLOCK        ;
    wire    [2 : 0]   S_AXI_HP2_ARSIZE        ;
    wire    [1 : 0]   S_AXI_HP2_AWBURST       ;
    wire    [1 : 0]   S_AXI_HP2_AWLOCK        ;
    wire    [2 : 0]   S_AXI_HP2_AWSIZE        ;
    wire    [2 : 0]   S_AXI_HP2_ARPROT        ;
    wire    [2 : 0]   S_AXI_HP2_AWPROT        ;
    wire    [31 : 0]  S_AXI_HP2_ARADDR        ;
    wire    [31 : 0]  S_AXI_HP2_AWADDR        ;
    wire    [3 : 0]   S_AXI_HP2_ARCACHE       ;
    wire    [3 : 0]   S_AXI_HP2_ARLEN         ;
    wire    [3 : 0]   S_AXI_HP2_ARQOS         ;
    wire    [3 : 0]   S_AXI_HP2_AWCACHE       ;
    wire    [3 : 0]   S_AXI_HP2_AWLEN         ;
    wire    [3 : 0]   S_AXI_HP2_AWQOS         ;
    wire    [4 : 0]   S_AXI_HP2_ARID          ;
    wire    [4 : 0]   S_AXI_HP2_AWID          ;
    wire    [4 : 0]   S_AXI_HP2_WID           ;
    wire    [63 : 0]  S_AXI_HP2_WDATA         ;
    wire    [7 : 0]   S_AXI_HP2_WSTRB         ;

    wire              S_AXI_HP3_RDISSUECAP1_EN;
    wire              S_AXI_HP3_WRISSUECAP1_EN;
    wire     [2 : 0]  S_AXI_HP3_RACOUNT       ;
    wire     [5 : 0]  S_AXI_HP3_WACOUNT       ;
    wire     [7 : 0]  S_AXI_HP3_RCOUNT        ;
    wire     [7 : 0]  S_AXI_HP3_WCOUNT        ;

    wire              S_AXI_HP3_1_ARREADY       ;
    wire              S_AXI_HP3_1_AWREADY       ;
    wire              S_AXI_HP3_1_BVALID        ;
    wire              S_AXI_HP3_1_RLAST         ;
    wire              S_AXI_HP3_1_RVALID        ;
    wire              S_AXI_HP3_1_WREADY        ;
    wire     [1 : 0]  S_AXI_HP3_1_BRESP         ;
    wire     [1 : 0]  S_AXI_HP3_1_RRESP         ;
    wire     [4 : 0]  S_AXI_HP3_1_BID           ;
    wire     [4 : 0]  S_AXI_HP3_1_RID           ;
    wire     [63 : 0] S_AXI_HP3_1_RDATA         ;
    wire              S_AXI_HP3_1_ARVALID       ;
    wire              S_AXI_HP3_1_AWVALID       ;
    wire              S_AXI_HP3_1_BREADY        ;
    wire              S_AXI_HP3_1_RDISSUECAP1_EN;
    wire              S_AXI_HP3_1_RREADY        ;
    wire              S_AXI_HP3_1_WLAST         ;
    wire              S_AXI_HP3_1_WRISSUECAP1_EN;
    wire              S_AXI_HP3_1_WVALID        ;
    wire    [1 : 0]   S_AXI_HP3_1_ARBURST       ;
    wire    [1 : 0]   S_AXI_HP3_1_ARLOCK        ;
    wire    [2 : 0]   S_AXI_HP3_1_ARSIZE        ;
    wire    [1 : 0]   S_AXI_HP3_1_AWBURST       ;
    wire    [1 : 0]   S_AXI_HP3_1_AWLOCK        ;
    wire    [2 : 0]   S_AXI_HP3_1_AWSIZE        ;
    wire    [2 : 0]   S_AXI_HP3_1_ARPROT        ;
    wire    [2 : 0]   S_AXI_HP3_1_AWPROT        ;
    wire    [31 : 0]  S_AXI_HP3_1_ARADDR        ;
    wire    [31 : 0]  S_AXI_HP3_1_AWADDR        ;
    wire    [3 : 0]   S_AXI_HP3_1_ARCACHE       ;
    wire    [3 : 0]   S_AXI_HP3_1_ARLEN         ;
    wire    [3 : 0]   S_AXI_HP3_1_ARQOS         ;
    wire    [3 : 0]   S_AXI_HP3_1_AWCACHE       ;
    wire    [3 : 0]   S_AXI_HP3_1_AWLEN         ;
    wire    [3 : 0]   S_AXI_HP3_1_AWQOS         ;
    wire    [4 : 0]   S_AXI_HP3_1_ARID          ;
    wire    [4 : 0]   S_AXI_HP3_1_AWID          ;
    wire    [4 : 0]   S_AXI_HP3_1_WID           ;
    wire    [63 : 0]  S_AXI_HP3_1_WDATA         ;
    wire    [7 : 0]   S_AXI_HP3_1_WSTRB         ;
    
    // HP_HC
    wire             S0_AXI_HP_HC_ARREADY     ;
    wire             S0_AXI_HP_HC_AWREADY     ;
    wire             S0_AXI_HP_HC_BVALID      ;
    wire             S0_AXI_HP_HC_RLAST       ;
    wire             S0_AXI_HP_HC_RVALID      ;
    wire             S0_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S0_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S0_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S0_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S0_AXI_HP_HC_RDATA       ;
    wire             S0_AXI_HP_HC_ARVALID     ;
    wire             S0_AXI_HP_HC_AWVALID     ;
    wire             S0_AXI_HP_HC_BREADY      ;
    wire             S0_AXI_HP_HC_RREADY      ;
    wire             S0_AXI_HP_HC_WLAST       ;
    wire             S0_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S0_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S0_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S0_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S0_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S0_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S0_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S0_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S0_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S0_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S0_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S0_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S0_AXI_HP_HC_WSTRB       ;    

    wire             S1_AXI_HP_HC_ARREADY     ;
    wire             S1_AXI_HP_HC_AWREADY     ;
    wire             S1_AXI_HP_HC_BVALID      ;
    wire             S1_AXI_HP_HC_RLAST       ;
    wire             S1_AXI_HP_HC_RVALID      ;
    wire             S1_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S1_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S1_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S1_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S1_AXI_HP_HC_RDATA       ;
    wire             S1_AXI_HP_HC_ARVALID     ;
    wire             S1_AXI_HP_HC_AWVALID     ;
    wire             S1_AXI_HP_HC_BREADY      ;
    wire             S1_AXI_HP_HC_RREADY      ;
    wire             S1_AXI_HP_HC_WLAST       ;
    wire             S1_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S1_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S1_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S1_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S1_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S1_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S1_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S1_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S1_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S1_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S1_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S1_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S1_AXI_HP_HC_WSTRB       ; 

    wire             S2_AXI_HP_HC_ARREADY     ;
    wire             S2_AXI_HP_HC_AWREADY     ;
    wire             S2_AXI_HP_HC_BVALID      ;
    wire             S2_AXI_HP_HC_RLAST       ;
    wire             S2_AXI_HP_HC_RVALID      ;
    wire             S2_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S2_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S2_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S2_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S2_AXI_HP_HC_RDATA       ;
    wire             S2_AXI_HP_HC_ARVALID     ;
    wire             S2_AXI_HP_HC_AWVALID     ;
    wire             S2_AXI_HP_HC_BREADY      ;
    wire             S2_AXI_HP_HC_RREADY      ;
    wire             S2_AXI_HP_HC_WLAST       ;
    wire             S2_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S2_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S2_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S2_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S2_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S2_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S2_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S2_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S2_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S2_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S2_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S2_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S2_AXI_HP_HC_WSTRB       ; 

    wire             S3_AXI_HP_HC_ARREADY     ;
    wire             S3_AXI_HP_HC_AWREADY     ;
    wire             S3_AXI_HP_HC_BVALID      ;
    wire             S3_AXI_HP_HC_RLAST       ;
    wire             S3_AXI_HP_HC_RVALID      ;
    wire             S3_AXI_HP_HC_WREADY      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_BRESP       ;
    wire   [1 : 0  ] S3_AXI_HP_HC_RRESP       ;
    wire   [4 : 0  ] S3_AXI_HP_HC_BID         ;
    wire   [4 : 0  ] S3_AXI_HP_HC_RID         ;
    wire   [63: 0  ] S3_AXI_HP_HC_RDATA       ;
    wire             S3_AXI_HP_HC_ARVALID     ;
    wire             S3_AXI_HP_HC_AWVALID     ;
    wire             S3_AXI_HP_HC_BREADY      ;
    wire             S3_AXI_HP_HC_RREADY      ;
    wire             S3_AXI_HP_HC_WLAST       ;
    wire             S3_AXI_HP_HC_WVALID      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_ARBURST     ;
    wire   [1 : 0  ] S3_AXI_HP_HC_ARLOCK      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_ARSIZE      ;
    wire   [1 : 0  ] S3_AXI_HP_HC_AWBURST     ;
    wire   [1 : 0  ] S3_AXI_HP_HC_AWLOCK      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_AWSIZE      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_ARPROT      ;
    wire   [2 : 0  ] S3_AXI_HP_HC_AWPROT      ;
    wire   [31: 0  ] S3_AXI_HP_HC_ARADDR      ;
    wire   [31: 0  ] S3_AXI_HP_HC_AWADDR      ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARCACHE     ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARLEN       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_ARQOS       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWCACHE     ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWLEN       ;
    wire   [3 : 0  ] S3_AXI_HP_HC_AWQOS       ;
    wire   [4 : 0  ] S3_AXI_HP_HC_ARID        ;
    wire   [4 : 0  ] S3_AXI_HP_HC_AWID        ;
    wire   [4 : 0  ] S3_AXI_HP_HC_WID         ;
    wire   [63: 0  ] S3_AXI_HP_HC_WDATA       ;
    wire   [7 : 0  ] S3_AXI_HP_HC_WSTRB       ;    

    wire              FCLK_CLK0               ;
    wire              FCLK_RESET0_N           ;

    wire  [28 : 0 ]   app_addr                ;
    wire  [2 : 0  ]   app_cmd                 ;
    wire              app_en                  ;
    wire  [28 : 0 ]   aimate_app_addr         ;
    wire  [2 : 0  ]   aimate_app_cmd          ;
    wire              aimate_app_en           ;
    wire  [28 : 0 ]   direct_app_addr         ;
    wire  [2 : 0  ]   direct_app_cmd          ;
    wire              direct_app_en           ;
    wire  [28 : 0 ]   direct_wr_app_addr      ;
    wire  [2 : 0  ]   direct_wr_app_cmd       ;
    wire              direct_wr_app_en        ;
    wire  [28 : 0 ]   direct_rd_app_addr      ;
    wire  [2 : 0  ]   direct_rd_app_cmd       ;
    wire              direct_rd_app_en        ;
    `ifdef  DDR16
      wire  [16*8-1 : 0]   app_wdf_data       ;
      wire  [16-1   : 0]   app_wdf_mask       ;
      wire  [16*8-1 : 0]   app_rd_data        ; 
      wire  [16*8-1 : 0]   aimate_app_wdf_data;
      wire  [16-1   : 0]   aimate_app_wdf_mask;
      wire  [16*8-1 : 0]   direct_app_wdf_data;
      wire  [16-1   : 0]   direct_app_wdf_mask;
      wire  [16*8-1 : 0]   direct_wr_app_wdf_data;
      wire  [16-1   : 0]   direct_wr_app_wdf_mask;
      wire  [16*8-1 : 0]   direct_rd_app_wdf_data;
      wire  [16-1   : 0]   direct_rd_app_wdf_mask;
      localparam integer DIRECT_APP_DATA_WIDTH = 16*8;
      localparam integer DIRECT_APP_DATA_BYTES = 16;
    `elsif  DDR32
      wire  [32*8-1 : 0]   app_wdf_data       ;
      wire  [32-1   : 0]   app_wdf_mask       ;
      wire  [32*8-1 : 0]   app_rd_data        ;       
      wire  [32*8-1 : 0]   aimate_app_wdf_data;
      wire  [32-1   : 0]   aimate_app_wdf_mask;
      wire  [32*8-1 : 0]   direct_app_wdf_data;
      wire  [32-1   : 0]   direct_app_wdf_mask;
      wire  [32*8-1 : 0]   direct_wr_app_wdf_data;
      wire  [32-1   : 0]   direct_wr_app_wdf_mask;
      wire  [32*8-1 : 0]   direct_rd_app_wdf_data;
      wire  [32-1   : 0]   direct_rd_app_wdf_mask;
      localparam integer DIRECT_APP_DATA_WIDTH = 32*8;
      localparam integer DIRECT_APP_DATA_BYTES = 32;
    `elsif  DDR64
      wire  [64*8-1 : 0]   app_wdf_data       ;
      wire  [64-1   : 0]   app_wdf_mask       ;
      wire  [64*8-1 : 0]   app_rd_data        ;
      wire  [64*8-1 : 0]   aimate_app_wdf_data;
      wire  [64-1   : 0]   aimate_app_wdf_mask;
      wire  [64*8-1 : 0]   direct_app_wdf_data;
      wire  [64-1   : 0]   direct_app_wdf_mask;
      wire  [64*8-1 : 0]   direct_wr_app_wdf_data;
      wire  [64-1   : 0]   direct_wr_app_wdf_mask;
      wire  [64*8-1 : 0]   direct_rd_app_wdf_data;
      wire  [64-1   : 0]   direct_rd_app_wdf_mask;
      localparam integer DIRECT_APP_DATA_WIDTH = 64*8;
      localparam integer DIRECT_APP_DATA_BYTES = 64;
    `endif
    wire              app_wdf_end             ;
    wire              app_wdf_wren            ;
    wire              aimate_app_wdf_end      ;
    wire              aimate_app_wdf_wren     ;
    wire              direct_app_wdf_end      ;
    wire              direct_app_wdf_wren     ;
    wire              direct_wr_app_wdf_end   ;
    wire              direct_wr_app_wdf_wren  ;
    wire              direct_rd_app_wdf_end   ;
    wire              direct_rd_app_wdf_wren  ;
    wire              app_rd_data_end         ; 
    wire              app_rd_data_valid       ; 
    wire              app_rdy                 ; 
    wire              app_wdf_rdy             ; 

  // ************************************************************************************
  //   reset and clocks
  // ************************************************************************************
  wire              soft_rst            ;
  wire              sys_rst_n           ;
  wire              core_rst            ;
  wire              clk_200mhz          ;

  wire              ddr_clk_rst         ;
  wire              gp_clk_rst          ;
  wire              hp_clk_rst          ;

  wire              ps_clk_out          ;  
  wire              ddr_clk             ;

  wire              gp_clk              ;
  wire              hp_clk              ;

  wire              ddr_ui_rst          ; // not use
  wire              ddr3_init_done      ;
  wire              ddr_clk_led         ;
  wire              ps_clk_led          ;

  // ************************************************************************************
  //   cam & display
  // ************************************************************************************
  wire              led1                ;
  wire              led2                ;
  wire              led3                ;
  wire              cam_hs              ;
  wire              cam_vs              ;
  wire  [23:0]      cam_rgb             ;
  wire              cam_clk             ;
  wire              cam_data_en         ; 

  wire              cmos_vsync_out      ;
  wire              cmos_href_out       ;
  wire  [23:0]      cmos_db_out         ; 
  wire  [1 :0]      write_addr_index    ;
  wire  [1 :0]      read_addr_index     ;    
  wire              continuous_en       ;
  wire              img_start           ;
  wire  [23:0]      img_data            ;
  wire              img_valid           ;
  wire              img_ready           ;  
  wire              img_start0          ;
  wire  [23:0]      img_data0           ;
  wire              img_valid0          ;
  wire              img_ready0          ;  
  wire              img_start1          ;
  wire  [23:0]      img_data1           ;
  wire              img_valid1          ;
  wire              img_ready1          ;
  wire  [1 :0]      video_mode          ;
  wire              video_mode_pulse    ;
  wire              aimate_img_ready    ;
  wire              direct_ddr_active    ;
  wire              direct_video_rst     ;
  wire              direct_video_rst_req ;
  reg   [7 :0]      direct_video_rst_cnt ;
  wire  [31:0]      direct_ddr_base0_byte_addr;
  wire  [31:0]      direct_ddr_base1_byte_addr;
  wire  [31:0]      direct_wr_base_byte_addr;
  wire  [31:0]      direct_rd_base_byte_addr;
  wire  [23:0]      direct_video_tdata   ;
  wire              direct_video_tvalid  ;
  wire              direct_video_tready  ;
  wire              direct_video_tuser   ;
  wire              direct_video_tlast   ;
  wire              direct_video_fifo_overflow;
  wire              direct_mipi_tready   ;
  wire  [23:0]      mipi_axis_tdata      ;
  wire              mipi_axis_tvalid     ;
  wire              mipi_axis_tready     ;
  wire              mipi_axis_tuser      ;
  wire              mipi_axis_tlast      ;
  (* mark_debug = "true", keep = "true" *) wire [23:0] dbg_mipi_axis_tdata;
  (* mark_debug = "true", keep = "true" *) wire dbg_mipi_axis_tvalid;
  (* mark_debug = "true", keep = "true" *) wire dbg_mipi_axis_tuser;
  (* mark_debug = "true", keep = "true" *) wire dbg_mipi_axis_tlast;
  (* mark_debug = "true", keep = "true" *) wire dbg_mipi_axis_tready;
  (* mark_debug = "true", keep = "true" *) wire dbg_mipi_axis_beat;
  (* mark_debug = "true", keep = "true" *) wire [1:0] dbg_video_mode;
  wire              mipi_csi_irq         ;
  wire              mipi_demosaic_irq    ;
  wire              mipi_gamma_irq       ;
  wire              mipi_dlyctrl_rdy     ;
  wire              mipi_csi_system_rst  ;
  wire              direct_writer_frame_start_pulse;
  wire              direct_writer_frame_active;
  wire              direct_writer_frame_done_pulse;
  wire              direct_wr_app_pending;
  wire              direct_rd_app_pending;
  wire              direct_reader_start;
  wire              direct_reader_frame_active;
  wire              direct_reader_frame_done_pulse;
  wire              direct_pp_writer_buf_index;
  wire              direct_pp_reader_buf_index;
  wire              direct_pp_latest_buf_index;
  wire              direct_pp_latest_frame_valid;
  wire              direct_pp_reader_frame_valid;
  wire  [23:0]      eth_ddr_axis_tdata  ;
  wire              eth_ddr_axis_tvalid ;
  wire              eth_ddr_axis_tready ;
  wire              eth_ddr_axis_tlast  ;
  wire              eth_ddr_axis_tuser  ;
  wire  [23:0]      eth_spare_axis_tdata;
  wire              eth_spare_axis_tvalid;
  wire              eth_spare_axis_tready;
  wire              eth_spare_axis_tlast;
  wire              eth_spare_axis_tuser;
  wire  [1 :0]      eth_video_select    ;
  wire              reset_cam_clk       ;
  wire              network_running     ;  

  wire  [15 : 0]    ps_x0_pos           ;
  wire  [15 : 0]    ps_y0_pos           ;
  wire  [15 : 0]    ps_x1_pos           ;
  wire  [15 : 0]    ps_y1_pos           ;
  wire  [15 : 0]    ps_x_leng           ;
  wire  [15 : 0]    ps_y_leng           ;
  wire  [ 3 : 0]    ps_hstride          ;
  wire  [ 3 : 0]    ps_vstride          ;
  wire  [10 : 0]    resize_pix_len      ;
  wire  [31 : 0]    write_ps_size       ;
  wire              display_en          ;

  wire  [31 : 0]    camera_wr_addr      ;
  wire  [31 : 0]    camera_rd_addr      ;
  wire              wr_done_pulse       ;
     
  wire              hdmi_i2c_scl_io     ; 
  wire              hdmi_i2c_sda_io     ; 
  wire              hdmi_out_clk        ; 
  wire   [23:0]     hdmi_out_data       ; 
  wire              hdmi_out_de         ; 
  wire              hdmi_out_hs         ; 
  wire              hdmi_out_vs         ; 
  wire   [0:0]      hdmi_rstn_tri_o     ;

  wire              wr_wfifo_err        ;
  wire              rd_rfifo_err        ;

  wire              test_irq            ;
  wire              customop_irq        ;
  wire              ai_irq              ; 
  wire              pl_bist_err_inv     ; 
  wire              dip_switches        ;
  wire              pl_bvalid           ;
  wire              pl_bready           ;
  wire              pll_lock            ; 
  wire    [23:0]    vtc_data            ;
  wire              vtc_vs              ;
  wire              vtc_hs              ;
  wire              vtc_de              ;

  wire    [31 : 0]  H_SYNC              ;
  wire    [31 : 0]  H_BACK_PORCH        ;
  wire    [31 : 0]  H_ACTIVE            ;
  wire    [31 : 0]  H_FRONT_PORCH       ;
  wire    [31 : 0]  V_SYNC              ;
  wire    [31 : 0]  V_BACK_PORCH        ;
  wire    [31 : 0]  V_ACTIVE            ;
  wire    [31 : 0]  V_FRONT_PORCH       ;

  localparam integer DIRECT_FRAME_WIDTH        = 1280;
  localparam integer DIRECT_FRAME_HEIGHT       = 720;
  localparam integer DIRECT_PIXELS_PER_PACKET  = 320;
  localparam [31:0] DIRECT_COLORBAR_DDR_BASE0 = 32'h0600_0000;
  localparam [31:0] DIRECT_COLORBAR_DDR_BASE1 = 32'h0700_0000;
  localparam [31:0] DIRECT_MIPI_DDR_BASE0     = 32'h0680_0000;
  localparam [31:0] DIRECT_MIPI_DDR_BASE1     = 32'h0780_0000;
  localparam integer MIPI_CTRL_AXI_ADDR_WIDTH  = 18;

  mna_gp_ww_itf  gp0();
  mna_gp_ww_itf  gp1();

  mna_hp_std_itf hp0();
  mna_hp_std_itf hp1();
  mna_hp_std_itf hp2();
  mna_hp_std_itf hp3(); 
  mna_hp_std_itf imgmake_hp_itf();
  mna_hp_std_itf s1_hp_itf();
  mna_hp_std_itf s2_hp_itf();
  mna_hp_std_itf s3_hp_itf();

  mna_gp_ww_itf  host_ctrl()  ;
  mna_gp_ww_itf  ai_ra()      ;
  mna_gp_ww_itf  cam()        ;
  mna_gp_ww_itf  m3_gpx()     ;

  mna_gp_ww_itf  cdma_ctrl()  ;
  mna_gp_ww_itf  cam_gp1_s01();
  mna_gp_ww_itf  cam_gp1_s02();
  mna_gp_ww_itf  cam_gp1_s03();

  // MIPI PS control aperture on User_GP0 m3_gpx:
  //   0x400C_0000 - 0x400C_3FFF : wrapper status
  //   0x400C_4000 - 0x400C_7FFF : CSI2 RX
  //   0x400C_8000 - 0x400C_BFFF : demosaic HLS
  //   0x400C_C000 - 0x400C_FFFF : gamma HLS
  wire                           mipi_ctrl_aclk;
  wire                           mipi_ctrl_aresetn;
  wire [MIPI_CTRL_AXI_ADDR_WIDTH-1:0] mipi_ctrl_awaddr;
  wire [2:0]                     mipi_ctrl_awprot;
  wire                           mipi_ctrl_awvalid;
  wire                           mipi_ctrl_awready;
  wire [31:0]                    mipi_ctrl_wdata;
  wire [3:0]                     mipi_ctrl_wstrb;
  wire                           mipi_ctrl_wvalid;
  wire                           mipi_ctrl_wready;
  wire [1:0]                     mipi_ctrl_bresp;
  wire                           mipi_ctrl_bvalid;
  wire                           mipi_ctrl_bready;
  wire [MIPI_CTRL_AXI_ADDR_WIDTH-1:0] mipi_ctrl_araddr;
  wire [2:0]                     mipi_ctrl_arprot;
  wire                           mipi_ctrl_arvalid;
  wire                           mipi_ctrl_arready;
  wire [31:0]                    mipi_ctrl_rdata;
  wire [1:0]                     mipi_ctrl_rresp;
  wire                           mipi_ctrl_rvalid;
  wire                           mipi_ctrl_rready;


  // Independent AN5641 input branch; legacy downstream paths are retained.
  wire [1:0] legacy_video_mode;
  wire legacy_video_mode_pulse, an5641_ready, an5641_de, an5641_vs;
  wire [23:0] an5641_rgb;
  wire [31:0] an5641_frames_in, an5641_frames_out, an5641_lines;
  wire [31:0] an5641_errors, an5641_stalls;
  wire [31:0] an5641_frames_in_gp, an5641_frames_out_gp, an5641_lines_gp;
  wire [31:0] an5641_errors_gp, an5641_stalls_gp;
  assign video_mode = MIPI_AI_INPUT ? 2'd2 : legacy_video_mode;
  assign video_mode_pulse = MIPI_AI_INPUT ? 1'b0 : legacy_video_mode_pulse;
  wire an5641_pixel_clk, an5641_pixel_reset, an5641_clock_locked;
  an5641_camera_clock u_an5641_pixel_clock (
    .ref_clk_200m(ddr_clk), .reset(direct_video_rst),
    .pixel_clk(an5641_pixel_clk), .pixel_reset(an5641_pixel_reset),
    .locked(an5641_clock_locked)
  );
  axis_rgb_to_camera #(.FRAME_WIDTH(1920), .FRAME_HEIGHT(1080)) u_an5641_camera (
    .clk(cam_clk), .rst(an5641_pixel_reset),
    .s_tdata(mipi_axis_tdata), .s_tvalid(mipi_axis_tvalid && MIPI_AI_INPUT),
    .s_tready(an5641_ready), .s_tuser(mipi_axis_tuser), .s_tlast(mipi_axis_tlast),
    .cam_rgb(an5641_rgb), .cam_de(an5641_de), .cam_vs(an5641_vs),
    .frames_in(an5641_frames_in), .frames_out(an5641_frames_out),
    .lines_in(an5641_lines), .format_errors(an5641_errors), .stall_cycles(an5641_stalls)
  );
  counter_gray_cdc u_an5641_frames_in_cdc (
    .src_clk(cam_clk), .src_rst(an5641_pixel_reset), .value(an5641_frames_in),
    .dst_clk(mipi_ctrl_aclk), .dst_rst(~mipi_ctrl_aresetn), .sampled(an5641_frames_in_gp)
  );
  counter_gray_cdc u_an5641_frames_out_cdc (
    .src_clk(cam_clk), .src_rst(an5641_pixel_reset), .value(an5641_frames_out),
    .dst_clk(mipi_ctrl_aclk), .dst_rst(~mipi_ctrl_aresetn), .sampled(an5641_frames_out_gp)
  );
  counter_gray_cdc u_an5641_lines_cdc (
    .src_clk(cam_clk), .src_rst(an5641_pixel_reset), .value(an5641_lines),
    .dst_clk(mipi_ctrl_aclk), .dst_rst(~mipi_ctrl_aresetn), .sampled(an5641_lines_gp)
  );
  counter_gray_cdc u_an5641_errors_cdc (
    .src_clk(cam_clk), .src_rst(an5641_pixel_reset), .value(an5641_errors),
    .dst_clk(mipi_ctrl_aclk), .dst_rst(~mipi_ctrl_aresetn), .sampled(an5641_errors_gp)
  );
  counter_gray_cdc u_an5641_stalls_cdc (
    .src_clk(cam_clk), .src_rst(an5641_pixel_reset), .value(an5641_stalls),
    .dst_clk(mipi_ctrl_aclk), .dst_rst(~mipi_ctrl_aresetn), .sampled(an5641_stalls_gp)
  );

  assign core_rst     = ~FCLK_RESET0_N             ;
  assign sys_rst_n    = ~core_rst                  ;
  assign led[0]     = ddr3_init_done & ddr_clk_led ;
  assign led[1]     = mipi_dlyctrl_rdy             ;

  assign dip_switches = 1'b1;
  assign eth_video_select = direct_ddr_active ? 2'd1 : 2'd3;
  assign direct_ddr_active = video_mode != 2'd2;
  assign direct_video_rst_req = ddr_clk_rst | video_mode_pulse | (~ddr3_init_done);
  assign direct_video_rst = direct_video_rst_req | (direct_video_rst_cnt != 8'd0);
  assign direct_ddr_base0_byte_addr = (video_mode == 2'd1) ? DIRECT_MIPI_DDR_BASE0 :
                                                            DIRECT_COLORBAR_DDR_BASE0;
  assign direct_ddr_base1_byte_addr = (video_mode == 2'd1) ? DIRECT_MIPI_DDR_BASE1 :
                                                            DIRECT_COLORBAR_DDR_BASE1;
  assign direct_writer_frame_start_pulse = direct_video_tvalid & direct_video_tready & direct_video_tuser;
  assign img_ready1 = (video_mode == 2'd2) ? aimate_img_ready :
                                             1'b1;
  assign mipi_axis_tready = MIPI_AI_INPUT ? an5641_ready :
                            ((video_mode == 2'd1) ? direct_mipi_tready : 1'b1);
  assign dbg_mipi_axis_tdata  = mipi_axis_tdata;
  assign dbg_mipi_axis_tvalid = mipi_axis_tvalid;
  assign dbg_mipi_axis_tuser  = mipi_axis_tuser;
  assign dbg_mipi_axis_tlast  = mipi_axis_tlast;
  assign dbg_mipi_axis_tready = mipi_axis_tready;
  assign dbg_mipi_axis_beat   = mipi_axis_tvalid & mipi_axis_tready;
  assign dbg_video_mode        = video_mode;

  // Direct ILA for MIPI AXIS capture debug.
  ila_mipi_axis u_ila_mipi_axis (
    .clk    (cam_clk              ),
    .probe0 (dbg_mipi_axis_tvalid ),
    .probe1 (dbg_mipi_axis_tuser  ),
    .probe2 (dbg_mipi_axis_tlast  ),
    .probe3 (dbg_mipi_axis_tready ),
    .probe4 (dbg_mipi_axis_beat   ),
    .probe5 (dbg_mipi_axis_tdata  ),
    .probe6 (dbg_video_mode       )
  );

  assign led1 = mipi_csi_irq;
  assign led2 = mipi_demosaic_irq;
  assign led3 = mipi_gamma_irq;
  assign cam_hs = 1'b0;
  assign cam_vs = MIPI_AI_INPUT ? an5641_vs : 1'b0;
  assign cam_rgb = MIPI_AI_INPUT ? an5641_rgb : 24'd0;
  assign cam_clk = MIPI_AI_INPUT ? an5641_pixel_clk : ddr_clk;
  assign cam_data_en = MIPI_AI_INPUT ? an5641_de : 1'b0;
  assign direct_app_addr = direct_wr_app_pending ? direct_wr_app_addr : direct_rd_app_addr;
  assign direct_app_cmd = direct_wr_app_pending ? direct_wr_app_cmd : direct_rd_app_cmd;
  assign direct_app_en = direct_wr_app_pending ? direct_wr_app_en : direct_rd_app_en;
  assign direct_app_wdf_data = direct_wr_app_pending ? direct_wr_app_wdf_data : direct_rd_app_wdf_data;
  assign direct_app_wdf_end = direct_wr_app_pending ? direct_wr_app_wdf_end : direct_rd_app_wdf_end;
  assign direct_app_wdf_mask = direct_wr_app_pending ? direct_wr_app_wdf_mask : direct_rd_app_wdf_mask;
  assign direct_app_wdf_wren = direct_wr_app_pending ? direct_wr_app_wdf_wren : direct_rd_app_wdf_wren;
  assign app_addr = direct_ddr_active ? direct_app_addr : aimate_app_addr;
  assign app_cmd = direct_ddr_active ? direct_app_cmd : aimate_app_cmd;
  assign app_en = direct_ddr_active ? direct_app_en : aimate_app_en;
  assign app_wdf_data = direct_ddr_active ? direct_app_wdf_data : aimate_app_wdf_data;
  assign app_wdf_end = direct_ddr_active ? direct_app_wdf_end : aimate_app_wdf_end;
  assign app_wdf_mask = direct_ddr_active ? direct_app_wdf_mask : aimate_app_wdf_mask;
  assign app_wdf_wren = direct_ddr_active ? direct_app_wdf_wren : aimate_app_wdf_wren;
  assign eth_spare_axis_tdata  = 24'd0;
  assign eth_spare_axis_tvalid = 1'b0;
  assign eth_spare_axis_tlast  = 1'b0;
  assign eth_spare_axis_tuser  = 1'b0;

always @(posedge ddr_clk) begin
  if (ddr_clk_rst || ~ddr3_init_done) begin
    direct_video_rst_cnt <= 8'hff;
  end else if (video_mode_pulse) begin
    direct_video_rst_cnt <= 8'hff;
  end else if (direct_video_rst_cnt != 8'd0) begin
    direct_video_rst_cnt <= direct_video_rst_cnt - 8'd1;
  end
end

video_mode_ctrl #(
  .DEBOUNCE_BITS(20)
) u_video_mode_ctrl (
  .clk        (ddr_clk              ),
  .rst        (ddr_clk_rst          ),
  .button_raw (mode_button_f8       ),
  .mode       (legacy_video_mode    ),
  .mode_pulse (legacy_video_mode_pulse)
);

demo_clkrst_wrapper u_demo_clkrst_wrapper(
  .ddr_clk_led (ddr_clk_led ),
  .ps_clk_led  (ps_clk_led  ),

  .sys_rst     (core_rst    ),
  .soft_rst    (soft_rst    ),

  .ddr_clk     (ddr_clk     ),
  .ps_clk_out  (ps_clk_out  ),

  .gp_clk      (gp_clk      ),
  .hp_clk      (hp_clk      ),
  .gp_clk_rst  (gp_clk_rst  ),
  .hp_clk_rst  (hp_clk_rst  ),
  .ddr_clk_rst (ddr_clk_rst )
);

gp_io u_gp0_io(
  .M_AXI_GP_ARVALID (User_GP0_ARVALID ),
  .M_AXI_GP_AWVALID (User_GP0_AWVALID ),
  .M_AXI_GP_BREADY  (User_GP0_BREADY  ),
  .M_AXI_GP_RREADY  (User_GP0_RREADY  ),
  .M_AXI_GP_WLAST   (User_GP0_WLAST   ),
  .M_AXI_GP_WVALID  (User_GP0_WVALID  ),
  .M_AXI_GP_ARID    (User_GP0_ARID    ),
  .M_AXI_GP_AWID    (User_GP0_AWID    ),
  .M_AXI_GP_WID     (User_GP0_WID     ),
  .M_AXI_GP_ARBURST (User_GP0_ARBURST ),
  .M_AXI_GP_ARLOCK  (User_GP0_ARLOCK  ),
  .M_AXI_GP_ARSIZE  (User_GP0_ARSIZE  ),
  .M_AXI_GP_AWBURST (User_GP0_AWBURST ),
  .M_AXI_GP_AWLOCK  (User_GP0_AWLOCK  ),
  .M_AXI_GP_AWSIZE  (User_GP0_AWSIZE  ),
  .M_AXI_GP_ARPROT  (User_GP0_ARPROT  ),
  .M_AXI_GP_AWPROT  (User_GP0_AWPROT  ),
  .M_AXI_GP_ARADDR  (User_GP0_ARADDR  ),
  .M_AXI_GP_AWADDR  (User_GP0_AWADDR  ),
  .M_AXI_GP_WDATA   (User_GP0_WDATA   ),
  .M_AXI_GP_ARCACHE (User_GP0_ARCACHE ),
  .M_AXI_GP_ARLEN   (User_GP0_ARLEN   ),
  .M_AXI_GP_ARQOS   (User_GP0_ARQOS   ),
  .M_AXI_GP_AWCACHE (User_GP0_AWCACHE ),
  .M_AXI_GP_AWLEN   (User_GP0_AWLEN   ),
  .M_AXI_GP_AWQOS   (User_GP0_AWQOS   ),
  .M_AXI_GP_WSTRB   (User_GP0_WSTRB   ),
  .M_AXI_GP_ACLK    (User_GP0_ACLK    ),
  .M_AXI_GP_ARREADY (User_GP0_ARREADY ),
  .M_AXI_GP_AWREADY (User_GP0_AWREADY ),
  .M_AXI_GP_BVALID  (User_GP0_BVALID  ),
  .M_AXI_GP_RLAST   (User_GP0_RLAST   ),
  .M_AXI_GP_RVALID  (User_GP0_RVALID  ),
  .M_AXI_GP_WREADY  (User_GP0_WREADY  ),
  .M_AXI_GP_BID     (User_GP0_BID     ),
  .M_AXI_GP_RID     (User_GP0_RID     ),
  .M_AXI_GP_BRESP   (User_GP0_BRESP   ),
  .M_AXI_GP_RRESP   (User_GP0_RRESP   ),
  .M_AXI_GP_RDATA   (User_GP0_RDATA   ),
  .gp               (gp0.master       ),
  .gp_clk_rst       (gp_clk_rst       ),
  .gp_clk           (gp_clk           )
);

gp0_manager 
#(
  .GP0_BASE       (32'h40000000       )
)
u_gp0_manager(
  .gpx       (gp0.slave            ),
  .host_ctrl (host_ctrl.master     ), //not used
  .ai_ra     (ai_ra.master         ), //not used
  .m2_gpx    (cam.master           ),
 
  .m3_gpx    (m3_gpx.master        ), //not used   //2026.3.13 zzx for uart 
  .gpx_rst   (gp_clk_rst           ),
  .gpx_clk   (gp_clk               )
);

gpx_RFU  #(.ERR(32'hA0AAAAAA)) u_host_ctrl_RFU(
  .gpx             (host_ctrl.slave            ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

gpx_RFU  #(.ERR(32'hA0AAAAAA)) u_ai_ra_RFU(
  .gpx             (ai_ra.slave                ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);
mna_gp2axi_lite_mipi #(
  .ADDR_WIDTH(MIPI_CTRL_AXI_ADDR_WIDTH)
) u_mipi_ctrl_gp2axi (
  .gpx            (m3_gpx.slave          ),
  .gpx_clk        (gp_clk                ),
  .gpx_rst        (gp_clk_rst            ),
  .S_AXI_ACLK     (mipi_ctrl_aclk        ),
  .S_AXI_ARESETN  (mipi_ctrl_aresetn     ),
  .S_AXI_AWADDR   (mipi_ctrl_awaddr      ),
  .S_AXI_AWPROT   (mipi_ctrl_awprot      ),
  .S_AXI_AWVALID  (mipi_ctrl_awvalid     ),
  .S_AXI_AWREADY  (mipi_ctrl_awready     ),
  .S_AXI_WDATA    (mipi_ctrl_wdata       ),
  .S_AXI_WSTRB    (mipi_ctrl_wstrb       ),
  .S_AXI_WVALID   (mipi_ctrl_wvalid      ),
  .S_AXI_WREADY   (mipi_ctrl_wready      ),
  .S_AXI_BRESP    (mipi_ctrl_bresp       ),
  .S_AXI_BVALID   (mipi_ctrl_bvalid      ),
  .S_AXI_BREADY   (mipi_ctrl_bready      ),
  .S_AXI_ARADDR   (mipi_ctrl_araddr      ),
  .S_AXI_ARPROT   (mipi_ctrl_arprot      ),
  .S_AXI_ARVALID  (mipi_ctrl_arvalid     ),
  .S_AXI_ARREADY  (mipi_ctrl_arready     ),
  .S_AXI_RDATA    (mipi_ctrl_rdata       ),
  .S_AXI_RRESP    (mipi_ctrl_rresp       ),
  .S_AXI_RVALID   (mipi_ctrl_rvalid      ),
  .S_AXI_RREADY   (mipi_ctrl_rready      )
);
gp_io u_gp1_io(
  .M_AXI_GP_ARVALID (User_GP1_ARVALID  ),
  .M_AXI_GP_AWVALID (User_GP1_AWVALID  ),
  .M_AXI_GP_BREADY  (User_GP1_BREADY   ),
  .M_AXI_GP_RREADY  (User_GP1_RREADY   ),
  .M_AXI_GP_WLAST   (User_GP1_WLAST    ),
  .M_AXI_GP_WVALID  (User_GP1_WVALID   ),
  .M_AXI_GP_ARID    (User_GP1_ARID     ),
  .M_AXI_GP_AWID    (User_GP1_AWID     ),
  .M_AXI_GP_WID     (User_GP1_WID      ),
  .M_AXI_GP_ARBURST (User_GP1_ARBURST  ),
  .M_AXI_GP_ARLOCK  (User_GP1_ARLOCK   ),
  .M_AXI_GP_ARSIZE  (User_GP1_ARSIZE   ),
  .M_AXI_GP_AWBURST (User_GP1_AWBURST  ),
  .M_AXI_GP_AWLOCK  (User_GP1_AWLOCK   ),
  .M_AXI_GP_AWSIZE  (User_GP1_AWSIZE   ),
  .M_AXI_GP_ARPROT  (User_GP1_ARPROT   ),
  .M_AXI_GP_AWPROT  (User_GP1_AWPROT   ),
  .M_AXI_GP_ARADDR  (User_GP1_ARADDR   ),
  .M_AXI_GP_AWADDR  (User_GP1_AWADDR   ),
  .M_AXI_GP_WDATA   (User_GP1_WDATA    ),
  .M_AXI_GP_ARCACHE (User_GP1_ARCACHE  ),
  .M_AXI_GP_ARLEN   (User_GP1_ARLEN    ),
  .M_AXI_GP_ARQOS   (User_GP1_ARQOS    ),
  .M_AXI_GP_AWCACHE (User_GP1_AWCACHE  ),
  .M_AXI_GP_AWLEN   (User_GP1_AWLEN    ),
  .M_AXI_GP_AWQOS   (User_GP1_AWQOS    ),
  .M_AXI_GP_WSTRB   (User_GP1_WSTRB    ),
  .M_AXI_GP_ACLK    (User_GP1_ACLK     ),
  .M_AXI_GP_ARREADY (User_GP1_ARREADY  ),
  .M_AXI_GP_AWREADY (User_GP1_AWREADY  ),
  .M_AXI_GP_BVALID  (User_GP1_BVALID   ),
  .M_AXI_GP_RLAST   (User_GP1_RLAST    ),
  .M_AXI_GP_RVALID  (User_GP1_RVALID   ),
  .M_AXI_GP_WREADY  (User_GP1_WREADY   ),
  .M_AXI_GP_BID     (User_GP1_BID      ),
  .M_AXI_GP_RID     (User_GP1_RID      ),
  .M_AXI_GP_BRESP   (User_GP1_BRESP    ),
  .M_AXI_GP_RRESP   (User_GP1_RRESP    ),
  .M_AXI_GP_RDATA   (User_GP1_RDATA    ),
  .gp               (gp1.master        ),
  .gp_clk_rst       (gp_clk_rst        ),
  .gp_clk           (gp_clk            )
);

user_gp1_manager #(.GP1_BASE(32'h80000000   ))user_gp1_manager_u0(
    .gpx          (gp1.slave           ) ,    
    .cam_gp1_s00  (cdma_ctrl.master    ) , // not used
    .cam_gp1_s01  (cam_gp1_s01.master  ) , // not used
    .cam_gp1_s02  (cam_gp1_s02.master  ) , // not used, reserved for AI_Mate/user regs
    .cam_gp1_s03  (cam_gp1_s03.master  ) , // not used, reserved for AI_Mate/user regs
    .gpx_rst      (gp_clk_rst          ) ,
    .gpx_clk      (gp_clk              ) 
);

gpx_RFU  #(.ERR(32'hB0AAAAAA)) u_cdma_ctrl_RFU(
  .gpx             (cdma_ctrl.slave            ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

gpx_RFU  #(.ERR(32'hB0AAAAAA)) u_cam_gp1_s01_RFU(
  .gpx             (cam_gp1_s01.slave          ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

gpx_RFU  #(.ERR(32'hB0AAAAAA)) u_cam_gp1_s02_RFU(
  .gpx             (cam_gp1_s02.slave          ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

gpx_RFU  #(.ERR(32'hB0AAAAAA)) u_cam_gp1_s03_RFU(
  .gpx             (cam_gp1_s03.slave          ),    
  .gpx_rst         (gp_clk_rst                 ),
  .gpx_clk         (gp_clk                     )
);

mipi_capture_axis #(
  .ADDR_WIDTH(MIPI_CTRL_AXI_ADDR_WIDTH)
) u_mipi_capture_axis (
  .diag_frames_in (an5641_frames_in_gp),
  .diag_frames_out (an5641_frames_out_gp),
  .diag_lines (an5641_lines_gp),
  .diag_errors (an5641_errors_gp),
  .diag_stalls (an5641_stalls_gp),

  .ctrl_aclk              (mipi_ctrl_aclk             ),
  .ctrl_aresetn           (mipi_ctrl_aresetn          ),
  .video_aclk             (cam_clk                    ),
  .video_aresetn          (~an5641_pixel_reset        ),
  .dphy_clk_200m          (ddr_clk                    ),
  .s_axi_awaddr           (mipi_ctrl_awaddr           ),
  .s_axi_awprot           (mipi_ctrl_awprot           ),
  .s_axi_awvalid          (mipi_ctrl_awvalid          ),
  .s_axi_awready          (mipi_ctrl_awready          ),
  .s_axi_wdata            (mipi_ctrl_wdata            ),
  .s_axi_wstrb            (mipi_ctrl_wstrb            ),
  .s_axi_wvalid           (mipi_ctrl_wvalid           ),
  .s_axi_wready           (mipi_ctrl_wready           ),
  .s_axi_bresp            (mipi_ctrl_bresp            ),
  .s_axi_bvalid           (mipi_ctrl_bvalid           ),
  .s_axi_bready           (mipi_ctrl_bready           ),
  .s_axi_araddr           (mipi_ctrl_araddr           ),
  .s_axi_arprot           (mipi_ctrl_arprot           ),
  .s_axi_arvalid          (mipi_ctrl_arvalid          ),
  .s_axi_arready          (mipi_ctrl_arready          ),
  .s_axi_rdata            (mipi_ctrl_rdata            ),
  .s_axi_rresp            (mipi_ctrl_rresp            ),
  .s_axi_rvalid           (mipi_ctrl_rvalid           ),
  .s_axi_rready           (mipi_ctrl_rready           ),
  .mipi_phy_if_clk_hs_n   (mipi_phy_if_0_clk_hs_n     ),
  .mipi_phy_if_clk_hs_p   (mipi_phy_if_0_clk_hs_p     ),
  .mipi_phy_if_clk_lp_n   (mipi_phy_if_0_clk_lp_n     ),
  .mipi_phy_if_clk_lp_p   (mipi_phy_if_0_clk_lp_p     ),
  .mipi_phy_if_data_hs_n  (mipi_phy_if_0_data_hs_n    ),
  .mipi_phy_if_data_hs_p  (mipi_phy_if_0_data_hs_p    ),
  .mipi_phy_if_data_lp_n  (mipi_phy_if_0_data_lp_n    ),
  .mipi_phy_if_data_lp_p  (mipi_phy_if_0_data_lp_p    ),
  .m_axis_tdata           (mipi_axis_tdata            ),
  .m_axis_tvalid          (mipi_axis_tvalid           ),
  .m_axis_tready          (mipi_axis_tready           ),
  .m_axis_tuser           (mipi_axis_tuser            ),
  .m_axis_tlast           (mipi_axis_tlast            ),
  .csi_irq                (mipi_csi_irq               ),
  .demosaic_irq           (mipi_demosaic_irq          ),
  .gamma_irq              (mipi_gamma_irq             ),
  .dlyctrl_rdy            (mipi_dlyctrl_rdy           ),
  .csi_system_rst         (mipi_csi_system_rst        )
);

config_s config_s_inst(
    .gp_clk                     (gp_clk                 ),
    .pll_lock                   (pll_lock               ),
    .cam0_clk                   (cam_clk                ),
    .cam1_clk                   (0                      ),
    .cam2_clk                   (0                      ),
    .cam3_clk                   (0                      ),

		.reset_cam0_clk             (reset_cam_clk          ),
    .reset_cam1_clk             (                       ),
    .reset_cam2_clk             (                       ),
    .reset_cam3_clk             (                       ),

    .si5368_i2c_scl_io          (si5368_i2c_scl_io      ), 
    .si5368_i2c_sda_io          (si5368_i2c_sda_io      ), 
    .si5368_rst_n               (si5368_rst_n           )	
);

vtc u_vtc(
    .clk           ( cam_clk         ),
    .rst_n         ( ~reset_cam_clk  ),

    .H_SYNC        (H_SYNC           ),
    .H_BACK_PORCH  (H_BACK_PORCH     ),
    .H_ACTIVE      (H_ACTIVE         ),
    .H_FRONT_PORCH (H_FRONT_PORCH    ),
    .V_SYNC        (V_SYNC           ),
    .V_BACK_PORCH  (V_BACK_PORCH     ),
    .V_ACTIVE      (V_ACTIVE        ),
    .V_FRONT_PORCH (V_FRONT_PORCH    ),  

    .data          ( vtc_data        ),
    .vs            ( vtc_vs          ),
    .hs            ( vtc_hs          ),
    .de            ( vtc_de          ) 
);
frame_to_ps_largebuf frame_to_ps_inst0(
    .cam_clk_use           (cam_clk              ),
    .reset_cam_clk         (reset_cam_clk        ),  
 
    .cmos_vsync_out        (cmos_vsync_out       ),
    .cmos_href_out         (cmos_href_out        ),
    .cmos_db_out           (cmos_db_out          ),    

    .display_en            (display_en            ),

    .reset_100mhz_n        (si5368_rst_n          ),
	  .HDMI_CLK_P            (HDMI_CLK_P            ),   
    .HDMI_CLK_N            (HDMI_CLK_N            ),
    .HDMI_TX_P             (HDMI_TX_P             ),
    .HDMI_TX_N             (HDMI_TX_N             ),   
        
    // master axi interface, connect HP 
    .m00_axi_aclk          (hp_clk               ),
    .m00_axi_aresetn       (~hp_clk_rst          ),
    .m00_axi_awid          (S_AXI_HP2_AWID        ),
    .m00_axi_awaddr        (S_AXI_HP2_AWADDR      ),
    .m00_axi_awlen         (S_AXI_HP2_AWLEN       ),
    .m00_axi_awsize        (S_AXI_HP2_AWSIZE      ),
    .m00_axi_awburst       (S_AXI_HP2_AWBURST     ),       
    .m00_axi_awlock        (S_AXI_HP2_AWLOCK      ),   
    .m00_axi_awcache       (S_AXI_HP2_AWCACHE     ),  
    .m00_axi_awprot        (S_AXI_HP2_AWPROT      ),   
    .m00_axi_awqos         (S_AXI_HP2_AWQOS       ),    
    .m00_axi_awuser        (                      ),  
    .m00_axi_awvalid       (S_AXI_HP2_AWVALID     ),
    .m00_axi_awready       (S_AXI_HP2_AWREADY     ),
	       
    .m00_axi_wdata         (S_AXI_HP2_WDATA       ),
    .m00_axi_wstrb         (S_AXI_HP2_WSTRB       ),
    .m00_axi_wlast         (S_AXI_HP2_WLAST       ),
    .m00_axi_wuser         (                      ),
    .m00_axi_wvalid        (S_AXI_HP2_WVALID      ),
    .m00_axi_wready        (S_AXI_HP2_WREADY      ),
	       
    .m00_axi_bid           (S_AXI_HP2_BID         ),
    .m00_axi_bresp         (S_AXI_HP2_BRESP       ),
    .m00_axi_buser         (1'b0                  ),
    .m00_axi_bvalid        (S_AXI_HP2_BVALID      ),
    .m00_axi_bready        (S_AXI_HP2_BREADY      ),
	       
    .m00_axi_arid          (S_AXI_HP2_ARID        ),
    .m00_axi_araddr        (S_AXI_HP2_ARADDR      ),
    .m00_axi_arlen         (S_AXI_HP2_ARLEN       ),
    .m00_axi_arsize        (S_AXI_HP2_ARSIZE      ),
    .m00_axi_arburst       (S_AXI_HP2_ARBURST     ),
    .m00_axi_arlock        (S_AXI_HP2_ARLOCK      ),
    .m00_axi_arcache       (S_AXI_HP2_ARCACHE     ),
    .m00_axi_arprot        (S_AXI_HP2_ARPROT      ),
    .m00_axi_arqos         (S_AXI_HP2_ARQOS       ),
    .m00_axi_aruser        (                      ),
    .m00_axi_arvalid       (S_AXI_HP2_ARVALID     ),
    .m00_axi_arready       (S_AXI_HP2_ARREADY     ),
	           
    .m00_axi_rid           (S_AXI_HP2_RID         ),
    .m00_axi_rdata         (S_AXI_HP2_RDATA       ),
    .m00_axi_rresp         (S_AXI_HP2_RRESP       ),
    .m00_axi_rlast         (S_AXI_HP2_RLAST       ),
    .m00_axi_ruser         (1'b0                  ),
    .m00_axi_rvalid        (S_AXI_HP2_RVALID      ),
    .m00_axi_rready        (S_AXI_HP2_RREADY      ), 

    //ps rsize config
    .ps_x0_pos             (ps_x0_pos            ),
    .ps_y0_pos             (ps_y0_pos            ),
    .ps_x1_pos             (ps_x1_pos            ),
    .ps_y1_pos             (ps_y1_pos            ),
    .ps_x_leng             (ps_x_leng            ),
    .ps_y_leng             (ps_y_leng            ),
    .ps_hstride            (ps_hstride           ),
    .ps_vstride            (ps_vstride           ),
    .resize_pix_len        (resize_pix_len       ),			
    .write_ps_size         (write_ps_size        ),

    .camera_wr_addr       (camera_wr_addr        ),
    .camera_rd_addr       (camera_rd_addr        ),
    .wr_wfifo_err         (wr_wfifo_err          ),
    .rd_rfifo_err         (rd_rfifo_err          ),
    .wr_done_pulse        (wr_done_pulse         ), 
    .dip_switches         (dip_switches          ),
    .ch0_write_addr_index (write_addr_index      ),
    .ch0_read_addr_index  (read_addr_index       )  
 );

 assign S_AXI_HP2_RDISSUECAP1_EN = 1'b0;
 assign S_AXI_HP2_WRISSUECAP1_EN = 1'b0;
 assign S_AXI_HP2_WID = 6'h00;

frame_trans frame_trans_inst0(
    // cmos
    .cam_vs              (cam_vs                ),
    .cam_de              (cam_data_en           ),
    .cam_rgb             (cam_rgb               ),
    .vtc_vs              (vtc_vs                ),
    .vtc_de              (vtc_de                ),
    .vtc_data            (vtc_data              ),
    
    .cam_clk             (cam_clk               ),
		.reset_cam_clk       (reset_cam_clk         ),
         
    .cmos_vsync_out      (cmos_vsync_out        ),
    .cmos_href_out       (cmos_href_out         ),
    .cmos_db_out         (cmos_db_out           ),  

    // slave axi lite interface??connect frame_ctrl
    .S_AXI_ACLK          (gp_clk                ),//50M
    .S_AXI_ARESETN       (~gp_clk_rst           ),
    .cam                 (cam.slave             ),	  
    
    //ps rsize config
    .ps_x0_pos           (ps_x0_pos             ),
    .ps_y0_pos           (ps_y0_pos             ),
    .ps_x1_pos           (ps_x1_pos             ),
    .ps_y1_pos           (ps_y1_pos             ),
    .ps_x_leng           (ps_x_leng             ),
    .ps_y_leng           (ps_y_leng             ),
    .ps_hstride          (ps_hstride            ),
    .ps_vstride          (ps_vstride            ),	
    .resize_pix_len      (resize_pix_len        ),			
    .write_ps_size       (write_ps_size         ),
    .H_SYNC              (H_SYNC                ),
    .H_BACK_PORCH        (H_BACK_PORCH          ),
    .H_ACTIVE            (H_ACTIVE              ),
    .H_FRONT_PORCH       (H_FRONT_PORCH         ),
    .V_SYNC              (V_SYNC                ),
    .V_BACK_PORCH        (V_BACK_PORCH          ),
    .V_ACTIVE            (V_ACTIVE              ),
    .V_FRONT_PORCH       (V_FRONT_PORCH         ),      

    //img_data for image_make 
    .M01_AXI_ACLK        (ddr_clk               ),
    .M01_AXI_ARESETN     (~ddr_clk_rst          ),    
    .img_start           (img_start1            ),
    .img_data            (img_data1             ),
    .img_valid           (img_valid1            ),
    .img_ready           (img_ready1            ),  

    //frame mode 
    .continuous_en       (continuous_en         ),  
    .display_en          (display_en            ),
    .wr_done_pulse       (wr_done_pulse         ),
    .wr_wfifo_err        (wr_wfifo_err          ),
    .rd_rfifo_err        (rd_rfifo_err          ),
    .camera_wr_addr      (camera_wr_addr        ),
    .camera_rd_addr      (camera_rd_addr        ),
    .npu_en               (npu_en)              ,
    .irq_test            (test_irq              ),
    .write_addr_index    (write_addr_index      ),
    .read_addr_index     (read_addr_index       ),
    .sys_rst_n           (sys_rst_n & FCLK_RESET0_N ),
    .soft_rst            (soft_rst              )         
);

assign S_AXI_HP0_RDISSUECAP1_EN = 1'b0;
assign S_AXI_HP0_WRISSUECAP1_EN = 1'b0;
assign S_AXI_HP1_RDISSUECAP1_EN = 1'b0;
assign S_AXI_HP1_WRISSUECAP1_EN = 1'b0;

assign S_AXI_HP3_RDISSUECAP1_EN = 1'b0;
assign S_AXI_HP3_WRISSUECAP1_EN = 1'b0;

ps_ai_wrapper ps_ai_wrapper_u0 (
    .FIXED_IO_mio              (FIXED_IO_0_mio         ),
    .FIXED_IO_ps_srstb         (FIXED_IO_0_ps_srstb    ),
    .FIXED_IO_ps_clk           (FIXED_IO_0_ps_clk      ),
    .FIXED_IO_ps_porb          (FIXED_IO_0_ps_porb     ),
    .DDR_ck_p                  (DDR_0_ck_p             ),
    .DDR_ck_n                  (DDR_0_ck_n             ),
    .DDR_cke                   (DDR_0_cke              ),
    .DDR_cs_n                  (DDR_0_cs_n             ),
    .DDR_ras_n                 (DDR_0_ras_n            ),
    .DDR_cas_n                 (DDR_0_cas_n            ),
    .DDR_we_n                  (DDR_0_we_n             ),
    .DDR_ba                    (DDR_0_ba               ),
    .DDR_addr                  (DDR_0_addr             ),
    .DDR_odt                   (DDR_0_odt              ),
    .DDR_reset_n               (DDR_0_reset_n          ),
    .DDR_dq                    (DDR_0_dq               ),
    .DDR_dm                    (DDR_0_dm               ),
    .DDR_dqs_p                 (DDR_0_dqs_p            ),
    .DDR_dqs_n                 (DDR_0_dqs_n            ),
    .FIXED_IO_ddr_vrn          (FIXED_IO_0_ddr_vrn     ),
    .FIXED_IO_ddr_vrp          (FIXED_IO_0_ddr_vrp     ),
    .GPIO_0_tri_io             (GPIO_0_tri_io          ),
    .IIC_0_scl_io              (IIC_0_scl_io           ),
    .IIC_0_sda_io              (IIC_0_sda_io           ),
      
    .reset_n                   (sys_rst_n & FCLK_RESET0_N ), 
    .FCLK_RESET0_N             (FCLK_RESET0_N          ),
    .soft_rst_n                (~soft_rst              ),
      
    .PJTAG_TCK                 (PJTAG_TCK              ),
    .PJTAG_TMS                 (PJTAG_TMS              ),
    .PJTAG_TDI                 (PJTAG_TDI              ),
    .PJTAG_TDO                 (PJTAG_TDO              ), 
            
    .hp_axi_aclk               (hp_clk                 ),
    .ps_clk_out                (ps_clk_out             ),
    .pll_lock                  (pll_lock               ),
      
    .BYolo_GP0_ARVALID         (BYolo_GP0_ARVALID      ),
    .BYolo_GP0_AWVALID         (BYolo_GP0_AWVALID      ),
    .BYolo_GP0_BREADY          (BYolo_GP0_BREADY       ),
    .BYolo_GP0_RREADY          (BYolo_GP0_RREADY       ),
    .BYolo_GP0_WLAST           (BYolo_GP0_WLAST        ),
    .BYolo_GP0_WVALID          (BYolo_GP0_WVALID       ),
    .BYolo_GP0_ARID            (BYolo_GP0_ARID         ),
    .BYolo_GP0_AWID            (BYolo_GP0_AWID         ),
    .BYolo_GP0_WID             (BYolo_GP0_WID          ),
    .BYolo_GP0_ARBURST         (BYolo_GP0_ARBURST      ),
    .BYolo_GP0_ARLOCK          (BYolo_GP0_ARLOCK       ),
    .BYolo_GP0_ARSIZE          (BYolo_GP0_ARSIZE       ),
    .BYolo_GP0_AWBURST         (BYolo_GP0_AWBURST      ),
    .BYolo_GP0_AWLOCK          (BYolo_GP0_AWLOCK       ),
    .BYolo_GP0_AWSIZE          (BYolo_GP0_AWSIZE       ),
    .BYolo_GP0_ARPROT          (BYolo_GP0_ARPROT       ),
    .BYolo_GP0_AWPROT          (BYolo_GP0_AWPROT       ),
    .BYolo_GP0_ARADDR          (BYolo_GP0_ARADDR       ),
    .BYolo_GP0_AWADDR          (BYolo_GP0_AWADDR       ),
    .BYolo_GP0_WDATA           (BYolo_GP0_WDATA        ),
    .BYolo_GP0_ARCACHE         (BYolo_GP0_ARCACHE      ),
    .BYolo_GP0_ARLEN           (BYolo_GP0_ARLEN        ),
    .BYolo_GP0_ARQOS           (BYolo_GP0_ARQOS        ),
    .BYolo_GP0_AWCACHE         (BYolo_GP0_AWCACHE      ),
    .BYolo_GP0_AWLEN           (BYolo_GP0_AWLEN        ),
    .BYolo_GP0_AWQOS           (BYolo_GP0_AWQOS        ),
    .BYolo_GP0_WSTRB           (BYolo_GP0_WSTRB        ),
    .BYolo_GP0_ARREADY         (BYolo_GP0_ARREADY      ),
    .BYolo_GP0_AWREADY         (BYolo_GP0_AWREADY      ),
    .BYolo_GP0_BVALID          (BYolo_GP0_BVALID       ),
    .BYolo_GP0_RLAST           (BYolo_GP0_RLAST        ),
    .BYolo_GP0_RVALID          (BYolo_GP0_RVALID       ),
    .BYolo_GP0_WREADY          (BYolo_GP0_WREADY       ),
    .BYolo_GP0_BID             (BYolo_GP0_BID          ),
    .BYolo_GP0_RID             (BYolo_GP0_RID          ),
    .BYolo_GP0_BRESP           (BYolo_GP0_BRESP        ),
    .BYolo_GP0_RRESP           (BYolo_GP0_RRESP        ),
    .BYolo_GP0_RDATA           (BYolo_GP0_RDATA        ),
          
    .BYolo_GP1_ARVALID         (BYolo_GP1_ARVALID      ),
    .BYolo_GP1_AWVALID         (BYolo_GP1_AWVALID      ),
    .BYolo_GP1_BREADY          (BYolo_GP1_BREADY       ),
    .BYolo_GP1_RREADY          (BYolo_GP1_RREADY       ),
    .BYolo_GP1_WLAST           (BYolo_GP1_WLAST        ),
    .BYolo_GP1_WVALID          (BYolo_GP1_WVALID       ),
    .BYolo_GP1_ARID            (BYolo_GP1_ARID         ),
    .BYolo_GP1_AWID            (BYolo_GP1_AWID         ),
    .BYolo_GP1_WID             (BYolo_GP1_WID          ),
    .BYolo_GP1_ARBURST         (BYolo_GP1_ARBURST      ),
    .BYolo_GP1_ARLOCK          (BYolo_GP1_ARLOCK       ),
    .BYolo_GP1_ARSIZE          (BYolo_GP1_ARSIZE       ),
    .BYolo_GP1_AWBURST         (BYolo_GP1_AWBURST      ),
    .BYolo_GP1_AWLOCK          (BYolo_GP1_AWLOCK       ),
    .BYolo_GP1_AWSIZE          (BYolo_GP1_AWSIZE       ),
    .BYolo_GP1_ARPROT          (BYolo_GP1_ARPROT       ),
    .BYolo_GP1_AWPROT          (BYolo_GP1_AWPROT       ),
    .BYolo_GP1_ARADDR          (BYolo_GP1_ARADDR       ),
    .BYolo_GP1_AWADDR          (BYolo_GP1_AWADDR       ),
    .BYolo_GP1_WDATA           (BYolo_GP1_WDATA        ),
    .BYolo_GP1_ARCACHE         (BYolo_GP1_ARCACHE      ),
    .BYolo_GP1_ARLEN           (BYolo_GP1_ARLEN        ),
    .BYolo_GP1_ARQOS           (BYolo_GP1_ARQOS        ),
    .BYolo_GP1_AWCACHE         (BYolo_GP1_AWCACHE      ),
    .BYolo_GP1_AWLEN           (BYolo_GP1_AWLEN        ),
    .BYolo_GP1_AWQOS           (BYolo_GP1_AWQOS        ),
    .BYolo_GP1_WSTRB           (BYolo_GP1_WSTRB        ),
    .BYolo_GP1_ARREADY         (BYolo_GP1_ARREADY      ),
    .BYolo_GP1_AWREADY         (BYolo_GP1_AWREADY      ),
    .BYolo_GP1_BVALID          (BYolo_GP1_BVALID       ),
    .BYolo_GP1_RLAST           (BYolo_GP1_RLAST        ),
    .BYolo_GP1_RVALID          (BYolo_GP1_RVALID       ),
    .BYolo_GP1_WREADY          (BYolo_GP1_WREADY       ),
    .BYolo_GP1_BID             (BYolo_GP1_BID          ),
    .BYolo_GP1_RID             (BYolo_GP1_RID          ),
    .BYolo_GP1_BRESP           (BYolo_GP1_BRESP        ),
    .BYolo_GP1_RRESP           (BYolo_GP1_RRESP        ),
    .BYolo_GP1_RDATA           (BYolo_GP1_RDATA        ),
    .uart_rtl_0_rxd            (uart_rtl_0_rxd         ), 
    .uart_rtl_0_txd            (uart_rtl_0_txd         ), 
    .User_GP0_ARVALID          (User_GP0_ARVALID       ),
    .User_GP0_AWVALID          (User_GP0_AWVALID       ),
    .User_GP0_BREADY           (User_GP0_BREADY        ),
    .User_GP0_RREADY           (User_GP0_RREADY        ),
    .User_GP0_WLAST            (User_GP0_WLAST         ),
    .User_GP0_WVALID           (User_GP0_WVALID        ),
    .User_GP0_ARID             (User_GP0_ARID          ),
    .User_GP0_AWID             (User_GP0_AWID          ),
    .User_GP0_WID              (User_GP0_WID           ),
    .User_GP0_ARBURST          (User_GP0_ARBURST       ),
    .User_GP0_ARLOCK           (User_GP0_ARLOCK        ),
    .User_GP0_ARSIZE           (User_GP0_ARSIZE        ),
    .User_GP0_AWBURST          (User_GP0_AWBURST       ),
    .User_GP0_AWLOCK           (User_GP0_AWLOCK        ),
    .User_GP0_AWSIZE           (User_GP0_AWSIZE        ),
    .User_GP0_ARPROT           (User_GP0_ARPROT        ),
    .User_GP0_AWPROT           (User_GP0_AWPROT        ),
    .User_GP0_ARADDR           (User_GP0_ARADDR        ),
    .User_GP0_AWADDR           (User_GP0_AWADDR        ),
    .User_GP0_WDATA            (User_GP0_WDATA         ),
    .User_GP0_ARCACHE          (User_GP0_ARCACHE       ),
    .User_GP0_ARLEN            (User_GP0_ARLEN         ),
    .User_GP0_ARQOS            (User_GP0_ARQOS         ),
    .User_GP0_AWCACHE          (User_GP0_AWCACHE       ),
    .User_GP0_AWLEN            (User_GP0_AWLEN         ),
    .User_GP0_AWQOS            (User_GP0_AWQOS         ),
    .User_GP0_WSTRB            (User_GP0_WSTRB         ),
    .User_GP0_ARREADY          (User_GP0_ARREADY       ),
    .User_GP0_AWREADY          (User_GP0_AWREADY       ),
    .User_GP0_BVALID           (User_GP0_BVALID        ),
    .User_GP0_RLAST            (User_GP0_RLAST         ),
    .User_GP0_RVALID           (User_GP0_RVALID        ),
    .User_GP0_WREADY           (User_GP0_WREADY        ),
    .User_GP0_BID              (User_GP0_BID           ),
    .User_GP0_RID              (User_GP0_RID           ),
    .User_GP0_BRESP            (User_GP0_BRESP         ),
    .User_GP0_RRESP            (User_GP0_RRESP         ),
    .User_GP0_RDATA            (User_GP0_RDATA         ),
          
    .User_GP1_ARVALID          (User_GP1_ARVALID       ),
    .User_GP1_AWVALID          (User_GP1_AWVALID       ),
    .User_GP1_BREADY           (User_GP1_BREADY        ),
    .User_GP1_RREADY           (User_GP1_RREADY        ),
    .User_GP1_WLAST            (User_GP1_WLAST         ),
    .User_GP1_WVALID           (User_GP1_WVALID        ),
    .User_GP1_ARID             (User_GP1_ARID          ),
    .User_GP1_AWID             (User_GP1_AWID          ),
    .User_GP1_WID              (User_GP1_WID           ),
    .User_GP1_ARBURST          (User_GP1_ARBURST       ),
    .User_GP1_ARLOCK           (User_GP1_ARLOCK        ),
    .User_GP1_ARSIZE           (User_GP1_ARSIZE        ),
    .User_GP1_AWBURST          (User_GP1_AWBURST       ),
    .User_GP1_AWLOCK           (User_GP1_AWLOCK        ),
    .User_GP1_AWSIZE           (User_GP1_AWSIZE        ),
    .User_GP1_ARPROT           (User_GP1_ARPROT        ),
    .User_GP1_AWPROT           (User_GP1_AWPROT        ),
    .User_GP1_ARADDR           (User_GP1_ARADDR        ),
    .User_GP1_AWADDR           (User_GP1_AWADDR        ),
    .User_GP1_WDATA            (User_GP1_WDATA         ),
    .User_GP1_ARCACHE          (User_GP1_ARCACHE       ),
    .User_GP1_ARLEN            (User_GP1_ARLEN         ),
    .User_GP1_ARQOS            (User_GP1_ARQOS         ),
    .User_GP1_AWCACHE          (User_GP1_AWCACHE       ),
    .User_GP1_AWLEN            (User_GP1_AWLEN         ),
    .User_GP1_AWQOS            (User_GP1_AWQOS         ),
    .User_GP1_WSTRB            (User_GP1_WSTRB         ),
    .User_GP1_ARREADY          (User_GP1_ARREADY       ),
    .User_GP1_AWREADY          (User_GP1_AWREADY       ),
    .User_GP1_BVALID           (User_GP1_BVALID        ),
    .User_GP1_RLAST            (User_GP1_RLAST         ),
    .User_GP1_RVALID           (User_GP1_RVALID        ),
    .User_GP1_WREADY           (User_GP1_WREADY        ),
    .User_GP1_BID              (User_GP1_BID           ),
    .User_GP1_RID              (User_GP1_RID           ),
    .User_GP1_BRESP            (User_GP1_BRESP         ),
    .User_GP1_RRESP            (User_GP1_RRESP         ),
    .User_GP1_RDATA            (User_GP1_RDATA         ),  

    .S_AXI_HP0_ARADDR          (S0_AXI_HP_HC_ARADDR    ),
    .S_AXI_HP0_ARBURST         (S0_AXI_HP_HC_ARBURST   ),
    .S_AXI_HP0_ARCACHE         (S0_AXI_HP_HC_ARCACHE   ),
    .S_AXI_HP0_ARID            (S0_AXI_HP_HC_ARID      ),
    .S_AXI_HP0_ARLEN           (S0_AXI_HP_HC_ARLEN     ),
    .S_AXI_HP0_ARLOCK          (S0_AXI_HP_HC_ARLOCK    ),
    .S_AXI_HP0_ARPROT          (S0_AXI_HP_HC_ARPROT    ),
    .S_AXI_HP0_ARQOS           (S0_AXI_HP_HC_ARQOS     ),
    .S_AXI_HP0_ARREADY         (S0_AXI_HP_HC_ARREADY   ),
    .S_AXI_HP0_ARSIZE          (S0_AXI_HP_HC_ARSIZE    ),
    .S_AXI_HP0_ARVALID         (S0_AXI_HP_HC_ARVALID   ),
    .S_AXI_HP0_AWADDR          (S0_AXI_HP_HC_AWADDR    ),
    .S_AXI_HP0_AWBURST         (S0_AXI_HP_HC_AWBURST   ),
    .S_AXI_HP0_AWCACHE         (S0_AXI_HP_HC_AWCACHE   ),
    .S_AXI_HP0_AWID            (S0_AXI_HP_HC_AWID      ),
    .S_AXI_HP0_AWLEN           (S0_AXI_HP_HC_AWLEN     ),
    .S_AXI_HP0_AWLOCK          (S0_AXI_HP_HC_AWLOCK    ),
    .S_AXI_HP0_AWPROT          (S0_AXI_HP_HC_AWPROT    ),
    .S_AXI_HP0_AWQOS           (S0_AXI_HP_HC_AWQOS     ),
    .S_AXI_HP0_AWREADY         (S0_AXI_HP_HC_AWREADY   ),
    .S_AXI_HP0_AWSIZE          (S0_AXI_HP_HC_AWSIZE    ),
    .S_AXI_HP0_AWVALID         (S0_AXI_HP_HC_AWVALID   ),
    .S_AXI_HP0_BID             (S0_AXI_HP_HC_BID       ),
    .S_AXI_HP0_BREADY          (S0_AXI_HP_HC_BREADY    ),
    .S_AXI_HP0_BRESP           (S0_AXI_HP_HC_BRESP     ),
    .S_AXI_HP0_BVALID          (S0_AXI_HP_HC_BVALID    ),
    .S_AXI_HP0_RDATA           (S0_AXI_HP_HC_RDATA     ),
    .S_AXI_HP0_RID             (S0_AXI_HP_HC_RID       ),
    .S_AXI_HP0_RLAST           (S0_AXI_HP_HC_RLAST     ),
    .S_AXI_HP0_RREADY          (S0_AXI_HP_HC_RREADY    ),
    .S_AXI_HP0_RRESP           (S0_AXI_HP_HC_RRESP     ),
    .S_AXI_HP0_RVALID          (S0_AXI_HP_HC_RVALID    ),
    .S_AXI_HP0_WDATA           (S0_AXI_HP_HC_WDATA     ),
    .S_AXI_HP0_WID             (S0_AXI_HP_HC_WID       ),
    .S_AXI_HP0_WLAST           (S0_AXI_HP_HC_WLAST     ),
    .S_AXI_HP0_WREADY          (S0_AXI_HP_HC_WREADY    ),
    .S_AXI_HP0_WSTRB           (S0_AXI_HP_HC_WSTRB     ),
    .S_AXI_HP0_WVALID          (S0_AXI_HP_HC_WVALID    ),

    .S_AXI_HP0_1_ARADDR        (0                      ),
    .S_AXI_HP0_1_ARBURST       (0                      ),
    .S_AXI_HP0_1_ARCACHE       (0                      ),
    .S_AXI_HP0_1_ARID          (0                      ),
    .S_AXI_HP0_1_ARLEN         (0                      ),
    .S_AXI_HP0_1_ARLOCK        (0                      ),
    .S_AXI_HP0_1_ARPROT        (0                      ),
    .S_AXI_HP0_1_ARQOS         (0                      ),
    .S_AXI_HP0_1_ARREADY       (                       ),
    .S_AXI_HP0_1_ARSIZE        (0                      ),
    .S_AXI_HP0_1_ARVALID       (0                      ),
    .S_AXI_HP0_1_AWADDR        (0                      ),
    .S_AXI_HP0_1_AWBURST       (0                      ),
    .S_AXI_HP0_1_AWCACHE       (0                      ),
    .S_AXI_HP0_1_AWID          (0                      ),
    .S_AXI_HP0_1_AWLEN         (0                      ),
    .S_AXI_HP0_1_AWLOCK        (0                      ),
    .S_AXI_HP0_1_AWPROT        (0                      ),
    .S_AXI_HP0_1_AWQOS         (0                      ),
    .S_AXI_HP0_1_AWREADY       (                       ),
    .S_AXI_HP0_1_AWSIZE        (0                      ),
    .S_AXI_HP0_1_AWVALID       (0                      ),
    .S_AXI_HP0_1_BID           (                       ),
    .S_AXI_HP0_1_BREADY        (0                      ),
    .S_AXI_HP0_1_BRESP         (                       ),
    .S_AXI_HP0_1_BVALID        (                       ),
    .S_AXI_HP0_1_RDATA         (                       ),
    .S_AXI_HP0_1_RID           (                       ),
    .S_AXI_HP0_1_RLAST         (                       ),
    .S_AXI_HP0_1_RREADY        (0                      ),
    .S_AXI_HP0_1_RRESP         (                       ),
    .S_AXI_HP0_1_RVALID        (                       ),
    .S_AXI_HP0_1_WDATA         (0                      ),
    .S_AXI_HP0_1_WID           (0                      ),
    .S_AXI_HP0_1_WLAST         (0                      ),
    .S_AXI_HP0_1_WREADY        (                       ),
    .S_AXI_HP0_1_WSTRB         (0                      ),
    .S_AXI_HP0_1_WVALID        (0                      ),


    .S_AXI_HP0_RACOUNT         (                         ),
    .S_AXI_HP0_RCOUNT          (                         ),
    .S_AXI_HP0_RDISSUECAP1_EN  (S_AXI_HP0_RDISSUECAP1_EN ),
    .S_AXI_HP0_WACOUNT         (                         ),
    .S_AXI_HP0_WCOUNT          (                         ),
    .S_AXI_HP0_WRISSUECAP1_EN  (S_AXI_HP0_WRISSUECAP1_EN ),

    .S_AXI_HP1_ARADDR          (S_AXI_HP1_ARADDR         ),
    .S_AXI_HP1_ARBURST         (S_AXI_HP1_ARBURST        ),
    .S_AXI_HP1_ARCACHE         (S_AXI_HP1_ARCACHE        ),
    .S_AXI_HP1_ARID            (S_AXI_HP1_ARID           ),
    .S_AXI_HP1_ARLEN           (S_AXI_HP1_ARLEN          ),
    .S_AXI_HP1_ARLOCK          (S_AXI_HP1_ARLOCK         ),
    .S_AXI_HP1_ARPROT          (S_AXI_HP1_ARPROT         ),
    .S_AXI_HP1_ARQOS           (S_AXI_HP1_ARQOS          ),
    .S_AXI_HP1_ARREADY         (S_AXI_HP1_ARREADY        ),
    .S_AXI_HP1_ARSIZE          (S_AXI_HP1_ARSIZE         ),
    .S_AXI_HP1_ARVALID         (S_AXI_HP1_ARVALID        ),
    .S_AXI_HP1_AWADDR          (S_AXI_HP1_AWADDR         ),
    .S_AXI_HP1_AWBURST         (S_AXI_HP1_AWBURST        ),
    .S_AXI_HP1_AWCACHE         (S_AXI_HP1_AWCACHE        ),
    .S_AXI_HP1_AWID            (S_AXI_HP1_AWID           ),
    .S_AXI_HP1_AWLEN           (S_AXI_HP1_AWLEN          ),
    .S_AXI_HP1_AWLOCK          (S_AXI_HP1_AWLOCK         ),
    .S_AXI_HP1_AWPROT          (S_AXI_HP1_AWPROT         ),
    .S_AXI_HP1_AWQOS           (S_AXI_HP1_AWQOS          ),
    .S_AXI_HP1_AWREADY         (S_AXI_HP1_AWREADY        ),
    .S_AXI_HP1_AWSIZE          (S_AXI_HP1_AWSIZE         ),
    .S_AXI_HP1_AWVALID         (S_AXI_HP1_AWVALID        ),
    .S_AXI_HP1_BID             (S_AXI_HP1_BID            ),
    .S_AXI_HP1_BREADY          (S_AXI_HP1_BREADY         ),
    .S_AXI_HP1_BRESP           (S_AXI_HP1_BRESP          ),
    .S_AXI_HP1_BVALID          (S_AXI_HP1_BVALID         ),
    .S_AXI_HP1_RDATA           (S_AXI_HP1_RDATA          ),
    .S_AXI_HP1_RID             (S_AXI_HP1_RID            ),
    .S_AXI_HP1_RLAST           (S_AXI_HP1_RLAST          ),
    .S_AXI_HP1_RREADY          (S_AXI_HP1_RREADY         ),
    .S_AXI_HP1_RRESP           (S_AXI_HP1_RRESP          ),
    .S_AXI_HP1_RVALID          (S_AXI_HP1_RVALID         ),
    .S_AXI_HP1_WDATA           (S_AXI_HP1_WDATA          ),
    .S_AXI_HP1_WID             (0                        ),
    .S_AXI_HP1_WLAST           (S_AXI_HP1_WLAST          ),
    .S_AXI_HP1_WREADY          (S_AXI_HP1_WREADY         ),
    .S_AXI_HP1_WSTRB           (S_AXI_HP1_WSTRB          ),
    .S_AXI_HP1_WVALID          (S_AXI_HP1_WVALID         ),  
    .S_AXI_HP1_1_ARADDR        (S1_AXI_HP_HC_ARADDR      ),
    .S_AXI_HP1_1_ARBURST       (S1_AXI_HP_HC_ARBURST     ),
    .S_AXI_HP1_1_ARCACHE       (S1_AXI_HP_HC_ARCACHE     ),
    .S_AXI_HP1_1_ARID          (S1_AXI_HP_HC_ARID        ),
    .S_AXI_HP1_1_ARLEN         (S1_AXI_HP_HC_ARLEN       ),
    .S_AXI_HP1_1_ARLOCK        (S1_AXI_HP_HC_ARLOCK      ),
    .S_AXI_HP1_1_ARPROT        (S1_AXI_HP_HC_ARPROT      ),
    .S_AXI_HP1_1_ARQOS         (S1_AXI_HP_HC_ARQOS       ),
    .S_AXI_HP1_1_ARREADY       (S1_AXI_HP_HC_ARREADY     ),
    .S_AXI_HP1_1_ARSIZE        (S1_AXI_HP_HC_ARSIZE      ),
    .S_AXI_HP1_1_ARVALID       (S1_AXI_HP_HC_ARVALID     ),
    .S_AXI_HP1_1_AWADDR        (S1_AXI_HP_HC_AWADDR      ),
    .S_AXI_HP1_1_AWBURST       (S1_AXI_HP_HC_AWBURST     ),
    .S_AXI_HP1_1_AWCACHE       (S1_AXI_HP_HC_AWCACHE     ),
    .S_AXI_HP1_1_AWID          (S1_AXI_HP_HC_AWID        ),
    .S_AXI_HP1_1_AWLEN         (S1_AXI_HP_HC_AWLEN       ),
    .S_AXI_HP1_1_AWLOCK        (S1_AXI_HP_HC_AWLOCK      ),
    .S_AXI_HP1_1_AWPROT        (S1_AXI_HP_HC_AWPROT      ),
    .S_AXI_HP1_1_AWQOS         (S1_AXI_HP_HC_AWQOS       ),
    .S_AXI_HP1_1_AWREADY       (S1_AXI_HP_HC_AWREADY     ),
    .S_AXI_HP1_1_AWSIZE        (S1_AXI_HP_HC_AWSIZE      ),
    .S_AXI_HP1_1_AWVALID       (S1_AXI_HP_HC_AWVALID     ),
    .S_AXI_HP1_1_BID           (S1_AXI_HP_HC_BID         ),
    .S_AXI_HP1_1_BREADY        (S1_AXI_HP_HC_BREADY      ),
    .S_AXI_HP1_1_BRESP         (S1_AXI_HP_HC_BRESP       ),
    .S_AXI_HP1_1_BVALID        (S1_AXI_HP_HC_BVALID      ),
    .S_AXI_HP1_1_RDATA         (S1_AXI_HP_HC_RDATA       ),
    .S_AXI_HP1_1_RID           (S1_AXI_HP_HC_RID         ),
    .S_AXI_HP1_1_RLAST         (S1_AXI_HP_HC_RLAST       ),
    .S_AXI_HP1_1_RREADY        (S1_AXI_HP_HC_RREADY      ),
    .S_AXI_HP1_1_RRESP         (S1_AXI_HP_HC_RRESP       ),
    .S_AXI_HP1_1_RVALID        (S1_AXI_HP_HC_RVALID      ),
    .S_AXI_HP1_1_WDATA         (S1_AXI_HP_HC_WDATA       ),
    .S_AXI_HP1_1_WID           (S1_AXI_HP_HC_WID         ),
    .S_AXI_HP1_1_WLAST         (S1_AXI_HP_HC_WLAST       ),
    .S_AXI_HP1_1_WREADY        (S1_AXI_HP_HC_WREADY      ),
    .S_AXI_HP1_1_WSTRB         (S1_AXI_HP_HC_WSTRB       ),
    .S_AXI_HP1_1_WVALID        (S1_AXI_HP_HC_WVALID      ),    
    .S_AXI_HP1_RACOUNT         (S_AXI_HP1_RACOUNT        ),
    .S_AXI_HP1_RCOUNT          (S_AXI_HP1_RCOUNT         ),
    .S_AXI_HP1_RDISSUECAP1_EN  (S_AXI_HP1_RDISSUECAP1_EN ),
    .S_AXI_HP1_WACOUNT         (S_AXI_HP1_WACOUNT        ),
    .S_AXI_HP1_WCOUNT          (S_AXI_HP1_WCOUNT         ),
    .S_AXI_HP1_WRISSUECAP1_EN  (S_AXI_HP1_WRISSUECAP1_EN ),    
    
    .S_AXI_HP2_ARADDR          (S_AXI_HP2_ARADDR         ),
    .S_AXI_HP2_ARBURST         (S_AXI_HP2_ARBURST        ),
    .S_AXI_HP2_ARCACHE         (S_AXI_HP2_ARCACHE        ),
    .S_AXI_HP2_ARID            (S_AXI_HP2_ARID           ),
    .S_AXI_HP2_ARLEN           (S_AXI_HP2_ARLEN          ),
    .S_AXI_HP2_ARLOCK          (S_AXI_HP2_ARLOCK         ),
    .S_AXI_HP2_ARPROT          (S_AXI_HP2_ARPROT         ),
    .S_AXI_HP2_ARQOS           (S_AXI_HP2_ARQOS          ),
    .S_AXI_HP2_ARREADY         (S_AXI_HP2_ARREADY        ),
    .S_AXI_HP2_ARSIZE          (S_AXI_HP2_ARSIZE         ),
    .S_AXI_HP2_ARVALID         (S_AXI_HP2_ARVALID        ),
    .S_AXI_HP2_AWADDR          (S_AXI_HP2_AWADDR         ),
    .S_AXI_HP2_AWBURST         (S_AXI_HP2_AWBURST        ),
    .S_AXI_HP2_AWCACHE         (S_AXI_HP2_AWCACHE        ),
    .S_AXI_HP2_AWID            (S_AXI_HP2_AWID           ),
    .S_AXI_HP2_AWLEN           (S_AXI_HP2_AWLEN          ),
    .S_AXI_HP2_AWLOCK          (S_AXI_HP2_AWLOCK         ),
    .S_AXI_HP2_AWPROT          (S_AXI_HP2_AWPROT         ),
    .S_AXI_HP2_AWQOS           (S_AXI_HP2_AWQOS          ),
    .S_AXI_HP2_AWREADY         (S_AXI_HP2_AWREADY        ),
    .S_AXI_HP2_AWSIZE          (S_AXI_HP2_AWSIZE         ),
    .S_AXI_HP2_AWVALID         (S_AXI_HP2_AWVALID        ),
    .S_AXI_HP2_BID             (S_AXI_HP2_BID            ),
    .S_AXI_HP2_BREADY          (S_AXI_HP2_BREADY         ),
    .S_AXI_HP2_BRESP           (S_AXI_HP2_BRESP          ),
    .S_AXI_HP2_BVALID          (S_AXI_HP2_BVALID         ),
    .S_AXI_HP2_RDATA           (S_AXI_HP2_RDATA          ),
    .S_AXI_HP2_RID             (S_AXI_HP2_RID            ),
    .S_AXI_HP2_RLAST           (S_AXI_HP2_RLAST          ),
    .S_AXI_HP2_RREADY          (S_AXI_HP2_RREADY         ),
    .S_AXI_HP2_RRESP           (S_AXI_HP2_RRESP          ),
    .S_AXI_HP2_RVALID          (S_AXI_HP2_RVALID         ),
    .S_AXI_HP2_WDATA           (S_AXI_HP2_WDATA          ),
    .S_AXI_HP2_WID             (S_AXI_HP2_WID            ),
    .S_AXI_HP2_WLAST           (S_AXI_HP2_WLAST          ),
    .S_AXI_HP2_WREADY          (S_AXI_HP2_WREADY         ),
    .S_AXI_HP2_WSTRB           (S_AXI_HP2_WSTRB          ),
    .S_AXI_HP2_WVALID          (S_AXI_HP2_WVALID         ),
    .S_AXI_HP2_1_ARADDR        (S2_AXI_HP_HC_ARADDR      ),
    .S_AXI_HP2_1_ARBURST       (S2_AXI_HP_HC_ARBURST     ),
    .S_AXI_HP2_1_ARCACHE       (S2_AXI_HP_HC_ARCACHE     ),
    .S_AXI_HP2_1_ARID          (S2_AXI_HP_HC_ARID        ),
    .S_AXI_HP2_1_ARLEN         (S2_AXI_HP_HC_ARLEN       ),
    .S_AXI_HP2_1_ARLOCK        (S2_AXI_HP_HC_ARLOCK      ),
    .S_AXI_HP2_1_ARPROT        (S2_AXI_HP_HC_ARPROT      ),
    .S_AXI_HP2_1_ARQOS         (S2_AXI_HP_HC_ARQOS       ),
    .S_AXI_HP2_1_ARREADY       (S2_AXI_HP_HC_ARREADY     ),
    .S_AXI_HP2_1_ARSIZE        (S2_AXI_HP_HC_ARSIZE      ),
    .S_AXI_HP2_1_ARVALID       (S2_AXI_HP_HC_ARVALID     ),
    .S_AXI_HP2_1_AWADDR        (S2_AXI_HP_HC_AWADDR      ),
    .S_AXI_HP2_1_AWBURST       (S2_AXI_HP_HC_AWBURST     ),
    .S_AXI_HP2_1_AWCACHE       (S2_AXI_HP_HC_AWCACHE     ),
    .S_AXI_HP2_1_AWID          (S2_AXI_HP_HC_AWID        ),
    .S_AXI_HP2_1_AWLEN         (S2_AXI_HP_HC_AWLEN       ),
    .S_AXI_HP2_1_AWLOCK        (S2_AXI_HP_HC_AWLOCK      ),
    .S_AXI_HP2_1_AWPROT        (S2_AXI_HP_HC_AWPROT      ),
    .S_AXI_HP2_1_AWQOS         (S2_AXI_HP_HC_AWQOS       ),
    .S_AXI_HP2_1_AWREADY       (S2_AXI_HP_HC_AWREADY     ),
    .S_AXI_HP2_1_AWSIZE        (S2_AXI_HP_HC_AWSIZE      ),
    .S_AXI_HP2_1_AWVALID       (S2_AXI_HP_HC_AWVALID     ),
    .S_AXI_HP2_1_BID           (S2_AXI_HP_HC_BID         ),
    .S_AXI_HP2_1_BREADY        (S2_AXI_HP_HC_BREADY      ),
    .S_AXI_HP2_1_BRESP         (S2_AXI_HP_HC_BRESP       ),
    .S_AXI_HP2_1_BVALID        (S2_AXI_HP_HC_BVALID      ),
    .S_AXI_HP2_1_RDATA         (S2_AXI_HP_HC_RDATA       ),
    .S_AXI_HP2_1_RID           (S2_AXI_HP_HC_RID         ),
    .S_AXI_HP2_1_RLAST         (S2_AXI_HP_HC_RLAST       ),
    .S_AXI_HP2_1_RREADY        (S2_AXI_HP_HC_RREADY      ),
    .S_AXI_HP2_1_RRESP         (S2_AXI_HP_HC_RRESP       ),
    .S_AXI_HP2_1_RVALID        (S2_AXI_HP_HC_RVALID      ),
    .S_AXI_HP2_1_WDATA         (S2_AXI_HP_HC_WDATA       ),
    .S_AXI_HP2_1_WID           (S2_AXI_HP_HC_WID         ),
    .S_AXI_HP2_1_WLAST         (S2_AXI_HP_HC_WLAST       ),
    .S_AXI_HP2_1_WREADY        (S2_AXI_HP_HC_WREADY      ),
    .S_AXI_HP2_1_WSTRB         (S2_AXI_HP_HC_WSTRB       ),
    .S_AXI_HP2_1_WVALID        (S2_AXI_HP_HC_WVALID      ),    
    .S_AXI_HP2_RACOUNT         (S_AXI_HP2_RACOUNT        ),
    .S_AXI_HP2_RCOUNT          (S_AXI_HP2_RCOUNT         ),
    .S_AXI_HP2_RDISSUECAP1_EN  (S_AXI_HP2_RDISSUECAP1_EN ),
    .S_AXI_HP2_WACOUNT         (S_AXI_HP2_WACOUNT        ),
    .S_AXI_HP2_WCOUNT          (S_AXI_HP2_WCOUNT         ),
    .S_AXI_HP2_WRISSUECAP1_EN  (S_AXI_HP2_WRISSUECAP1_EN ),    

    .S_AXI_HP3_ARADDR          (S_AXI_HP3_1_ARADDR       ),
    .S_AXI_HP3_ARBURST         (S_AXI_HP3_1_ARBURST      ),
    .S_AXI_HP3_ARCACHE         (S_AXI_HP3_1_ARCACHE      ),
    .S_AXI_HP3_ARID            (S_AXI_HP3_1_ARID         ),
    .S_AXI_HP3_ARLEN           (S_AXI_HP3_1_ARLEN        ),
    .S_AXI_HP3_ARLOCK          (S_AXI_HP3_1_ARLOCK       ),
    .S_AXI_HP3_ARPROT          (S_AXI_HP3_1_ARPROT       ),
    .S_AXI_HP3_ARQOS           (S_AXI_HP3_1_ARQOS        ),
    .S_AXI_HP3_ARREADY         (S_AXI_HP3_1_ARREADY      ),
    .S_AXI_HP3_ARSIZE          (S_AXI_HP3_1_ARSIZE       ),
    .S_AXI_HP3_ARVALID         (S_AXI_HP3_1_ARVALID      ),
    .S_AXI_HP3_AWADDR          (S_AXI_HP3_1_AWADDR       ),
    .S_AXI_HP3_AWBURST         (S_AXI_HP3_1_AWBURST      ),
    .S_AXI_HP3_AWCACHE         (S_AXI_HP3_1_AWCACHE      ),
    .S_AXI_HP3_AWID            (S_AXI_HP3_1_AWID         ),
    .S_AXI_HP3_AWLEN           (S_AXI_HP3_1_AWLEN        ),
    .S_AXI_HP3_AWLOCK          (S_AXI_HP3_1_AWLOCK       ),
    .S_AXI_HP3_AWPROT          (S_AXI_HP3_1_AWPROT       ),
    .S_AXI_HP3_AWQOS           (S_AXI_HP3_1_AWQOS        ),
    .S_AXI_HP3_AWREADY         (S_AXI_HP3_1_AWREADY      ),
    .S_AXI_HP3_AWSIZE          (S_AXI_HP3_1_AWSIZE       ),
    .S_AXI_HP3_AWVALID         (S_AXI_HP3_1_AWVALID      ),
    .S_AXI_HP3_BID             (S_AXI_HP3_1_BID          ),
    .S_AXI_HP3_BREADY          (S_AXI_HP3_1_BREADY       ),
    .S_AXI_HP3_BRESP           (S_AXI_HP3_1_BRESP        ),
    .S_AXI_HP3_BVALID          (S_AXI_HP3_1_BVALID       ),
    .S_AXI_HP3_RDATA           (S_AXI_HP3_1_RDATA        ),
    .S_AXI_HP3_RID             (S_AXI_HP3_1_RID          ),
    .S_AXI_HP3_RLAST           (S_AXI_HP3_1_RLAST        ),
    .S_AXI_HP3_RREADY          (S_AXI_HP3_1_RREADY       ),
    .S_AXI_HP3_RRESP           (S_AXI_HP3_1_RRESP        ),
    .S_AXI_HP3_RVALID          (S_AXI_HP3_1_RVALID       ),
    .S_AXI_HP3_WDATA           (S_AXI_HP3_1_WDATA        ),
    .S_AXI_HP3_WID             (S_AXI_HP3_1_WID          ),
    .S_AXI_HP3_WLAST           (S_AXI_HP3_1_WLAST        ),
    .S_AXI_HP3_WREADY          (S_AXI_HP3_1_WREADY       ),
    .S_AXI_HP3_WSTRB           (S_AXI_HP3_1_WSTRB        ),
    .S_AXI_HP3_WVALID          (S_AXI_HP3_1_WVALID       ),
    .S_AXI_HP3_1_ARADDR        (S3_AXI_HP_HC_ARADDR      ),
    .S_AXI_HP3_1_ARBURST       (S3_AXI_HP_HC_ARBURST     ),
    .S_AXI_HP3_1_ARCACHE       (S3_AXI_HP_HC_ARCACHE     ),
    .S_AXI_HP3_1_ARID          (S3_AXI_HP_HC_ARID        ),
    .S_AXI_HP3_1_ARLEN         (S3_AXI_HP_HC_ARLEN       ),
    .S_AXI_HP3_1_ARLOCK        (S3_AXI_HP_HC_ARLOCK      ),
    .S_AXI_HP3_1_ARPROT        (S3_AXI_HP_HC_ARPROT      ),
    .S_AXI_HP3_1_ARQOS         (S3_AXI_HP_HC_ARQOS       ),
    .S_AXI_HP3_1_ARREADY       (S3_AXI_HP_HC_ARREADY     ),
    .S_AXI_HP3_1_ARSIZE        (S3_AXI_HP_HC_ARSIZE      ),
    .S_AXI_HP3_1_ARVALID       (S3_AXI_HP_HC_ARVALID     ),
    .S_AXI_HP3_1_AWADDR        (S3_AXI_HP_HC_AWADDR      ),
    .S_AXI_HP3_1_AWBURST       (S3_AXI_HP_HC_AWBURST     ),
    .S_AXI_HP3_1_AWCACHE       (S3_AXI_HP_HC_AWCACHE     ),
    .S_AXI_HP3_1_AWID          (S3_AXI_HP_HC_AWID        ),
    .S_AXI_HP3_1_AWLEN         (S3_AXI_HP_HC_AWLEN       ),
    .S_AXI_HP3_1_AWLOCK        (S3_AXI_HP_HC_AWLOCK      ),
    .S_AXI_HP3_1_AWPROT        (S3_AXI_HP_HC_AWPROT      ),
    .S_AXI_HP3_1_AWQOS         (S3_AXI_HP_HC_AWQOS       ),
    .S_AXI_HP3_1_AWREADY       (S3_AXI_HP_HC_AWREADY     ),
    .S_AXI_HP3_1_AWSIZE        (S3_AXI_HP_HC_AWSIZE      ),
    .S_AXI_HP3_1_AWVALID       (S3_AXI_HP_HC_AWVALID     ),
    .S_AXI_HP3_1_BID           (S3_AXI_HP_HC_BID         ),
    .S_AXI_HP3_1_BREADY        (S3_AXI_HP_HC_BREADY      ),
    .S_AXI_HP3_1_BRESP         (S3_AXI_HP_HC_BRESP       ),
    .S_AXI_HP3_1_BVALID        (S3_AXI_HP_HC_BVALID      ),
    .S_AXI_HP3_1_RDATA         (S3_AXI_HP_HC_RDATA       ),
    .S_AXI_HP3_1_RID           (S3_AXI_HP_HC_RID         ),
    .S_AXI_HP3_1_RLAST         (S3_AXI_HP_HC_RLAST       ),
    .S_AXI_HP3_1_RREADY        (S3_AXI_HP_HC_RREADY      ),
    .S_AXI_HP3_1_RRESP         (S3_AXI_HP_HC_RRESP       ),
    .S_AXI_HP3_1_RVALID        (S3_AXI_HP_HC_RVALID      ),
    .S_AXI_HP3_1_WDATA         (S3_AXI_HP_HC_WDATA       ),
    .S_AXI_HP3_1_WID           (S3_AXI_HP_HC_WID         ),
    .S_AXI_HP3_1_WLAST         (S3_AXI_HP_HC_WLAST       ),
    .S_AXI_HP3_1_WREADY        (S3_AXI_HP_HC_WREADY      ),
    .S_AXI_HP3_1_WSTRB         (S3_AXI_HP_HC_WSTRB       ),
    .S_AXI_HP3_1_WVALID        (S3_AXI_HP_HC_WVALID      ),      
    .S_AXI_HP3_RACOUNT         (S_AXI_HP3_RACOUNT        ),
    .S_AXI_HP3_RCOUNT          (S_AXI_HP3_RCOUNT         ),
    .S_AXI_HP3_RDISSUECAP1_EN  (S_AXI_HP3_RDISSUECAP1_EN ),
    .S_AXI_HP3_WACOUNT         (S_AXI_HP3_WACOUNT        ),
    .S_AXI_HP3_WCOUNT          (S_AXI_HP3_WCOUNT         ),
    .S_AXI_HP3_WRISSUECAP1_EN  (S_AXI_HP3_WRISSUECAP1_EN ),    

    .pl_araddr                 (pl_araddr                ),
    .pl_arinfo                 (pl_arinfo                ),
    .pl_arlast                 (pl_arlast                ),
    .pl_arready                (pl_arready               ),
    .pl_arvalid                (pl_arvalid               ),
    .pl_awaddr                 (pl_awaddr                ),
    .pl_awdata                 (pl_awdata                ),
    .pl_awen                   (pl_awen                  ),
    .pl_awinfo                 (pl_awinfo                ),
    .pl_awlast                 (pl_awlast                ),
    .pl_awready                (pl_awready               ),
    .pl_awvalid                (pl_awvalid               ),
    .pl_bvalid                 (pl_bvalid                ),  
    .pl_bready                 (pl_bready                ),  
    .pl_bist_clk               (pl_bist_clk              ),
    .pl_bist_rstn              (pl_bist_rstn             ),
    .pl_bist_en                (pl_bist_en               ),      
    .pl_bist_done              (pl_bist_done             ),
    .pl_bist_err               (pl_bist_err              ),
    .pl_bist_err_inv           (pl_bist_err_inv          ),
    .pl_clk_div_out            (pl_clk_div_out           ),
    .pl_clk_en_b               (pl_clk_en_b              ),
    .pl_int_info               (pl_int_info              ),   
    .pl_int_valid              (pl_int_valid             ), 
    .pl_int_ready              (pl_int_ready             ),      
    .pl_itf_clk                (pl_itf_clk               ),
    .pl_ra_araddr              (pl_ra_araddr             ),
    .pl_ra_arready             (pl_ra_arready            ),
    .pl_ra_arvalid             (pl_ra_arvalid            ),
    .pl_ra_awaddr              (pl_ra_awaddr             ),
    .pl_ra_awdata              (pl_ra_awdata             ),
    .pl_ra_awready             (pl_ra_awready            ),
    .pl_ra_awvalid             (pl_ra_awvalid            ),
    .pl_ra_clk                 (pl_ra_clk                ),
    .pl_ra_rdata               (pl_ra_rdata              ),
    .pl_ra_rready              (pl_ra_rready             ),
    .pl_ra_rvalid              (pl_ra_rvalid             ),
    .pl_rdata                  (pl_rdata                 ),
    .pl_repair_done            (pl_repair_done           ),
    .pl_repair_fail            (pl_repair_fail           ),
    .pl_rlast                  (pl_rlast                 ),
    .pl_rready                 (pl_rready                ),
    .pl_rst_n                  (pl_rst_n                 ), 
    .pl_rvalid                 (pl_rvalid                ),
    .pl_scan_clk               (pl_scan_clk              ),
    .pl_scan_en                (pl_scan_en               ),
    .pl_scan_i                 (pl_scan_i[63:0]          ),
    .pl_scan_mode_b            (pl_scan_mode_b           ),
    .pl_scan_o                 (pl_scan_o                ),
    .pl_scan_rst_n             (pl_scan_rst_n            ),
  
    .test_irq                  (test_irq                 ),
    .customop_irq              (customop_irq             ),
    .ai_irq                    (ai_irq                   ),
    .clk_200mhz                (clk_200mhz               ),
    
    .gp0_ar_cnt                (gp0_ar_cnt               ),
    .gp0_r_cnt                 (gp0_r_cnt                ),
    .gp0_aw_cnt                (gp0_aw_cnt               ),   
    .gp0_w_cnt                 (gp0_w_cnt                ),
    .gp0_b_cnt                 (gp0_b_cnt                ),

    .gp1_ar_cnt                (gp1_ar_cnt               ),
    .gp1_r_cnt                 (gp1_r_cnt                ),
    .gp1_aw_cnt                (gp1_aw_cnt               ),
    .gp1_w_cnt                 (gp1_w_cnt                ),  
    .gp1_b_cnt                 (gp1_b_cnt                )              
    );

video_direct_source_select #(
  .DATA_WIDTH             (24),
  .SDI_KEEP_EVERY_N       (1),
  .FRAME_WIDTH            (DIRECT_FRAME_WIDTH),
  .FRAME_HEIGHT           (DIRECT_FRAME_HEIGHT),
  .COLORBAR_PERIOD_CYCLES (DIRECT_FRAME_WIDTH*DIRECT_FRAME_HEIGHT),
  .FIFO_DEPTH             (2048)
) u_video_direct_source_select (
  .clk          (ddr_clk              ),
  .rst          (direct_video_rst     ),
  .mode         (video_mode           ),
  .sdi_tdata    (mipi_axis_tdata      ),
  .sdi_tvalid   (mipi_axis_tvalid     ),
  .sdi_tready   (direct_mipi_tready   ),
  .sdi_tuser    (mipi_axis_tuser      ),
  .m_axis_tdata (direct_video_tdata   ),
  .m_axis_tvalid(direct_video_tvalid  ),
  .m_axis_tready(direct_video_tready  ),
  .m_axis_tuser (direct_video_tuser   ),
  .m_axis_tlast (direct_video_tlast   ),
  .fifo_overflow(direct_video_fifo_overflow)
);

video_pingpong_ctrl u_direct_video_pingpong_ctrl (
  .clk                     (ddr_clk                         ),
  .rst                     (direct_video_rst                ),
  .enable                  (direct_ddr_active & ddr3_init_done),
  .base0_byte_addr         (direct_ddr_base0_byte_addr      ),
  .base1_byte_addr         (direct_ddr_base1_byte_addr      ),
  .writer_frame_start_pulse(direct_writer_frame_start_pulse ),
  .writer_frame_done_pulse (direct_writer_frame_done_pulse  ),
  .reader_frame_done_pulse (direct_reader_frame_done_pulse  ),
  .reader_frame_active     (direct_reader_frame_active      ),
  .writer_base_byte_addr   (direct_wr_base_byte_addr        ),
  .reader_base_byte_addr   (direct_rd_base_byte_addr        ),
  .reader_start            (direct_reader_start             ),
  .writer_buf_index        (direct_pp_writer_buf_index      ),
  .reader_buf_index        (direct_pp_reader_buf_index      ),
  .latest_buf_index        (direct_pp_latest_buf_index      ),
  .latest_frame_valid      (direct_pp_latest_frame_valid    ),
  .reader_frame_valid      (direct_pp_reader_frame_valid    )
);

axis_to_mig_video_writer #(
  .FRAME_WIDTH            (DIRECT_FRAME_WIDTH),
  .FRAME_HEIGHT           (DIRECT_FRAME_HEIGHT),
  .APP_DATA_WIDTH         (DIRECT_APP_DATA_WIDTH),
  .APP_DATA_BYTES         (DIRECT_APP_DATA_BYTES)
) u_axis_to_mig_video_writer (
  .clk                   (ddr_clk                         ),
  .rst                   (direct_video_rst                ),
  .enable                (direct_ddr_active & ddr3_init_done),
  .base_byte_addr        (direct_wr_base_byte_addr        ),
  .s_axis_tdata          (direct_video_tdata              ),
  .s_axis_tvalid         (direct_video_tvalid             ),
  .s_axis_tready         (direct_video_tready             ),
  .s_axis_tuser          (direct_video_tuser              ),
  .app_addr              (direct_wr_app_addr              ),
  .app_cmd               (direct_wr_app_cmd               ),
  .app_en                (direct_wr_app_en                ),
  .app_wdf_data          (direct_wr_app_wdf_data          ),
  .app_wdf_end           (direct_wr_app_wdf_end           ),
  .app_wdf_mask          (direct_wr_app_wdf_mask          ),
  .app_wdf_wren          (direct_wr_app_wdf_wren          ),
  .app_rdy               (app_rdy                         ),
  .app_wdf_rdy           (app_wdf_rdy                     ),
  .app_write_pending     (direct_wr_app_pending           ),
  .frame_active          (direct_writer_frame_active      ),
  .frame_done_pulse      (direct_writer_frame_done_pulse  )
);

mig_to_axis_video_reader #(
  .FRAME_WIDTH            (DIRECT_FRAME_WIDTH),
  .FRAME_HEIGHT           (DIRECT_FRAME_HEIGHT),
  .APP_DATA_WIDTH         (DIRECT_APP_DATA_WIDTH),
  .APP_DATA_BYTES         (DIRECT_APP_DATA_BYTES)
) u_mig_to_axis_video_reader (
  .clk                   (ddr_clk                         ),
  .rst                   (direct_video_rst                ),
  .enable                (direct_ddr_active & ddr3_init_done),
  .start                 (direct_reader_start             ),
  .base_byte_addr        (direct_rd_base_byte_addr        ),
  .app_addr              (direct_rd_app_addr              ),
  .app_cmd               (direct_rd_app_cmd               ),
  .app_en                (direct_rd_app_en                ),
  .app_wdf_data          (direct_rd_app_wdf_data          ),
  .app_wdf_end           (direct_rd_app_wdf_end           ),
  .app_wdf_mask          (direct_rd_app_wdf_mask          ),
  .app_wdf_wren          (direct_rd_app_wdf_wren          ),
  .app_rd_data           (app_rd_data                     ),
  .app_rd_data_valid     (app_rd_data_valid               ),
  .app_rdy               (app_rdy & (~direct_wr_app_pending)),
  .app_read_pending      (direct_rd_app_pending           ),
  .m_axis_tdata          (eth_ddr_axis_tdata              ),
  .m_axis_tvalid         (eth_ddr_axis_tvalid             ),
  .m_axis_tready         (eth_ddr_axis_tready             ),
  .m_axis_tlast          (eth_ddr_axis_tlast              ),
  .m_axis_tuser          (eth_ddr_axis_tuser              ),
  .frame_active          (direct_reader_frame_active      ),
  .frame_done_pulse      (direct_reader_frame_done_pulse  )
);

pl_eth_colorbar_top #(
  .FRAME_WIDTH        (DIRECT_FRAME_WIDTH),
  .FRAME_HEIGHT       (DIRECT_FRAME_HEIGHT),
  .PIXELS_PER_PACKET  (DIRECT_PIXELS_PER_PACKET)
) u_pl_eth_colorbar_top (
  .ref_clk_200mhz (ddr_clk                            ),
  .rst            (core_rst | ddr_ui_rst              ),
  .pl_phy_txc     (pl_phy_txc                         ),
  .pl_phy_tx_ctl  (pl_phy_tx_ctl                      ),
  .pl_phy_txd     (pl_phy_txd                         ),
  .pl_phy_rxc     (pl_phy_rxc                         ),
  .pl_phy_rx_ctl  (pl_phy_rx_ctl                      ),
  .pl_phy_rxd     (pl_phy_rxd                         ),
  .pl_phy_mdc     (pl_phy_mdc                         ),
  .pl_phy_mdio    (pl_phy_mdio                        ),
  .pl_phy_reset_n (pl_phy_reset_n                     ),
  .tx_video_select(eth_video_select                   ),
  .s_video_axis_aclk(ddr_clk                          ),
  .s_video_axis_aresetn(~direct_video_rst             ),
  .s_video_axis_tdata(eth_ddr_axis_tdata              ),
  .s_video_axis_tvalid(eth_ddr_axis_tvalid            ),
  .s_video_axis_tready(eth_ddr_axis_tready            ),
  .s_video_axis_tlast(eth_ddr_axis_tlast              ),
  .s_video_axis_tuser(eth_ddr_axis_tuser              ),
  .spare_axis_tdata(eth_spare_axis_tdata              ),
  .spare_axis_tvalid(eth_spare_axis_tvalid            ),
  .spare_axis_tready(eth_spare_axis_tready            ),
  .spare_axis_tlast(eth_spare_axis_tlast              ),
  .spare_axis_tuser(eth_spare_axis_tuser              ),
  .led            (                                  ),
  .eth_clk_out    (                                  ),
  .eth_clk_locked (                                  )
);
AI_Mate_0 ZGolo(
  .hp_clk                   (ddr_clk                  ),
  .ui_clk                   (ddr_clk                  ),
  .reg_clk                  (gp_clk                   ),
  .sys_rst_n                (sys_rst_n & (~soft_rst)  & FCLK_RESET0_N & (video_mode == 2'd2)),
  .img_ready_0              (aimate_img_ready         ),
  .img_data_0               ({40'b0,img_data1}        ),
  .img_valid_0              ((video_mode == 2'd2) ? img_valid1 : 1'b0),
  .img_start_0              ((video_mode == 2'd2) ? img_start1 : 1'b0),
 
  .app_addr                 (aimate_app_addr          ),
  .app_cmd                  (aimate_app_cmd           ),
  .app_en                   (aimate_app_en            ),
  .app_wdf_data             (aimate_app_wdf_data      ),
  .app_wdf_end              (aimate_app_wdf_end       ),
  .app_wdf_mask             (aimate_app_wdf_mask      ),
  .app_wdf_wren             (aimate_app_wdf_wren      ),
  .app_rd_data              (app_rd_data              ),
  .app_rd_data_end          (app_rd_data_end          ),
  .app_rd_data_valid        (app_rd_data_valid        ),
  .app_rdy                  (app_rdy                  ),
  .app_wdf_rdy              (app_wdf_rdy              ),
  .ddr3_init_done           (ddr3_init_done           ),
  .M_AXI_GP0_ARVALID        (BYolo_GP0_ARVALID        ),
  .M_AXI_GP0_AWVALID        (BYolo_GP0_AWVALID        ),
  .M_AXI_GP0_BREADY         (BYolo_GP0_BREADY         ),
  .M_AXI_GP0_RREADY         (BYolo_GP0_RREADY         ),
  .M_AXI_GP0_WLAST          (BYolo_GP0_WLAST          ),
  .M_AXI_GP0_WVALID         (BYolo_GP0_WVALID         ),
  .M_AXI_GP0_ARID           (BYolo_GP0_ARID           ),
  .M_AXI_GP0_AWID           (BYolo_GP0_AWID           ),
  .M_AXI_GP0_WID            (BYolo_GP0_WID            ),
  .M_AXI_GP0_ARBURST        (BYolo_GP0_ARBURST        ),
  .M_AXI_GP0_ARLOCK         (BYolo_GP0_ARLOCK         ),
  .M_AXI_GP0_ARSIZE         (BYolo_GP0_ARSIZE         ),
  .M_AXI_GP0_AWBURST        (BYolo_GP0_AWBURST        ),
  .M_AXI_GP0_AWLOCK         (BYolo_GP0_AWLOCK         ),
  .M_AXI_GP0_AWSIZE         (BYolo_GP0_AWSIZE         ),
  .M_AXI_GP0_ARPROT         (BYolo_GP0_ARPROT         ),
  .M_AXI_GP0_AWPROT         (BYolo_GP0_AWPROT         ),
  .M_AXI_GP0_ARADDR         (BYolo_GP0_ARADDR         ),
  .M_AXI_GP0_AWADDR         (BYolo_GP0_AWADDR         ),
  .M_AXI_GP0_WDATA          (BYolo_GP0_WDATA          ),
  .M_AXI_GP0_ARCACHE        (BYolo_GP0_ARCACHE        ),
  .M_AXI_GP0_ARLEN          (BYolo_GP0_ARLEN          ),
  .M_AXI_GP0_ARQOS          (BYolo_GP0_ARQOS          ),
  .M_AXI_GP0_AWCACHE        (BYolo_GP0_AWCACHE        ),
  .M_AXI_GP0_AWLEN          (BYolo_GP0_AWLEN          ),
  .M_AXI_GP0_AWQOS          (BYolo_GP0_AWQOS          ),
  .M_AXI_GP0_WSTRB          (BYolo_GP0_WSTRB          ),
  .M_AXI_GP0_ARREADY        (BYolo_GP0_ARREADY        ),
  .M_AXI_GP0_AWREADY        (BYolo_GP0_AWREADY        ),
  .M_AXI_GP0_BVALID         (BYolo_GP0_BVALID         ),
  .M_AXI_GP0_RLAST          (BYolo_GP0_RLAST          ),
  .M_AXI_GP0_RVALID         (BYolo_GP0_RVALID         ),
  .M_AXI_GP0_WREADY         (BYolo_GP0_WREADY         ),
  .M_AXI_GP0_BID            (BYolo_GP0_BID            ),
  .M_AXI_GP0_RID            (BYolo_GP0_RID            ),
  .M_AXI_GP0_BRESP          (BYolo_GP0_BRESP          ),
  .M_AXI_GP0_RRESP          (BYolo_GP0_RRESP          ),
  .M_AXI_GP0_RDATA          (BYolo_GP0_RDATA          ),
  
  .M_AXI_GP1_ARVALID        (BYolo_GP1_ARVALID        ),
  .M_AXI_GP1_AWVALID        (BYolo_GP1_AWVALID        ),
  .M_AXI_GP1_BREADY         (BYolo_GP1_BREADY         ),
  .M_AXI_GP1_RREADY         (BYolo_GP1_RREADY         ),
  .M_AXI_GP1_WLAST          (BYolo_GP1_WLAST          ),
  .M_AXI_GP1_WVALID         (BYolo_GP1_WVALID         ),
  .M_AXI_GP1_ARID           (BYolo_GP1_ARID           ),
  .M_AXI_GP1_AWID           (BYolo_GP1_AWID           ),
  .M_AXI_GP1_WID            (BYolo_GP1_WID            ),
  .M_AXI_GP1_ARBURST        (BYolo_GP1_ARBURST        ),
  .M_AXI_GP1_ARLOCK         (BYolo_GP1_ARLOCK         ),
  .M_AXI_GP1_ARSIZE         (BYolo_GP1_ARSIZE         ),
  .M_AXI_GP1_AWBURST        (BYolo_GP1_AWBURST        ),
  .M_AXI_GP1_AWLOCK         (BYolo_GP1_AWLOCK         ),
  .M_AXI_GP1_AWSIZE         (BYolo_GP1_AWSIZE         ),
  .M_AXI_GP1_ARPROT         (BYolo_GP1_ARPROT         ),
  .M_AXI_GP1_AWPROT         (BYolo_GP1_AWPROT         ),
  .M_AXI_GP1_ARADDR         (BYolo_GP1_ARADDR         ),
  .M_AXI_GP1_AWADDR         (BYolo_GP1_AWADDR         ),
  .M_AXI_GP1_WDATA          (BYolo_GP1_WDATA          ),
  .M_AXI_GP1_ARCACHE        (BYolo_GP1_ARCACHE        ),
  .M_AXI_GP1_ARLEN          (BYolo_GP1_ARLEN          ),
  .M_AXI_GP1_ARQOS          (BYolo_GP1_ARQOS          ),
  .M_AXI_GP1_AWCACHE        (BYolo_GP1_AWCACHE        ),
  .M_AXI_GP1_AWLEN          (BYolo_GP1_AWLEN          ),
  .M_AXI_GP1_AWQOS          (BYolo_GP1_AWQOS          ),
  .M_AXI_GP1_WSTRB          (BYolo_GP1_WSTRB          ),
  .M_AXI_GP1_ARREADY        (BYolo_GP1_ARREADY        ),
  .M_AXI_GP1_AWREADY        (BYolo_GP1_AWREADY        ),
  .M_AXI_GP1_BVALID         (BYolo_GP1_BVALID         ),
  .M_AXI_GP1_RLAST          (BYolo_GP1_RLAST          ),
  .M_AXI_GP1_RVALID         (BYolo_GP1_RVALID         ),
  .M_AXI_GP1_WREADY         (BYolo_GP1_WREADY         ),
  .M_AXI_GP1_BID            (BYolo_GP1_BID            ),
  .M_AXI_GP1_RID            (BYolo_GP1_RID            ),
  .M_AXI_GP1_BRESP          (BYolo_GP1_BRESP          ),
  .M_AXI_GP1_RRESP          (BYolo_GP1_RRESP          ),
  .M_AXI_GP1_RDATA          (BYolo_GP1_RDATA          ),

  .S_AXI_HP0_ARREADY        (S_AXI_HP1_ARREADY        ),
  .S_AXI_HP0_AWREADY        (S_AXI_HP1_AWREADY        ),
  .S_AXI_HP0_BVALID         (S_AXI_HP1_BVALID         ),
  .S_AXI_HP0_RLAST          (S_AXI_HP1_RLAST          ),
  .S_AXI_HP0_RVALID         (S_AXI_HP1_RVALID         ),
  .S_AXI_HP0_WREADY         (S_AXI_HP1_WREADY         ),
  .S_AXI_HP0_BRESP          (S_AXI_HP1_BRESP          ),
  .S_AXI_HP0_RRESP          (S_AXI_HP1_RRESP          ),
  .S_AXI_HP0_BID            (S_AXI_HP1_BID            ),
  .S_AXI_HP0_RID            (S_AXI_HP1_RID            ),
  .S_AXI_HP0_RDATA          (S_AXI_HP1_RDATA          ),
  .S_AXI_HP0_ARVALID        (S_AXI_HP1_ARVALID        ),
  .S_AXI_HP0_AWVALID        (S_AXI_HP1_AWVALID        ),
  .S_AXI_HP0_BREADY         (S_AXI_HP1_BREADY         ),
  .S_AXI_HP0_RREADY         (S_AXI_HP1_RREADY         ),
  .S_AXI_HP0_WLAST          (S_AXI_HP1_WLAST          ),
  .S_AXI_HP0_WVALID         (S_AXI_HP1_WVALID         ),
  .S_AXI_HP0_ARBURST        (S_AXI_HP1_ARBURST        ),
  .S_AXI_HP0_ARLOCK         (S_AXI_HP1_ARLOCK         ),
  .S_AXI_HP0_ARSIZE         (S_AXI_HP1_ARSIZE         ),
  .S_AXI_HP0_AWBURST        (S_AXI_HP1_AWBURST        ),
  .S_AXI_HP0_AWLOCK         (S_AXI_HP1_AWLOCK         ),
  .S_AXI_HP0_AWSIZE         (S_AXI_HP1_AWSIZE         ),
  .S_AXI_HP0_ARPROT         (S_AXI_HP1_ARPROT         ),
  .S_AXI_HP0_AWPROT         (S_AXI_HP1_AWPROT         ),
  .S_AXI_HP0_ARADDR         (S_AXI_HP1_ARADDR         ),
  .S_AXI_HP0_AWADDR         (S_AXI_HP1_AWADDR         ),
  .S_AXI_HP0_ARCACHE        (S_AXI_HP1_ARCACHE        ),
  .S_AXI_HP0_ARLEN          (S_AXI_HP1_ARLEN          ),
  .S_AXI_HP0_ARQOS          (S_AXI_HP1_ARQOS          ),
  .S_AXI_HP0_AWCACHE        (S_AXI_HP1_AWCACHE        ),
  .S_AXI_HP0_AWLEN          (S_AXI_HP1_AWLEN          ),
  .S_AXI_HP0_AWQOS          (S_AXI_HP1_AWQOS          ),
  .S_AXI_HP0_ARID           (S_AXI_HP1_ARID           ),
  .S_AXI_HP0_AWID           (S_AXI_HP1_AWID           ),
  .S_AXI_HP0_WID            (S_AXI_HP1_WID            ),
  .S_AXI_HP0_WDATA          (S_AXI_HP1_WDATA          ),
  .S_AXI_HP0_WSTRB          (S_AXI_HP1_WSTRB          ),
  .S_AXI_HP1_ARREADY        (S_AXI_HP3_1_ARREADY        ),
  .S_AXI_HP1_AWREADY        (S_AXI_HP3_1_AWREADY        ),
  .S_AXI_HP1_BVALID         (S_AXI_HP3_1_BVALID         ),
  .S_AXI_HP1_RLAST          (S_AXI_HP3_1_RLAST          ),
  .S_AXI_HP1_RVALID         (S_AXI_HP3_1_RVALID         ),
  .S_AXI_HP1_WREADY         (S_AXI_HP3_1_WREADY         ),
  .S_AXI_HP1_BRESP          (S_AXI_HP3_1_BRESP          ),
  .S_AXI_HP1_RRESP          (S_AXI_HP3_1_RRESP          ),
  .S_AXI_HP1_BID            (S_AXI_HP3_1_BID            ),
  .S_AXI_HP1_RID            (S_AXI_HP3_1_RID            ),
  .S_AXI_HP1_RDATA          (S_AXI_HP3_1_RDATA          ),

  .S_AXI_HP1_ARVALID        (S_AXI_HP3_1_ARVALID        ),
  .S_AXI_HP1_AWVALID        (S_AXI_HP3_1_AWVALID        ),
  .S_AXI_HP1_BREADY         (S_AXI_HP3_1_BREADY         ),
  .S_AXI_HP1_RREADY         (S_AXI_HP3_1_RREADY         ),
  .S_AXI_HP1_WLAST          (S_AXI_HP3_1_WLAST          ),
  .S_AXI_HP1_WVALID         (S_AXI_HP3_1_WVALID         ),
  .S_AXI_HP1_ARBURST        (S_AXI_HP3_1_ARBURST        ),
  .S_AXI_HP1_ARLOCK         (S_AXI_HP3_1_ARLOCK         ),
  .S_AXI_HP1_ARSIZE         (S_AXI_HP3_1_ARSIZE         ),
  .S_AXI_HP1_AWBURST        (S_AXI_HP3_1_AWBURST        ),
  .S_AXI_HP1_AWLOCK         (S_AXI_HP3_1_AWLOCK         ),
  .S_AXI_HP1_AWSIZE         (S_AXI_HP3_1_AWSIZE         ),
  .S_AXI_HP1_ARPROT         (S_AXI_HP3_1_ARPROT         ),
  .S_AXI_HP1_AWPROT         (S_AXI_HP3_1_AWPROT         ),
  .S_AXI_HP1_ARADDR         (S_AXI_HP3_1_ARADDR         ),
  .S_AXI_HP1_AWADDR         (S_AXI_HP3_1_AWADDR         ),
  .S_AXI_HP1_ARCACHE        (S_AXI_HP3_1_ARCACHE        ),
  .S_AXI_HP1_ARLEN          (S_AXI_HP3_1_ARLEN          ),
  .S_AXI_HP1_ARQOS          (S_AXI_HP3_1_ARQOS          ),
  .S_AXI_HP1_AWCACHE        (S_AXI_HP3_1_AWCACHE        ),
  .S_AXI_HP1_AWLEN          (S_AXI_HP3_1_AWLEN          ),
  .S_AXI_HP1_AWQOS          (S_AXI_HP3_1_AWQOS          ),
  .S_AXI_HP1_ARID           (S_AXI_HP3_1_ARID           ),
  .S_AXI_HP1_AWID           (S_AXI_HP3_1_AWID           ),
  .S_AXI_HP1_WID            (S_AXI_HP3_1_WID            ),
  .S_AXI_HP1_WDATA          (S_AXI_HP3_1_WDATA          ),
  .S_AXI_HP1_WSTRB          (S_AXI_HP3_1_WSTRB          ),


  .S0_AXI_HP_HC_ARREADY     (S0_AXI_HP_HC_ARREADY     ),
  .S0_AXI_HP_HC_AWREADY     (S0_AXI_HP_HC_AWREADY     ),
  .S0_AXI_HP_HC_BVALID      (S0_AXI_HP_HC_BVALID      ),
  .S0_AXI_HP_HC_RLAST       (S0_AXI_HP_HC_RLAST       ),
  .S0_AXI_HP_HC_RVALID      (S0_AXI_HP_HC_RVALID      ),
  .S0_AXI_HP_HC_WREADY      (S0_AXI_HP_HC_WREADY      ),
  .S0_AXI_HP_HC_BRESP       (S0_AXI_HP_HC_BRESP       ),
  .S0_AXI_HP_HC_RRESP       (S0_AXI_HP_HC_RRESP       ),
  .S0_AXI_HP_HC_BID         (S0_AXI_HP_HC_BID         ),
  .S0_AXI_HP_HC_RID         (S0_AXI_HP_HC_RID         ),
  .S0_AXI_HP_HC_RDATA       (S0_AXI_HP_HC_RDATA       ),
  .S0_AXI_HP_HC_ARVALID     (S0_AXI_HP_HC_ARVALID     ),
  .S0_AXI_HP_HC_AWVALID     (S0_AXI_HP_HC_AWVALID     ),
  .S0_AXI_HP_HC_BREADY      (S0_AXI_HP_HC_BREADY      ),
  .S0_AXI_HP_HC_RREADY      (S0_AXI_HP_HC_RREADY      ),
  .S0_AXI_HP_HC_WLAST       (S0_AXI_HP_HC_WLAST       ),
  .S0_AXI_HP_HC_WVALID      (S0_AXI_HP_HC_WVALID      ),
  .S0_AXI_HP_HC_ARBURST     (S0_AXI_HP_HC_ARBURST     ),
  .S0_AXI_HP_HC_ARLOCK      (S0_AXI_HP_HC_ARLOCK      ),
  .S0_AXI_HP_HC_ARSIZE      (S0_AXI_HP_HC_ARSIZE      ),
  .S0_AXI_HP_HC_AWBURST     (S0_AXI_HP_HC_AWBURST     ),
  .S0_AXI_HP_HC_AWLOCK      (S0_AXI_HP_HC_AWLOCK      ),
  .S0_AXI_HP_HC_AWSIZE      (S0_AXI_HP_HC_AWSIZE      ),
  .S0_AXI_HP_HC_ARPROT      (S0_AXI_HP_HC_ARPROT      ),
  .S0_AXI_HP_HC_AWPROT      (S0_AXI_HP_HC_AWPROT      ),
  .S0_AXI_HP_HC_ARADDR      (S0_AXI_HP_HC_ARADDR      ),
  .S0_AXI_HP_HC_AWADDR      (S0_AXI_HP_HC_AWADDR      ),
  .S0_AXI_HP_HC_ARCACHE     (S0_AXI_HP_HC_ARCACHE     ),
  .S0_AXI_HP_HC_ARLEN       (S0_AXI_HP_HC_ARLEN       ),
  .S0_AXI_HP_HC_ARQOS       (S0_AXI_HP_HC_ARQOS       ),
  .S0_AXI_HP_HC_AWCACHE     (S0_AXI_HP_HC_AWCACHE     ),
  .S0_AXI_HP_HC_AWLEN       (S0_AXI_HP_HC_AWLEN       ),
  .S0_AXI_HP_HC_AWQOS       (S0_AXI_HP_HC_AWQOS       ),
  .S0_AXI_HP_HC_ARID        (S0_AXI_HP_HC_ARID        ),
  .S0_AXI_HP_HC_AWID        (S0_AXI_HP_HC_AWID        ),
  .S0_AXI_HP_HC_WID         (S0_AXI_HP_HC_WID         ),
  .S0_AXI_HP_HC_WDATA       (S0_AXI_HP_HC_WDATA       ),
  .S0_AXI_HP_HC_WSTRB       (S0_AXI_HP_HC_WSTRB       ), 

  .S1_AXI_HP_HC_ARREADY     (S1_AXI_HP_HC_ARREADY     ),
  .S1_AXI_HP_HC_AWREADY     (S1_AXI_HP_HC_AWREADY     ),
  .S1_AXI_HP_HC_BVALID      (S1_AXI_HP_HC_BVALID      ),
  .S1_AXI_HP_HC_RLAST       (S1_AXI_HP_HC_RLAST       ),
  .S1_AXI_HP_HC_RVALID      (S1_AXI_HP_HC_RVALID      ),
  .S1_AXI_HP_HC_WREADY      (S1_AXI_HP_HC_WREADY      ),
  .S1_AXI_HP_HC_BRESP       (S1_AXI_HP_HC_BRESP       ),
  .S1_AXI_HP_HC_RRESP       (S1_AXI_HP_HC_RRESP       ),
  .S1_AXI_HP_HC_BID         (S1_AXI_HP_HC_BID         ),
  .S1_AXI_HP_HC_RID         (S1_AXI_HP_HC_RID         ),
  .S1_AXI_HP_HC_RDATA       (S1_AXI_HP_HC_RDATA       ),
  .S1_AXI_HP_HC_ARVALID     (S1_AXI_HP_HC_ARVALID     ),
  .S1_AXI_HP_HC_AWVALID     (S1_AXI_HP_HC_AWVALID     ),
  .S1_AXI_HP_HC_BREADY      (S1_AXI_HP_HC_BREADY      ),
  .S1_AXI_HP_HC_RREADY      (S1_AXI_HP_HC_RREADY      ),
  .S1_AXI_HP_HC_WLAST       (S1_AXI_HP_HC_WLAST       ),
  .S1_AXI_HP_HC_WVALID      (S1_AXI_HP_HC_WVALID      ),
  .S1_AXI_HP_HC_ARBURST     (S1_AXI_HP_HC_ARBURST     ),
  .S1_AXI_HP_HC_ARLOCK      (S1_AXI_HP_HC_ARLOCK      ),
  .S1_AXI_HP_HC_ARSIZE      (S1_AXI_HP_HC_ARSIZE      ),
  .S1_AXI_HP_HC_AWBURST     (S1_AXI_HP_HC_AWBURST     ),
  .S1_AXI_HP_HC_AWLOCK      (S1_AXI_HP_HC_AWLOCK      ),
  .S1_AXI_HP_HC_AWSIZE      (S1_AXI_HP_HC_AWSIZE      ),
  .S1_AXI_HP_HC_ARPROT      (S1_AXI_HP_HC_ARPROT      ),
  .S1_AXI_HP_HC_AWPROT      (S1_AXI_HP_HC_AWPROT      ),
  .S1_AXI_HP_HC_ARADDR      (S1_AXI_HP_HC_ARADDR      ),
  .S1_AXI_HP_HC_AWADDR      (S1_AXI_HP_HC_AWADDR      ),
  .S1_AXI_HP_HC_ARCACHE     (S1_AXI_HP_HC_ARCACHE     ),
  .S1_AXI_HP_HC_ARLEN       (S1_AXI_HP_HC_ARLEN       ),
  .S1_AXI_HP_HC_ARQOS       (S1_AXI_HP_HC_ARQOS       ),
  .S1_AXI_HP_HC_AWCACHE     (S1_AXI_HP_HC_AWCACHE     ),
  .S1_AXI_HP_HC_AWLEN       (S1_AXI_HP_HC_AWLEN       ),
  .S1_AXI_HP_HC_AWQOS       (S1_AXI_HP_HC_AWQOS       ),
  .S1_AXI_HP_HC_ARID        (S1_AXI_HP_HC_ARID        ),
  .S1_AXI_HP_HC_AWID        (S1_AXI_HP_HC_AWID        ),
  .S1_AXI_HP_HC_WID         (S1_AXI_HP_HC_WID         ),
  .S1_AXI_HP_HC_WDATA       (S1_AXI_HP_HC_WDATA       ),
  .S1_AXI_HP_HC_WSTRB       (S1_AXI_HP_HC_WSTRB       ), 

  .S2_AXI_HP_HC_ARREADY     (S2_AXI_HP_HC_ARREADY     ),
  .S2_AXI_HP_HC_AWREADY     (S2_AXI_HP_HC_AWREADY     ),
  .S2_AXI_HP_HC_BVALID      (S2_AXI_HP_HC_BVALID      ),
  .S2_AXI_HP_HC_RLAST       (S2_AXI_HP_HC_RLAST       ),
  .S2_AXI_HP_HC_RVALID      (S2_AXI_HP_HC_RVALID      ),
  .S2_AXI_HP_HC_WREADY      (S2_AXI_HP_HC_WREADY      ),
  .S2_AXI_HP_HC_BRESP       (S2_AXI_HP_HC_BRESP       ),
  .S2_AXI_HP_HC_RRESP       (S2_AXI_HP_HC_RRESP       ),
  .S2_AXI_HP_HC_BID         (S2_AXI_HP_HC_BID         ),
  .S2_AXI_HP_HC_RID         (S2_AXI_HP_HC_RID         ),
  .S2_AXI_HP_HC_RDATA       (S2_AXI_HP_HC_RDATA       ),
  .S2_AXI_HP_HC_ARVALID     (S2_AXI_HP_HC_ARVALID     ),
  .S2_AXI_HP_HC_AWVALID     (S2_AXI_HP_HC_AWVALID     ),
  .S2_AXI_HP_HC_BREADY      (S2_AXI_HP_HC_BREADY      ),
  .S2_AXI_HP_HC_RREADY      (S2_AXI_HP_HC_RREADY      ),
  .S2_AXI_HP_HC_WLAST       (S2_AXI_HP_HC_WLAST       ),
  .S2_AXI_HP_HC_WVALID      (S2_AXI_HP_HC_WVALID      ),
  .S2_AXI_HP_HC_ARBURST     (S2_AXI_HP_HC_ARBURST     ),
  .S2_AXI_HP_HC_ARLOCK      (S2_AXI_HP_HC_ARLOCK      ),
  .S2_AXI_HP_HC_ARSIZE      (S2_AXI_HP_HC_ARSIZE      ),
  .S2_AXI_HP_HC_AWBURST     (S2_AXI_HP_HC_AWBURST     ),
  .S2_AXI_HP_HC_AWLOCK      (S2_AXI_HP_HC_AWLOCK      ),
  .S2_AXI_HP_HC_AWSIZE      (S2_AXI_HP_HC_AWSIZE      ),
  .S2_AXI_HP_HC_ARPROT      (S2_AXI_HP_HC_ARPROT      ),
  .S2_AXI_HP_HC_AWPROT      (S2_AXI_HP_HC_AWPROT      ),
  .S2_AXI_HP_HC_ARADDR      (S2_AXI_HP_HC_ARADDR      ),
  .S2_AXI_HP_HC_AWADDR      (S2_AXI_HP_HC_AWADDR      ),
  .S2_AXI_HP_HC_ARCACHE     (S2_AXI_HP_HC_ARCACHE     ),
  .S2_AXI_HP_HC_ARLEN       (S2_AXI_HP_HC_ARLEN       ),
  .S2_AXI_HP_HC_ARQOS       (S2_AXI_HP_HC_ARQOS       ),
  .S2_AXI_HP_HC_AWCACHE     (S2_AXI_HP_HC_AWCACHE     ),
  .S2_AXI_HP_HC_AWLEN       (S2_AXI_HP_HC_AWLEN       ),
  .S2_AXI_HP_HC_AWQOS       (S2_AXI_HP_HC_AWQOS       ),
  .S2_AXI_HP_HC_ARID        (S2_AXI_HP_HC_ARID        ),
  .S2_AXI_HP_HC_AWID        (S2_AXI_HP_HC_AWID        ),
  .S2_AXI_HP_HC_WID         (S2_AXI_HP_HC_WID         ),
  .S2_AXI_HP_HC_WDATA       (S2_AXI_HP_HC_WDATA       ),
  .S2_AXI_HP_HC_WSTRB       (S2_AXI_HP_HC_WSTRB       ), 

  .S3_AXI_HP_HC_ARREADY     (S3_AXI_HP_HC_ARREADY     ),
  .S3_AXI_HP_HC_AWREADY     (S3_AXI_HP_HC_AWREADY     ),
  .S3_AXI_HP_HC_BVALID      (S3_AXI_HP_HC_BVALID      ),
  .S3_AXI_HP_HC_RLAST       (S3_AXI_HP_HC_RLAST       ),
  .S3_AXI_HP_HC_RVALID      (S3_AXI_HP_HC_RVALID      ),
  .S3_AXI_HP_HC_WREADY      (S3_AXI_HP_HC_WREADY      ),
  .S3_AXI_HP_HC_BRESP       (S3_AXI_HP_HC_BRESP       ),
  .S3_AXI_HP_HC_RRESP       (S3_AXI_HP_HC_RRESP       ),
  .S3_AXI_HP_HC_BID         (S3_AXI_HP_HC_BID         ),
  .S3_AXI_HP_HC_RID         (S3_AXI_HP_HC_RID         ),
  .S3_AXI_HP_HC_RDATA       (S3_AXI_HP_HC_RDATA       ),
  .S3_AXI_HP_HC_ARVALID     (S3_AXI_HP_HC_ARVALID     ),
  .S3_AXI_HP_HC_AWVALID     (S3_AXI_HP_HC_AWVALID     ),
  .S3_AXI_HP_HC_BREADY      (S3_AXI_HP_HC_BREADY      ),
  .S3_AXI_HP_HC_RREADY      (S3_AXI_HP_HC_RREADY      ),
  .S3_AXI_HP_HC_WLAST       (S3_AXI_HP_HC_WLAST       ),
  .S3_AXI_HP_HC_WVALID      (S3_AXI_HP_HC_WVALID      ),
  .S3_AXI_HP_HC_ARBURST     (S3_AXI_HP_HC_ARBURST     ),
  .S3_AXI_HP_HC_ARLOCK      (S3_AXI_HP_HC_ARLOCK      ),
  .S3_AXI_HP_HC_ARSIZE      (S3_AXI_HP_HC_ARSIZE      ),
  .S3_AXI_HP_HC_AWBURST     (S3_AXI_HP_HC_AWBURST     ),
  .S3_AXI_HP_HC_AWLOCK      (S3_AXI_HP_HC_AWLOCK      ),
  .S3_AXI_HP_HC_AWSIZE      (S3_AXI_HP_HC_AWSIZE      ),
  .S3_AXI_HP_HC_ARPROT      (S3_AXI_HP_HC_ARPROT      ),
  .S3_AXI_HP_HC_AWPROT      (S3_AXI_HP_HC_AWPROT      ),
  .S3_AXI_HP_HC_ARADDR      (S3_AXI_HP_HC_ARADDR      ),
  .S3_AXI_HP_HC_AWADDR      (S3_AXI_HP_HC_AWADDR      ),
  .S3_AXI_HP_HC_ARCACHE     (S3_AXI_HP_HC_ARCACHE     ),
  .S3_AXI_HP_HC_ARLEN       (S3_AXI_HP_HC_ARLEN       ),
  .S3_AXI_HP_HC_ARQOS       (S3_AXI_HP_HC_ARQOS       ),
  .S3_AXI_HP_HC_AWCACHE     (S3_AXI_HP_HC_AWCACHE     ),
  .S3_AXI_HP_HC_AWLEN       (S3_AXI_HP_HC_AWLEN       ),
  .S3_AXI_HP_HC_AWQOS       (S3_AXI_HP_HC_AWQOS       ),
  .S3_AXI_HP_HC_ARID        (S3_AXI_HP_HC_ARID        ),
  .S3_AXI_HP_HC_AWID        (S3_AXI_HP_HC_AWID        ),
  .S3_AXI_HP_HC_WID         (S3_AXI_HP_HC_WID         ),
  .S3_AXI_HP_HC_WDATA       (S3_AXI_HP_HC_WDATA       ),
  .S3_AXI_HP_HC_WSTRB       (S3_AXI_HP_HC_WSTRB       ), 

  .pl_awaddr                (pl_awaddr                ),
  .pl_awdata                (pl_awdata                ),
  .pl_awen                  (pl_awen                  ),
  .pl_awinfo                (pl_awinfo                ),
  .pl_awlast                (pl_awlast                ),
  .pl_awvalid               (pl_awvalid               ),
  .pl_awready               (pl_awready               ),
  .pl_araddr                (pl_araddr                ),
  .pl_arinfo                (pl_arinfo                ),
  .pl_arlast                (pl_arlast                ),
  .pl_arvalid               (pl_arvalid               ),
  .pl_arready               (pl_arready               ),
  .pl_rdata                 (pl_rdata                 ),
  .pl_rvalid                (pl_rvalid                ),
  .pl_rlast                 (pl_rlast                 ),
  .pl_rready                (pl_rready                ),
  .pl_bvalid                (pl_bvalid                ),  //30TAI
  .pl_bready                (pl_bready                ),  //30TAI  
  .pl_ra_awaddr             (pl_ra_awaddr             ),
  .pl_ra_awdata             (pl_ra_awdata             ),
  .pl_ra_awvalid            (pl_ra_awvalid            ),
  .pl_ra_awready            (pl_ra_awready            ),
  .pl_ra_araddr             (pl_ra_araddr             ),
  .pl_ra_arvalid            (pl_ra_arvalid            ),
  .pl_ra_arready            (pl_ra_arready            ),
  .pl_ra_rdata              (pl_ra_rdata              ),
  .pl_ra_rvalid             (pl_ra_rvalid             ),
  .pl_ra_rready             (pl_ra_rready             ),
  .pl_int_info              (pl_int_info              ),  //30TAI  
  .pl_int_valid             (pl_int_valid             ),  //30TAI
  .pl_int_ready             (pl_int_ready             ),  //30TAI  
  .pl_ra_clk                (pl_ra_clk                ),
  .pl_itf_clk               (pl_itf_clk               ),
  .pl_rst_n                 (pl_rst_n                 ),
  .pl_clk_en_b              (pl_clk_en_b              ),
  //.pl_row_en_b              (pl_row_en_b              ),
  //.pl_col_en_b              (pl_col_en_b              ),
  .pl_bist_clk              (pl_bist_clk              ),
  .pl_bist_rstn             (pl_bist_rstn             ),
  .pl_bist_en               (pl_bist_en               ),
  .pl_bist_err              (pl_bist_err              ),
  .pl_bist_done             (pl_bist_done             ),
  .pl_repair_done           (pl_repair_done           ),
  .pl_repair_fail           (pl_repair_fail           ),
  //.pl_buyi_error            (pl_buyi_error            ),
  .pl_bist_err_inv          (pl_bist_err_inv          ),
  .pl_clk_div_out           (pl_clk_div_out           ),
  .pl_scan_mode_b           (pl_scan_mode_b           ),
  .pl_scan_en               (pl_scan_en               ),
  .pl_scan_clk              (pl_scan_clk              ),
  .pl_scan_rst_n            (pl_scan_rst_n            ),
  //.pl_scan_pipe_clk         (pl_scan_pipe_clk         ),
  .pl_scan_i                (pl_scan_i                ),
  .pl_scan_o                (pl_scan_o                ),

  .gp0_ar_cnt               (gp0_ar_cnt               ),
  .gp0_r_cnt                (gp0_r_cnt                ),
  .gp0_aw_cnt               (gp0_aw_cnt               ),   
  .gp0_w_cnt                (gp0_w_cnt                ),
  .gp0_b_cnt                (gp0_b_cnt                ),

  .gp1_ar_cnt               (gp1_ar_cnt               ),
  .gp1_r_cnt                (gp1_r_cnt                ),
  .gp1_aw_cnt               (gp1_aw_cnt               ),
  .gp1_w_cnt                (gp1_w_cnt                ),  
  .gp1_b_cnt                (gp1_b_cnt                ),   
  .hp_disable               (                         ),

  //irq
  .customop_irq             (customop_irq             ),
  .ai_irq                   (ai_irq                  )     
);


mig_7series_0 mig_ddr3_u0 (
        .ddr3_dq             (ddr3_dq            ),
        .ddr3_dqs_n          (ddr3_dqs_n         ),
        .ddr3_dqs_p          (ddr3_dqs_p         ),
        .ddr3_addr           (ddr3_addr          ),
        .ddr3_ba             (ddr3_ba            ),
        .ddr3_ras_n          (ddr3_ras_n         ),
        .ddr3_cas_n          (ddr3_cas_n         ),
        .ddr3_we_n           (ddr3_we_n          ),
        .ddr3_reset_n        (ddr3_reset_n       ),
        .ddr3_ck_p           (ddr3_ck_p          ),
        .ddr3_ck_n           (ddr3_ck_n          ),
        .ddr3_cke            (ddr3_cke           ),
        .ddr3_cs_n           (ddr3_cs_n          ),
        .ddr3_dm             (ddr3_dm            ),
        .ddr3_odt            (ddr3_odt           ),

        .init_calib_complete (ddr3_init_done     ),

        .app_addr            (app_addr           ),
        .app_cmd             (app_cmd            ),
        .app_en              (app_en             ),
        .app_wdf_data        (app_wdf_data       ),
        .app_wdf_end         (app_wdf_end        ),
        .app_wdf_wren        (app_wdf_wren       ),
        .app_rd_data         (app_rd_data        ),
        .app_rd_data_end     (app_rd_data_end    ),
        .app_rd_data_valid   (app_rd_data_valid  ),
        .app_rdy             (app_rdy            ),
        .app_wdf_rdy         (app_wdf_rdy        ),
        .app_wdf_mask        (app_wdf_mask       ),

        .app_sr_req          (1'b0               ),
        .app_ref_req         (1'b0               ),
        .app_zq_req          (1'b0               ),
        .app_sr_active       (                   ),
        .app_ref_ack         (                   ),
        .app_zq_ack          (                   ),

        .ui_clk              (ddr_clk            ),
        .ui_clk_sync_rst     (ddr_ui_rst         ),

        .sys_clk_p           (sys_clk_p          ),
        .sys_clk_n           (sys_clk_n          ),
        .device_temp_i       ('d0                ),  // input [11:0]			device_temp_i
        .sys_rst             (core_rst           )
    );


reg  [31:0]   cnt_led;
reg           led_test_blink;
assign led_test[0] = (video_mode == 2'd2);
assign led_test[1] = led_test_blink;
always @(posedge ddr_clk)begin
   if(!sys_rst_n)begin
            cnt_led<='d0;
            led_test_blink<=1'b0;
   end
   else begin
            if(cnt_led==32'd100_000_000)begin
                led_test_blink<=~led_test_blink;
                cnt_led<='d0;
            end
            else begin

                cnt_led<=cnt_led+1;
            end

     end
end







endmodule
