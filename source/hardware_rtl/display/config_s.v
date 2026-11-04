 //==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : config_s.v
// Author        : WangYinglin 
// Project       : 
// Create Date   : 2023.02.11
// Description   : 
// 
//-----------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module config_s(
    input                       gp_clk              ,
    input                       pll_lock            ,
    input                       cam0_clk            ,
    input                       cam1_clk            ,
    input                       cam2_clk            ,
    input                       cam3_clk            ,

	output                      reset_cam0_clk      ,
    output                      reset_cam1_clk      ,
    output                      reset_cam2_clk      ,
    output                      reset_cam3_clk      ,

    inout                       si5368_i2c_scl_io   , 
    inout                       si5368_i2c_sda_io   , 
    output                      si5368_rst_n        	
);
    wire              pll_locked_cam      ;
	wire              clk_100MHz          ;
	wire              fclk_locked         ;
	wire              reset_100mhz        ;
    wire  [9  : 0]    si5368_lut_index    ;
    wire  [31 : 0]    si5368_lut_data     ; 

    /*
    clk_gen_cam u0 (
        .clk_in1              (gp_clk                 ), 
        .clk_out1             (clk_100MHz             ),
        .reset                (1'b0                   ),
        .locked               (fclk_locked            )
    );
    */
    assign fclk_locked = pll_lock;
    assign clk_100MHz = gp_clk;
    
    async_to_sync_reset a2sync_reset_cam0_clk(
    	.async_reset            (~fclk_locked         ),
    	.clk                    (cam0_clk             ),
    	.sync_reset             (reset_cam0_clk       )
    );

    async_to_sync_reset a2sync_reset_cam1_clk(
    	.async_reset            (~fclk_locked         ),
    	.clk                    (cam1_clk             ),
    	.sync_reset             (reset_cam1_clk       )
    );

    async_to_sync_reset a2sync_reset_cam2_clk(
    	.async_reset            (~fclk_locked         ),
    	.clk                    (cam2_clk             ),
    	.sync_reset             (reset_cam2_clk       )
    );

    async_to_sync_reset a2sync_reset_cam3_clk(
    	.async_reset            (~fclk_locked         ),
    	.clk                    (cam3_clk             ),
    	.sync_reset             (reset_cam3_clk       )
    );

    async_to_sync_reset async_reset_100MHz(
        .async_reset            (~fclk_locked         ),
        .clk                    (clk_100MHz           ),
        .sync_reset             (reset_100mhz         )
    ); 

    i2c_config i2c_config_si5368(
    	.rst                    (reset_100mhz           ),
    	.clk                    (clk_100MHz             ),
    	.clk_div_cnt            (16'd499                ),
    	.i2c_addr_2byte         (1'b0                   ),
    	.reg_file_index         (si5368_lut_index       ),
    	.reg_device_addr        (si5368_lut_data[31:24] ),
    	.reg_file_addr          (si5368_lut_data[23:8]  ),
    	.reg_file_data          (si5368_lut_data[7:0]   ),
    	.config_error           (                       ),
    	.config_done            (                       ),
    	.i2c_scl                (si5368_i2c_scl_io      ),
    	.i2c_sda                (si5368_i2c_sda_io      )
    );
    assign si5368_rst_n = ~reset_100mhz;

    //configure look-up table
    lut_si5368 lut_si5368_m0(
    	.lut_index              (si5368_lut_index       ),
    	.lut_data               (si5368_lut_data        )
    ); 
endmodule
