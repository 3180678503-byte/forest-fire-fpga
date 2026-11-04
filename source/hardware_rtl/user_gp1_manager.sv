//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : user_gp1_manager.sv
// Author        : zhaoxiaodong
// Project       :
// Create Date   : 2020.02.07
// Description   : 
//
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
// 1.01    2022.7.25    luowei       parameter base
//==============================================================================

module user_gp1_manager #(parameter GP1_BASE=32'h80000000)(
    mna_gp_ww_itf.slave       gpx                ,    
    mna_gp_ww_itf.master      cam_gp1_s00        ,
    mna_gp_ww_itf.master      cam_gp1_s01        ,
    mna_gp_ww_itf.master      cam_gp1_s02        ,
    mna_gp_ww_itf.master      cam_gp1_s03        ,

    input                     gpx_rst            ,
    input                     gpx_clk
);

//localparam GP1_SPLIT_BASE = GP1_BASE | 32'h00000800;
localparam GP1_SPLIT_BASE = GP1_BASE | 32'h00080000;

mna_gp_ww_itf m00_gpx();
mna_gp_ww_itf m04_gpx();
mna_gp_ww_itf m4_gpx();
mna_gp_ww_itf m6_gpx();

/*

                                          GP1_BASE(default:0x8000_0000)
                                              gpx
                              _________________|_________________     
                             /                                   \                         
*512*                   0x8000_0000                          0x8008_0000
                          m00_gpx                               m04_gpx
                  __________|__________                 __________|__________                              
                 /                     \               /                     \                       
*256*       0x8000_0000            0x8004_0000    0x8008_0000            0x800c_0000  
                 |                      |              |                      |
            cam_gp1_s00            cam_gp1_s01     cam_gp1_s02            cam_gp1_s03
              
*/

gpx_ww_split #(.BASE(GP1_BASE),.ASP(19),.ERR(32'hB1AAAAAA)) gpx_ww_split_u0(
        .gpx     (gpx             )  ,    
        .m00_gpx (m00_gpx.master  )  ,
        .m01_gpx (m04_gpx.master  )  ,
        .gpx_rst (gpx_rst         )  ,
        .gpx_clk (gpx_clk         )
);

gpx_ww_split #(.BASE(GP1_BASE),.ASP(18),.ERR(32'hB1BBBBBB)) gpx_ww_split_u1(
        .gpx     (m00_gpx.slave   )  ,    
        .m00_gpx (cam_gp1_s00     )  ,
        .m01_gpx (cam_gp1_s01     )  ,
        .gpx_rst (gpx_rst         )  ,
        .gpx_clk (gpx_clk         )
);

gpx_ww_split #(.BASE(GP1_SPLIT_BASE),.ASP(18),.ERR(32'hB1CCCCCC)) gpx_ww_split_u2(
        .gpx     (m04_gpx.slave   )  ,    
        .m00_gpx (cam_gp1_s02     )  ,
        .m01_gpx (cam_gp1_s03     )  ,
        .gpx_rst (gpx_rst         )  ,
        .gpx_clk (gpx_clk         )
);

gpx_RFU  #(.ERR(32'hB1DDDDDD)) gpx_RFU_u4(
        .gpx     (m4_gpx.slave    )  ,    
        .gpx_rst (gpx_rst         )  ,
        .gpx_clk (gpx_clk         )
);

gpx_RFU  #(.ERR(32'hB1EEEEEE)) gpx_RFU_u6(
        .gpx     (m6_gpx.slave    )  ,    
        .gpx_rst (gpx_rst         )  ,
        .gpx_clk (gpx_clk         )
);

endmodule
