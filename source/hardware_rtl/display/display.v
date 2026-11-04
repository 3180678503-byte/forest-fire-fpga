//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : display.v
// Author        : WangYinglin 
// Project       : 
// Create Date   : 2022.02.18
// Description   : 
// 
//-----------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module display(
    input                       gclk_50MHz          ,
    input                       cam_clk             ,

    input                       cmos_vsync_out      ,
    input                       cmos_href_out       ,
    input      [23 : 0]         cmos_db_out         ,

    output                      cam_clk_use         ,
    output                      reset_cam_clk       ,

	inout                       si5368_i2c_scl_io   , 
    inout                       si5368_i2c_sda_io   , 
    output                      si5368_rst_n        ,
	// hdmi
	inout                       hdmi_i2c_scl_io     , 
    inout                       hdmi_i2c_sda_io     , 
    output                      hdmi_out_clk        , 
    output     [23 : 0]         hdmi_out_data       , 
    output                      hdmi_out_de         , 
    output                      hdmi_out_hs         , 
    output                      hdmi_out_vs         , 
    output     [ 0 : 0]         hdmi_rstn_tri_o     ,    
    // master axi interface, connect HP
	input                       m00_axi_aclk        ,
    input                       m00_axi_aresetn     ,
    output     [ 3 : 0]         m00_axi_awid        ,
    output     [31 : 0]         m00_axi_awaddr      ,
    output     [ 7 : 0]         m00_axi_awlen       ,
    output     [ 2 : 0]         m00_axi_awsize      ,
    output     [ 1 : 0]         m00_axi_awburst     ,       
    output                      m00_axi_awlock      ,   
    output     [ 3 : 0]         m00_axi_awcache     ,  
    output     [ 2 : 0]         m00_axi_awprot      ,   
    output     [ 3 : 0]         m00_axi_awqos       ,    
    output     [ 0 : 0]         m00_axi_awuser      ,  
    output                      m00_axi_awvalid     ,
    input                       m00_axi_awready     ,    

    output     [63 : 0]         m00_axi_wdata       ,
    output     [ 7 : 0]         m00_axi_wstrb       ,
    output                      m00_axi_wlast       ,
    output                      m00_axi_wuser       ,
    output                      m00_axi_wvalid      ,
    input                       m00_axi_wready      ,
    
    input                       m00_axi_bid         ,
    input      [ 1 : 0]         m00_axi_bresp       ,
    input                       m00_axi_buser       ,
    input                       m00_axi_bvalid      ,
    output                      m00_axi_bready      ,
    
    output                      m00_axi_arid        ,
    output     [31 : 0]         m00_axi_araddr      ,
    output     [ 7 : 0]         m00_axi_arlen       ,
    output     [ 2 : 0]         m00_axi_arsize      ,
    output     [ 1 : 0]         m00_axi_arburst     ,
    output     [ 1 : 0]         m00_axi_arlock      ,
    output     [ 3 : 0]         m00_axi_arcache     ,
    output     [ 2 : 0]         m00_axi_arprot      ,
    output     [ 3 : 0]         m00_axi_arqos       ,
    output                      m00_axi_aruser      ,
    output                      m00_axi_arvalid     ,
    input                       m00_axi_arready     ,
    
    input                       m00_axi_rid         ,
    input      [63 : 0]         m00_axi_rdata       ,
    input      [ 1 : 0]         m00_axi_rresp       ,
    input                       m00_axi_rlast       ,
    input                       m00_axi_ruser       ,
    input                       m00_axi_rvalid      ,
    output                      m00_axi_rready      ,   
    
    //ps resize
    input      [15 : 0]         ps_x0_pos           ,
    input      [15 : 0]         ps_y0_pos           ,
    input      [15 : 0]         ps_x1_pos           ,
    input      [15 : 0]         ps_y1_pos           ,
    input      [15 : 0]         ps_x_leng           ,
    input      [15 : 0]         ps_y_leng           ,
    input      [ 3 : 0]         ps_hstride          ,
    input      [ 3 : 0]         ps_vstride          ,		
    input      [31 : 0]         write_ps_size       ,


    input      [ 31: 0]         camera_wr_addr      ,
    input      [ 31: 0]         camera_rd_addr      ,
    output                      wr_wfifo_err        ,
    output                      rd_rfifo_err        ,
    output                      wr_done_pulse       ,

    input	   [ 7 : 0]	        dip_switches        ,
    output     [ 1 : 0]         ch0_write_addr_index,
    output     [ 1 : 0]         ch0_read_addr_index          
);

    parameter MEM_DATA_BITS = 64; 
    parameter ADDR_BITS     = 27; 
    parameter BUSRT_BITS    = 10; 

    wire                                wr_burst_data_req       ;
    wire                                wr_burst_finish         ;
    wire                                rd_burst_finish         ;
    wire                                rd_burst_req            ;
    wire                                wr_burst_req            ;
    wire    [BUSRT_BITS - 1    : 0]     rd_burst_len            ;
    wire    [BUSRT_BITS - 1    : 0]     wr_burst_len            ;
    wire    [ ADDR_BITS - 1    : 0]     rd_burst_addr           ;
    wire    [ ADDR_BITS - 1    : 0]     wr_burst_addr           ;
    wire                                rd_burst_data_valid     ;
    wire    [MEM_DATA_BITS - 1 : 0]     rd_burst_data           ;
    wire    [MEM_DATA_BITS - 1 : 0]     wr_burst_data           ;
    
    wire                                ch0_wr_burst_data_req   ;
    wire                                ch0_wr_burst_finish     ;
    wire                                ch0_rd_burst_finish     ;
    wire                                ch0_rd_burst_req        ;
    wire                                ch0_wr_burst_req        ;
    wire    [BUSRT_BITS - 1    : 0]     ch0_rd_burst_len        ;
    wire    [BUSRT_BITS - 1    : 0]     ch0_wr_burst_len        ;
    wire    [ ADDR_BITS - 1    : 0]     ch0_rd_burst_addr       ;
    wire    [ ADDR_BITS - 1    : 0]     ch0_wr_burst_addr       ;
    wire                                ch0_rd_burst_data_valid ;
    wire    [MEM_DATA_BITS - 1 : 0]     ch0_rd_burst_data       ;
    wire    [MEM_DATA_BITS - 1 : 0]     ch0_wr_burst_data       ;
    wire                                ch0_read_req            ;
    wire                                ch0_read_req_ack        ;
    wire                                ch0_read_en             ;
    wire                   [15 : 0]     ch0_read_data           ;
    wire                                ch0_write_en            ;
    wire                   [15 : 0]     ch0_write_data          ;
    wire                                ch0_write_req           ;
    wire                                ch0_write_req_ack       ;
    // hdmi part                                                 
    wire                                hdmi_hs                 ;
    wire                                hdmi_vs                 ;
    wire                                hdmi_de                 ;
    wire                   [7  : 0]     hdmi_r                  ;
    wire                   [7  : 0]     hdmi_g                  ;
    wire                   [7  : 0]     hdmi_b                  ;
    wire                   [9  : 0]     hdmi_lut_index          ;
    wire                   [31 : 0]     hdmi_lut_data           ;

    wire                   [9  : 0]     si5368_lut_index        ;
    wire                   [31 : 0]     si5368_lut_data         ;    
   // colorbar
    wire                                color_bar_hs            ;
    wire                                color_bar_vs            ;
    wire                                color_bar_de            ;
    wire                   [ 7 : 0]     color_bar_r             ;
    wire                   [ 7 : 0]     color_bar_g             ;
    wire                   [ 7 : 0]     color_bar_b             ; 
    // others
    wire                                gclk_100MHz             ;
    wire                                fclk_locked             ;
    wire                                reset_100mhz            ;
    wire                                ch0_read_req_sync       ;
    wire                                ch0_write_req_sync      ;
    wire                                ch0_write_req_ack_sync  ;
    wire                                ch0_read_req_ack_sync   ;
    wire                                wfifo_empty             ;
    wire                                rfifo_full              ; 
    wire                                hs                      ;
    wire                                vs                      ;
    wire                                de                      ;  
    wire                   [15 : 0]     vout_data               ;
    wire                                pll_locked_cam          ;

    wire                                cam_clk_use_7425        ;
    wire                                cam_clk_use_1485        ;
    wire                                cam_clk_use_297         ;
    wire                                gclk_74M25Hz            ;
    wire                                write_finish            ;
    reg                                 wr_done_req             ;
    wire                                wr_done_ack             ;


    wire        resize_href ;
    wire        resize_vsync;
    wire [15:0] resize_data ;
    wire        cmos_vsync_out_pos;
    reg         cmos_vsync_out_d1;

    

    reg   [15 : 0]                      ps_x0_pos_use; 
    reg   [15 : 0]                      ps_y0_pos_use; 
    reg   [15 : 0]                      ps_x1_pos_use; 
    reg   [15 : 0]                      ps_y1_pos_use; 
    reg   [15 : 0]                      ps_x_leng_use; 
    reg   [15 : 0]                      ps_y_leng_use; 
    reg   [ 3 : 0]                      ps_hstride_use;
    reg   [ 3 : 0]                      ps_vstride_use;
    reg   [31 :0 ]                      write_ps_size_use;

    clk_gen_cam u0 (
        .clk_in1                (gclk_50MHz             ), 
        .clk_out1               (gclk_100MHz            ),
        .clk_out2               (gclk_74M25Hz           ),
        .reset                  (1'b0                   ),
        .locked                 (fclk_locked            )
    );
    
    cmos_clkgen cmos_clkgen_u0
    (
      .clk_in1                  (cam_clk                ),
      .clk_out1                 (cam_clk_use_7425            ),
      .clk_out2                 (cam_clk_use_297            ),
      .clk_out3                 (cam_clk_use_1485            ),
      .locked                   (pll_locked_cam         )
    );

    //assign cam_clk_use = cam_clk_use_7425;
    assign cam_clk_use = cam_clk_use_1485;
    //assign cam_clk_use = gclk_74M25Hz;
    

    async_to_sync_reset async_reset_100MHz(
        .async_reset            (~fclk_locked           ),
        .clk                    (gclk_100MHz            ),
        .sync_reset             (reset_100mhz           )
    );      

    async_to_sync_reset a2sync_reset_cam_clk(
    	.async_reset(~fclk_locked),
    	.clk (cam_clk_use),
    	.sync_reset(reset_cam_clk)
    );
    
    //I2C master controller
    i2c_config i2c_config_si5368(
    	.rst                    (reset_100mhz           ),
    	.clk                    (gclk_100MHz            ),
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

    //I2C master controller
    i2c_config i2c_config_hdmi(
    	.rst                    (reset_100mhz           ),
    	.clk                    (gclk_100MHz            ),
    	.clk_div_cnt            (16'd499                ),
    	.i2c_addr_2byte         (1'b0                   ),
    	.reg_file_index         (hdmi_lut_index         ),
    	.reg_device_addr        (hdmi_lut_data[31:24]   ),
    	.reg_file_addr          (hdmi_lut_data[23:8]    ),
    	.reg_file_data          (hdmi_lut_data[7:0]     ),
    	.config_error           (                       ),
    	.config_done            (                       ),
    	.i2c_scl                (hdmi_i2c_scl_io        ),
    	.i2c_sda                (hdmi_i2c_sda_io        )
    );

    //configure look-up table
    lut_sil9134 lut_sil9134_m0(
    	.lut_index              (hdmi_lut_index         ),
    	.lut_data               (hdmi_lut_data          )
    ); 
     

    always @(posedge cam_clk_use) begin
        if(reset_cam_clk == 1'b1)
            cmos_vsync_out_d1 <= 1'b0;
        else
            cmos_vsync_out_d1 <= cmos_vsync_out;
    end
    assign cmos_vsync_out_pos = cmos_vsync_out & (~cmos_vsync_out_d1);

    always @(posedge cam_clk_use) begin
        if(reset_cam_clk == 1'b1) begin
            ps_x0_pos_use  <= 0 ;
            ps_y0_pos_use  <= 0 ;
            ps_x1_pos_use  <= 0 ;
            ps_y1_pos_use  <= 0 ;
            ps_x_leng_use  <= 0 ;
            ps_y_leng_use  <= 0 ;
            ps_hstride_use <= 0 ;  
            ps_vstride_use <= 0 ;
            write_ps_size_use <= 0;  
        end
        else if (cmos_vsync_out_pos) begin
            ps_x0_pos_use  <= ps_x0_pos  ;
            ps_y0_pos_use  <= ps_y0_pos  ;
            ps_x1_pos_use  <= ps_x1_pos  ;
            ps_y1_pos_use  <= ps_y1_pos  ;
            ps_x_leng_use  <= ps_x_leng  ;
            ps_y_leng_use  <= ps_y_leng  ;
            ps_hstride_use <= ps_hstride ;
            ps_vstride_use <= ps_vstride ;
            write_ps_size_use <= write_ps_size;
        end        
    end
    
    cmos_resize cmos_resize_u0(
        .cmos1_pclk            (cam_clk_use         ),
        .reset_cmos1_pclk      (reset_cam_clk       ),
        .dvp_href              (cmos_href_out       ),
        .dvp_vsync             (cmos_vsync_out_pos  ),
        .dvp_data              ({cmos_db_out[23:19],cmos_db_out[15:10],cmos_db_out[7:3]} ),
        .x0_pos                (ps_x0_pos_use       ),
        .y0_pos                (ps_y0_pos_use       ),
        .x1_pos                (ps_x1_pos_use       ),
        .y1_pos                (ps_y1_pos_use       ),
        .x_leng                (ps_x_leng_use       ),
        .y_leng                (ps_y_leng_use       ),
        .hstride               (ps_hstride_use      ),
        .vstride               (ps_vstride_use      ),
        .resize_href           (resize_href         ),
        .resize_vsync          (resize_vsync        ),
        .resize_data           (resize_data         )
    );


    assign ch0_write_en    = resize_href  ;
    assign ch0_write_data  = resize_data  ;
    
    //assign ch0_write_en    = cmos_href_out                        ;
    //assign ch0_write_data  = {cmos_db_out[23:19],cmos_db_out[15:10],cmos_db_out[7:3]};

    //video frame data read-write control
    frame_read_write frame_read_write_m0(
        .rst                        (~m00_axi_aresetn         ),
        .mem_clk                    (m00_axi_aclk             ),
        .rd_burst_req               (ch0_rd_burst_req         ),
        .rd_burst_len               (ch0_rd_burst_len         ),
        .rd_burst_addr              (ch0_rd_burst_addr        ),
        .rd_burst_data_valid        (ch0_rd_burst_data_valid  ),
        .rd_burst_data              (ch0_rd_burst_data        ),
        .rd_burst_finish            (ch0_rd_burst_finish      ),
        .read_clk                   (cam_clk_use              ),
        .read_req                   (ch0_read_req_sync        ),
        .read_req_ack               (ch0_read_req_ack         ),
        .read_finish                (                         ),
        .read_addr_0                (camera_rd_addr[26:0]     ), 
        .read_addr_1                (camera_rd_addr[26:0]     ), //large enough address space for one frame of video
        .read_addr_2                (camera_rd_addr[26:0]     ), 
        .read_addr_3                (camera_rd_addr[26:0]     ), 
        .read_addr_index            (ch0_read_addr_index      ),
        .read_len                   (27'd518400               ), // frame size  1920 * 1080 * 16 / 64
        .read_en                    (ch0_read_en              ),
        .read_data                  (ch0_read_data            ),

        .wr_burst_req               (ch0_wr_burst_req         ),
        .wr_burst_len               (ch0_wr_burst_len         ),
        .wr_burst_addr              (ch0_wr_burst_addr        ),
        .wr_burst_data_req          (ch0_wr_burst_data_req    ),
        .wr_burst_data              (ch0_wr_burst_data        ),
        .wr_burst_finish            (ch0_wr_burst_finish      ),
        .write_clk                  (cam_clk_use              ),
        .write_req                  (ch0_write_req_sync       ),
        .write_req_ack              (ch0_write_req_ack        ),
        .write_finish               (write_finish             ),
        .write_addr_0               (camera_wr_addr[26:0]     ),
        .write_addr_1               (camera_wr_addr[26:0]     ),
        .write_addr_2               (camera_wr_addr[26:0]     ), 
        .write_addr_3               (camera_wr_addr[26:0]     ), 
        .write_addr_index           (ch0_write_addr_index     ),
        .write_len                  (write_ps_size_use        ),	//27'd518400 
        .write_en                   (ch0_write_en             ),
        .write_data                 (ch0_write_data           ),
        .wr_wfifo_err               (wr_wfifo_err             ),
        .rd_rfifo_err               (rd_rfifo_err             ),
        .wfifo_empty                (wfifo_empty              ),
        .rfifo_full                 (rfifo_full               )
    );    

    //CMOS sensor writes the request and generates the read and write address index
    cmos_write_req_gen cmos_write_req_gen_m0(
    	.rst                        (reset_cam_clk            ),
    	.pclk                       (cam_clk_use                  ),
    	.m00_axi_aclk               (m00_axi_aclk             ),	
    	.cmos_vsync                 (cmos_vsync_out           ),
    	.write_req                  (ch0_write_req            ),
    	.write_addr_index_sync      (ch0_write_addr_index     ),
    	.read_addr_index_sync       (ch0_read_addr_index      ),
    	.write_req_ack              (ch0_write_req_ack_sync   )
    );
    
    //video output timing generator 
    color_bar color_bar_m0(
    	.clk                        (cam_clk_use              ),
    	.rst                        (reset_cam_clk            ),
    	.hs                         (color_bar_hs             ),
    	.vs                         (color_bar_vs             ),
    	.de                         (color_bar_de             ),
    	.rgb_r                      (color_bar_r              ),
    	.rgb_g                      (color_bar_g              ),
    	.rgb_b                      (color_bar_b              )
    );
    
    //generate a frame read data request
    video_rect_read_data video_rect_read_data_m0(
    	.video_clk                  (cam_clk_use                  ),
    	.rst                        (reset_cam_clk            ),
    	.video_left_offset          (12'd0                    ),
    	.video_top_offset           (12'd0                    ),
    	.video_width                (12'd1920                 ),
    	.video_height	            (12'd1080                 ),	
    	.read_req                   (ch0_read_req             ),
    	.read_req_ack               (ch0_read_req_ack_sync    ),
    	.read_en                    (ch0_read_en              ),
    	.read_data                  (ch0_read_data            ),
    	.timing_hs                  (color_bar_hs             ),
    	.timing_vs                  (color_bar_vs             ),
    	.timing_de                  (color_bar_de             ),
    	.timing_data 	            (16'd0                    ),
    	.hs                         (hs                       ),
    	.vs                         (vs                       ),
    	.de                         (de                       ),
    	.vout_data                  (vout_data                )
    );

    assign rd_burst_req            = ch0_rd_burst_req       ;
    assign rd_burst_len            = ch0_rd_burst_len       ;
    assign rd_burst_addr           = ch0_rd_burst_addr      ;
    
    assign ch0_rd_burst_data_valid = rd_burst_data_valid                                                                     ;
    assign ch0_rd_burst_data       = {rd_burst_data[15:0], rd_burst_data[31:16], rd_burst_data[47:32], rd_burst_data[63:48]} ;           
    assign ch0_rd_burst_finish     = rd_burst_finish                                                                         ;
   
	assign wr_burst_req            =  ch0_wr_burst_req      ;
    assign wr_burst_len            =  ch0_wr_burst_len      ;
    assign wr_burst_addr           =  ch0_wr_burst_addr     ;
    assign ch0_wr_burst_data_req   =  wr_burst_data_req     ;
    //assign wr_burst_data           =  {ch0_wr_burst_data[15:0], ch0_wr_burst_data[31:16], ch0_wr_burst_data[47:32], ch0_wr_burst_data[63:48]};  
    assign wr_burst_data = {ch0_wr_burst_data[31:0], ch0_wr_burst_data[63:32]};
    assign ch0_wr_burst_finish     =  wr_burst_finish       ; 

    aq_axi_master u_aq_axi_master(
        .ARESETN                    (m00_axi_aresetn          ),
        .ACLK                       (m00_axi_aclk             ),
        .M_AXI_AWID                 (m00_axi_awid             ),
        .M_AXI_AWADDR               (m00_axi_awaddr           ),
        .M_AXI_AWLEN                (m00_axi_awlen            ),
        .M_AXI_AWSIZE               (m00_axi_awsize           ),
        .M_AXI_AWBURST              (m00_axi_awburst          ),
        .M_AXI_AWLOCK               (m00_axi_awlock           ),
        .M_AXI_AWCACHE              (m00_axi_awcache          ),
        .M_AXI_AWPROT               (m00_axi_awprot           ),
        .M_AXI_AWQOS                (m00_axi_awqos            ),
        .M_AXI_AWUSER               (m00_axi_awuser           ),
        .M_AXI_AWVALID              (m00_axi_awvalid          ),
        .M_AXI_AWREADY              (m00_axi_awready          ),
        .M_AXI_WDATA                (m00_axi_wdata            ),
        .M_AXI_WSTRB                (m00_axi_wstrb            ),
        .M_AXI_WLAST                (m00_axi_wlast            ),
        .M_AXI_WUSER                (m00_axi_wuser            ),
        .M_AXI_WVALID               (m00_axi_wvalid           ),
        .M_AXI_WREADY               (m00_axi_wready           ),
        .M_AXI_BID                  (m00_axi_bid              ),
        .M_AXI_BRESP                (m00_axi_bresp            ),
        .M_AXI_BUSER                (m00_axi_buser            ),
        .M_AXI_BVALID               (m00_axi_bvalid           ),
        .M_AXI_BREADY               (m00_axi_bready           ),
        .M_AXI_ARID                 (m00_axi_arid             ),
        .M_AXI_ARADDR               (m00_axi_araddr           ),
        .M_AXI_ARLEN                (m00_axi_arlen            ),
        .M_AXI_ARSIZE               (m00_axi_arsize           ),
        .M_AXI_ARBURST              (m00_axi_arburst          ),
        .M_AXI_ARLOCK               (m00_axi_arlock           ),
        .M_AXI_ARCACHE              (m00_axi_arcache          ),
        .M_AXI_ARPROT               (m00_axi_arprot           ),
        .M_AXI_ARQOS                (m00_axi_arqos            ),
        .M_AXI_ARUSER               (m00_axi_aruser           ),
        .M_AXI_ARVALID              (m00_axi_arvalid          ),
        .M_AXI_ARREADY              (m00_axi_arready          ),
        .M_AXI_RID                  (m00_axi_rid              ),
        .M_AXI_RDATA                (m00_axi_rdata            ),
        .M_AXI_RRESP                (m00_axi_rresp            ),
        .M_AXI_RLAST                (m00_axi_rlast            ),
        .M_AXI_RUSER                (m00_axi_ruser            ),
        .M_AXI_RVALID               (m00_axi_rvalid           ),
        .M_AXI_RREADY               (m00_axi_rready           ),
        .MASTER_RST                 (1'b0                     ),
        .WR_START                   (wr_burst_req             ),
        .WR_ADRS                    ({wr_burst_addr,3'd0}     ),
        .WR_LEN                     ({wr_burst_len,3'd0}      ),
        .WR_READY                   (                         ),
        .WR_FIFO_RE                 (wr_burst_data_req        ),
        .WR_FIFO_EMPTY              (1'b0                     ),
        .WR_FIFO_AEMPTY             (1'b0                     ),
        .WR_FIFO_DATA               (wr_burst_data            ),
        .WR_DONE                    (wr_burst_finish          ),
        .RD_START                   (rd_burst_req             ),
        .RD_ADRS                    ({rd_burst_addr,3'd0}     ),
        .RD_LEN                     ({rd_burst_len,3'd0}      ),
        .RD_READY                   (                         ),
        .RD_FIFO_WE                 (rd_burst_data_valid      ),
        .RD_FIFO_FULL               (rfifo_full               ),
        .RD_FIFO_AFULL              (1'b0                     ),
        .RD_FIFO_DATA               (rd_burst_data            ),
        .RD_DONE                    (rd_burst_finish          ),
        .DEBUG                      (                         )
    );
    
    assign hdmi_rstn_tri_o = ~reset_100mhz                        ;
	assign hdmi_out_clk    = cam_clk_use                          ;
	assign hdmi_out_de     = de                                   ;
    assign hdmi_out_hs     = hs                                   ;
    assign hdmi_out_vs     = vs                                   ;
	assign hdmi_r          = {vout_data[15:11],vout_data[13:11]}  ;
    assign hdmi_g          = {vout_data[10: 5],vout_data[ 6: 5]}  ;
    assign hdmi_b          = {vout_data[ 4: 0],vout_data[ 2: 0]}  ;    
    assign hdmi_out_data   = dip_switches[0] ? {hdmi_r, hdmi_g, hdmi_b} : {color_bar_r, color_bar_g, color_bar_b}; 
    //assign hdmi_out_data   = {8'hff, 8'h00, 8'h00}; 


    always @(posedge m00_axi_aclk) begin
        if(~m00_axi_aresetn)
             wr_done_req <= 1'b0;
        else if (wr_done_ack)
            wr_done_req <= 1'b0;
        else if (write_finish)     
             wr_done_req <= 1'b1;
    end


    bridge_s bridge_s_u1(
        .clka      (m00_axi_aclk        ),
        .clkb      (cam_clk_use         ),
        .rsta      (~m00_axi_aresetn    ),
        .rstb      (~m00_axi_aresetn    ),
        .a_req     (wr_done_req         ),
        .a_req_clr (wr_done_ack         ),
        .b_en      (wr_done_pulse       )
         );



    level_cross level_cross_u0(
        .a2         (ch0_write_req_sync     ),
        .clk2       (m00_axi_aclk           ),
        .rst2       (~m00_axi_aresetn       ),
  
        .a1         (ch0_write_req          ),
        .clk1       (cam_clk_use                ),
        .rst1       (reset_cam_clk          )
    );   

    level_cross level_cross_u1(
        .a2         (ch0_write_req_ack_sync ),
        .clk2       (cam_clk_use                ),
        .rst2       (reset_cam_clk          ),

        .a1         (ch0_write_req_ack      ),
        .clk1       (m00_axi_aclk           ),
        .rst1       (~m00_axi_aresetn       )
    );


    level_cross level_cross_u2(
        .a2         (ch0_read_req_sync      ),
        .clk2       (m00_axi_aclk           ),
        .rst2       (~m00_axi_aresetn       ),
    
        .a1         (ch0_read_req           ),
        .clk1       (cam_clk_use                ),
        .rst1       (reset_cam_clk          )
    );

    level_cross level_cross_u3(
        .a2         (ch0_read_req_ack_sync  ),
        .clk2       (cam_clk_use                ),
        .rst2       (reset_cam_clk          ),

        .a1         (ch0_read_req_ack       ),
        .clk1       (m00_axi_aclk           ),
        .rst1       (~m00_axi_aresetn       )
    );

endmodule
