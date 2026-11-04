//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : image_dma.v
// Author        : Luo Wei
// Project       : NB2138
// Create Date   : 2021.9.09
// Description   :
// - Image read hp 
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
module image_dma #( parameter HP_DW=64, HP_AW=32, AS=64,ICN=3, SCN=3, HP_NUM=3, IEDW=8) (
        mna_hp_std_itf.master       hp             ,
        output                      img_rddr_done  ,
        input                       img_rddr_start ,
        input    [ HP_AW-1 : 0]     img_rddr_base  ,
        input    [      23 : 0]     img_rddr_len   , // ceil(w*h/21)
        input    [       4 : 0]     img_last_sft   , // w*h - 21*(len-1)
        input    [        6 : 0]    channel_each   ,
        input    [        6 : 0]    channel_times  ,       

        output   [IEDW*SCN-1: 0]    img_data       ,  //
        output                      img_valid      ,
        input                       img_ready      ,
        output   [        3 : 0]    img_rddr_st    ,

        output                      img_rdata_end  ,

        input                       img_clk        ,
        input                       img_rst
);

    wire [       HP_AW-1 : 0] img_rddr_araddr  ;//as = 64,o
    wire                      img_rddr_arvalid ;//o
    wire                      img_rddr_arready ;//i

    wire [   64*HP_NUM-1 : 0] n2w_wdata        ;
    wire                      n2w_wvalid       ;
    wire                      n2w_wlast        ;
    wire                      n2w_wready       ;
 
    n2w_bwc_sp#(.NDW(64), .WDW(64*HP_NUM), .CBW(5)) n2w_bwc_u0(
        .n2w_ndata       (hp.rdata        ),
        .n2w_nvalid      (hp.rvalid       ),
        .n2w_nlast       (1'b0            ),
        .n2w_nready      (hp.rready       ),

        .n2w_wdata       (n2w_wdata       ),
        .n2w_wlast       (n2w_wlast       ),
        .n2w_wvalid      (n2w_wvalid      ),
        .n2w_wready      (n2w_wready      ),

        .n2w_clk_rst     (img_rst         ),
        .n2w_clk         (img_clk         )
    );
    
    img_rddr #(.AS(AS),.ICN(ICN),.SCN(SCN),.HP_NUM(HP_NUM),.IEDW(IEDW)) img_rddr_u0(
        .img_rddr_data    (n2w_wdata        ),//i
        .img_rddr_valid   (n2w_wvalid       ),//i
        .img_rddr_ready   (n2w_wready       ),//o

        .img_rddr_araddr  (hp.araddr        ),//as = 64,o
        .img_rddr_arvalid (hp.arvalid       ),//o
        .img_rddr_arready (hp.arready       ),//i

        .img_rddr_done    (img_rddr_done    ),

        .img_rddr_start   (img_rddr_start   ),
        .img_rddr_base    (img_rddr_base    ),
        .img_rddr_len     (img_rddr_len     ),
        .img_last_sft     (img_last_sft     ),
        .channel_each     (channel_each     ),
        .channel_times    (channel_times    ),

        .img_data         (img_data         ),
        .img_dv           (img_valid        ),
        .img_ready        (img_ready        ),

        .img_rddr_st      (img_rddr_st      ),
        .img_rdata_end    (img_rdata_end    ),
        .clk              (img_clk          ),
        .rst              (img_rst          )
    );

     //hp3 wr -->not use
     //assign hp.awaddr = 32'd0;
     //assign hp.awvalid = 1'b0;
     //assign hp.wdata = 64'd0;
     //assign hp.wvalid = 1'b0;

endmodule