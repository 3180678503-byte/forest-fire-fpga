//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : pcie_axi_in.v
// Author        : Luo Wei
// Project       : NB2138
// Create Date   : 2022.06.22
// Description   :
// - pcie_axi_in
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
module pcie_axi_in #( parameter IEDW=8,OEDW=8, DDR_AW=32, AS=8, ICN=4, HP_NUM=3, PCN=3)(
    // =========== slave axi lite interface ===========
    mna_gp_ww_itf.slave         gp                    ,
    input                       S_AXI_ACLK            ,   //gp0_clk
    input                       S_AXI_ARESETN         ,   //gp0_rst_n
    // ===================    FPGA    =================           
    input                       M_AXI_ACLK            ,   //ddr_clk
    input                       M_AXI_ARESETN         ,   //ddr_rst_n 
    //PL DDR      
    mna_ddr_rd_itf.master       img_ddr_rd_itf        ,   //ddr r
    // ======== master axi interface, connect HP ======
    mna_hp_std_itf.master       hp                    ,
    input                       hp_clk                ,
    input                       hp_rst                ,
    //==================== image out ==================
    input                       img_ready             ,
    output   [OEDW*PCN-1: 0]    img_data              ,
    output                      img_valid             ,
    output                      img_start             
);
    wire                        img_rddr_start  ;
    wire                        img_rdata_end   ;
    wire     [        1 : 0]    data_path       ; // 0 -> PL DDR    1-> HP
    wire     [        1 : 0]    data_type       ;
    wire     [        2 : 0]    fifo_st0        ;
    wire     [        2 : 0]    fifo_st1        ;
    wire     [IEDW*PCN-1: 0]    img_data_in     ;
    wire     [OEDW*PCN-1: 0]    img_data0       ;
    wire     [OEDW*PCN-1: 0]    img_data1       ;

    mna_hp_std_itf              hpx()           ; 
    mna_hp_std_itf              hpy()           ; 
    mna_hp_std_itf              hp_out()        ; 
    


    //PL DDR
    rddr_convertor rddr_convertor_u0(
        .rddr_arvalid            (img_ddr_rd_itf.arvalid ),
        .rddr_araddr             (img_ddr_rd_itf.araddr  ),
        .rddr_arready            (img_ddr_rd_itf.arready ),    
        .img_arvalid             (hpx.arvalid            ),
        .img_araddr              (hpx.araddr             ),
        .img_arready             (hpx.arready            ),    
        .img_rddr_start          (img_rddr_start         ),
        .img_rdata_end           (img_rdata_end          ),    
        .rddr_rvalid             (img_ddr_rd_itf.rvalid  ),
        .rddr_rdata              (img_ddr_rd_itf.rdata   ),
        .rddr_rready             (img_ddr_rd_itf.rready  ),    
        .img_rvalid              (hpx.rvalid             ),
        .img_rdata               (hpx.rdata              ),
        .img_rready              (hpx.rready             ),    
        .clk                     (M_AXI_ACLK             ),
        .rst                     (~M_AXI_ARESETN         )
    );  

    //chose data_path
    assign hp_out.arready = data_path == 2'b0 ? hpx.arready : hpy.arready;
    assign hpx.arvalid = data_path == 2'b0 && hp_out.arvalid;
    assign hpx.araddr =  hp_out.araddr;
    assign hpy.arvalid = data_path == 2'b1 && hp_out.arvalid;
    assign hpy.araddr =  hp_out.araddr;
    
    assign hp_out.rdata = data_path == 2'b0 ? hpx.rdata : hpy.rdata;
    assign hp_out.rvalid = data_path == 2'b0 ? hpx.rvalid : hpy.rvalid;
    assign hpx.rready = data_path == 2'b0 && hp_out.rready;
    assign hpy.rready = data_path == 2'b1 && hp_out.rready;

    //cdc
    cdc_fifo_imgmk #(.DW(64)) cdc_fifo_imgmk_u0(
        .wdata       (  hp.rdata       ),
        .wvalid      (  hp.rvalid      ),
        .wready      (  hp.rready      ),

        .rdata       (  hpy.rdata      ),
        .rvalid      (  hpy.rvalid     ),
        .rready      (  hpy.rready     ),

        .fifo_st     (  fifo_st0       ),
        .wrst        (  hp_rst         ),
        .wclk        (  hp_clk         ),
        .rrst        (  ~M_AXI_ARESETN ),
        .rclk        (  M_AXI_ACLK     )
    );

    cdc_fifo_imgmk #(.DW(32)) cdc_fifo_imgmk_u1(
        .wdata       (  hpy.araddr     ),
        .wvalid      (  hpy.arvalid    ),
        .wready      (  hpy.arready    ),

        .rdata       (  hp.araddr      ),
        .rvalid      (  hp.arvalid     ),
        .rready      (  hp.arready     ),

        .fifo_st     (  fifo_st1       ),
        .wrst        (  ~M_AXI_ARESETN ),
        .wclk        (  M_AXI_ACLK     ),
        .rrst        (  hp_rst         ),
        .rclk        (  hp_clk         )
    );

    image_dma_top #(.HP_DW(64), .HP_AW(32), .AS(8), .ICN(4), .HP_NUM(3), .PCN(PCN), .IEDW(IEDW)) image_dma_top_u0(
        .hp                      (hp_out             )  ,
        .gp                      (gp                 )  ,
        .S_AXI_ACLK              (S_AXI_ACLK         )  ,//gp0_clk
        .S_AXI_ARESETN           (S_AXI_ARESETN      )  ,//gp0_rst_n
        .img_rddr_start          (img_rddr_start     )  ,
        .img_rdata_end           (img_rdata_end      )  , 
        .data_path               (data_path          )  ,  
        .data_type               (data_type          )  ,
        .img_ready               (img_ready          )  ,
        .img_data                (img_data_in        )  ,
        .img_valid               (img_valid          )  ,
        .img_start               (img_start          )  , 
        .img_clk                 (M_AXI_ACLK         )  ,
        .img_rst                 (~M_AXI_ARESETN     )  
    );
     
    //uint8 -> int16
    //genvar i;
    //generate
    //    for(i=0;i<PCN;i=i+1)begin: img_data_0
    //        assign img_data0[i*OEDW+:OEDW] = {{(OEDW-IEDW){1'b0}},img_data_in[i*IEDW+:IEDW]};
    //    end
    //endgenerate

    ////int8 -> int16
    //genvar j;
    //generate
    //    for(j=0;j<PCN;j=j+1)begin: img_data_1
    //        assign img_data1[j*OEDW+:OEDW] = {{(OEDW-IEDW){img_data_in[j*IEDW+IEDW-1]}},img_data_in[j*IEDW+:IEDW]};
    //    end
    //endgenerate

    //assign img_data = (data_type == 2'd0) ? img_data0 : img_data1;

    genvar i;
    generate
        for(i=0;i<PCN;i=i+1)begin: img_data_0
            assign img_data[i*OEDW+:OEDW] = img_data_in[i*IEDW+:IEDW];
        end
    endgenerate

endmodule
