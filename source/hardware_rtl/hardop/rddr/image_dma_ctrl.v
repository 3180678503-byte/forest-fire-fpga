
//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : image_dma_ctrl.v
// Author        : Luo Wei
// Project       : NB2138
// Create Date   : 2022.2.18
// Description   :
// - Host top control
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module image_dma_ctrl #(parameter ICN=3) (
    // ======== slave axi lite interface ==============
    input                       S_AXI_ACLK            ,
    input                       S_AXI_ARESETN         ,
    mna_gp_ww_itf.slave         cam_gp1_s01           ,
 
	// =============== ctrl & status ==================
    output                      img_rddr_start        ,
    output reg [     31 : 0]    img_rddr_base         ,
    output reg [     23 : 0]    img_rddr_len          , // ((width*height-1)/8+1)*3
    output reg [      4 : 0]    img_last_sft          , // w*h-(len-3)/3*8
    output reg [      6 : 0]    channel_each          ,
    output reg [      1 : 0]    data_path             ,
    output reg [      1 : 0]    data_type             ,
    input      [     31 : 0]    img_rstatus           ,
    input                       img_clk               ,
    input                       img_rst               
);
     // axi-lite reg signals
     reg    [8 : 0]          axi_awaddr         ;
     reg    [8 : 0]          axi_araddr         ;
     reg    [31: 0]          axi_awdata         ;
 
     wire   [31: 0]          slv_reg0           ;
     wire   [31: 0]          slv_reg1           ;
     wire   [31: 0]          slv_reg2           ;
     wire   [31: 0]          slv_reg3           ;
     wire   [31: 0]          slv_reg4           ;
     wire   [31: 0]          slv_reg5           ;
     wire   [31: 0]          slv_reg6           ; 
     wire   [31: 0]          slv_reg7           ; 
     wire   [31: 0]          slv_reg8           ; 

     wire                    slv_reg_rden       ;
     wire                    slv_reg_wren       ;
     reg    [31: 0]          test_reg           ;
     reg                     img_cmd            ;
     wire                    img_cmd_cross      ;

    //------------------------------------------------
    //-- AXI-lite Write Register Control--
    //------------------------------------------------
    assign cam_gp1_s01.awwready = 1'b1;

    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            axi_awaddr <= 0;
        else if (cam_gp1_s01.awwvalid)
            axi_awaddr <= cam_gp1_s01.awwaddr[9:0];
    end

    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            axi_awdata <= 0;
        else if (cam_gp1_s01.awwvalid)
            axi_awdata <= cam_gp1_s01.awwdata;
    end

    assign slv_reg_wren = cam_gp1_s01.awwready && cam_gp1_s01.awwvalid;

    assign cam_gp1_s01.arready = 1'b1;

    always @( posedge S_AXI_ACLK )
    begin
      if ( S_AXI_ARESETN == 1'b0 )
          axi_araddr  <= 10'h0;
      else if (cam_gp1_s01.arvalid)
          axi_araddr  <= cam_gp1_s01.araddr;
    end

    always @( posedge S_AXI_ACLK )
    begin
      if ( S_AXI_ARESETN == 1'b0 )
          cam_gp1_s01.rvalid <= 0;
      else if (cam_gp1_s01.arready && cam_gp1_s01.arvalid)
          cam_gp1_s01.rvalid <= 1'b1;
      else if (cam_gp1_s01.rready)
          cam_gp1_s01.rvalid <= 1'b0;
    end
 
    assign slv_reg_rden = cam_gp1_s01.arready & cam_gp1_s01.arvalid;

    //------------------------------------------------
    //-- Registers File Definition --
    //------------------------------------------------
    //10'h000 : slv_reg0
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            img_cmd <= 1'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h000)
            img_cmd <= cam_gp1_s01.awwdata[0];
		else
		    img_cmd <= 1'h0; 
    end
    assign slv_reg0 = {31'd0, img_cmd};

    pulse_cross pulse_cross_u1(
        .a2    (img_cmd_cross  ),
        .clk2  (img_clk        ),
        .rst2  (img_rst        ),

        .a1    (img_cmd        ),
        .clk1  (S_AXI_ACLK     ),
        .rst1  (~S_AXI_ARESETN  )
     );

    assign img_rddr_start = img_cmd_cross;
    // 10'h004 : slv_reg1
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            img_rddr_base <= 32'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h004)
            img_rddr_base <= cam_gp1_s01.awwdata[31:0];
    end
    assign slv_reg1 = img_rddr_base;

    //10'h008 : slv_reg2
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            img_rddr_len <= 24'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h008)
            img_rddr_len <= cam_gp1_s01.awwdata[23:0];
    end
    assign slv_reg2 = {8'h0, img_rddr_len};

    //10'h00C : slv_reg3
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            img_last_sft <= 5'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h00C)
            img_last_sft <= cam_gp1_s01.awwdata[4:0];
    end
    assign slv_reg3 = {27'h0, img_last_sft};

    //10'h0010 : slv_reg4
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            channel_each <= 7'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h010)
            channel_each <= cam_gp1_s01.awwdata[6:0];
    end
    assign slv_reg4 = {25'h0, channel_each};


    //10'h014 : slv_reg5
    assign slv_reg5 = img_rstatus;

    //10'h018 : slv_reg6
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            test_reg <= 32'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h018)
            test_reg <= cam_gp1_s01.awwdata;
    end
    assign slv_reg6 = test_reg;

    // 10'h01C : slv_reg7
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            data_path <= 32'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h01C)
            data_path <= cam_gp1_s01.awwdata;
    end
    assign slv_reg7 = data_path;

    // 10'h020 : slv_reg8
    always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            data_type <= 32'h0;
        else if (slv_reg_wren && cam_gp1_s01.awwaddr[9:0]==10'h020)
            data_type <= cam_gp1_s01.awwdata;
    end
    assign slv_reg8 = data_type;


//gp read reg
always @( posedge S_AXI_ACLK )
    begin
        if ( S_AXI_ARESETN == 1'b0 )
            cam_gp1_s01.rdata  <= 0;
        else if(slv_reg_rden )
            case(cam_gp1_s01.araddr[9:0])
                10'h000 :  cam_gp1_s01.rdata <= slv_reg0;
                10'h004 :  cam_gp1_s01.rdata <= slv_reg1;
                10'h008 :  cam_gp1_s01.rdata <= slv_reg2;
                10'h00C :  cam_gp1_s01.rdata <= slv_reg3;
                10'h010 :  cam_gp1_s01.rdata <= slv_reg4;   
                10'h014 :  cam_gp1_s01.rdata <= slv_reg5;    
                10'h018 :  cam_gp1_s01.rdata <= slv_reg6;  
                10'h01C :  cam_gp1_s01.rdata <= slv_reg7;
                10'h020 :  cam_gp1_s01.rdata <= slv_reg8;
                default :  cam_gp1_s01.rdata <= 32'h0   ;
            endcase
    end

endmodule
