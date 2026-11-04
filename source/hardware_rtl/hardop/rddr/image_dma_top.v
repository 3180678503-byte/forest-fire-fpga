//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : image_make_top.v
// Author        : Luo Wei
// Project       : NB2138
// Create Date   : 2022.2.16
// Description   :
// - Image make top module   plin 
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
module image_dma_top #( parameter HP_DW=64, HP_AW=32, AS=8, ICN=4, HP_NUM=3, PCN=4, IEDW=8)(
        // ======== master axi interface, connect HP ========
        mna_hp_std_itf.master       hp                    ,
        // ========   slave axi lite interface gp   ========
        mna_gp_ww_itf.slave         gp                    ,
        input                       S_AXI_ACLK            ,//gp0_clk
        input                       S_AXI_ARESETN         ,//gp0_rst_n
        output                      img_rddr_start        ,
        output                      img_rdata_end         , 
        output   [        1 : 0]    data_path             ,
        output   [        1 : 0]    data_type             ,
        input                       img_ready             ,
        output   [IEDW*PCN-1: 0]    img_data              ,
        output                      img_valid             ,
        output                      img_start             , 
        input                       img_clk               ,
        input                       img_rst               
);
               
    wire         [       31 : 0]     img_rddr_base   ;
    wire         [       23 : 0]     img_rddr_len    ; // ((width*height-1)/8+1)*3
    wire         [        4 : 0]     img_last_sft    ; // w*h-(len-3)/3*8
    wire         [       31 : 0]     img_rstatus     ;
    wire         [        3 : 0]     img_rddr_st     ;
    wire                             img_rddr_done   ;
    wire         [        6 : 0]     channel_each    ;

    assign img_rstatus = {28'd0,img_rddr_st};
    assign img_start = img_rddr_start;

    image_dma_ctrl #(.ICN(ICN)) image_dma_ctrl_u0(
    // ======== slave axi lite interface ========
         .S_AXI_ACLK           (S_AXI_ACLK          ),
         .S_AXI_ARESETN        (S_AXI_ARESETN       ),
         .cam_gp1_s01          (gp                  ),
         .img_rddr_start       (img_rddr_start      ),
         .img_rddr_base        (img_rddr_base       ),
         .img_rddr_len         (img_rddr_len        ), // ceil(w*h/21)
         .img_last_sft         (img_last_sft        ), // w*h - 21*(len-1)\
         .channel_each         (channel_each        ),
         .data_path            (data_path           ),
         .data_type            (data_type           ),
         .img_rstatus          (img_rstatus         ),
         .img_clk              (img_clk             ),
         .img_rst              (img_rst             )
	); 

    
    image_dma #(.HP_DW( HP_DW), .HP_AW(HP_AW), .AS(AS), .ICN(ICN), .SCN(PCN), .HP_NUM(HP_NUM), .IEDW(IEDW)) image_dma_u0 (
        .hp                    (hp                  ),
        .img_rddr_done         (img_rddr_done       ),
        .img_rddr_start        (img_rddr_start      ),
        .img_rddr_base         (img_rddr_base       ),
        .img_rddr_len          (img_rddr_len        ), // ceil(w*h/21)
        .img_last_sft          (img_last_sft        ), // w*h - 21*(len-1)
        .channel_each          (channel_each        ), 
        .channel_times         ('d1                 ),

        .img_data              (img_data            ),
        .img_valid             (img_valid           ),
        .img_ready             (img_ready           ),
        .img_rddr_st           (img_rddr_st         ),
        .img_rdata_end         (img_rdata_end       ),

        .img_clk               (img_clk             ),
        .img_rst               (img_rst             )
    ); 
   

endmodule