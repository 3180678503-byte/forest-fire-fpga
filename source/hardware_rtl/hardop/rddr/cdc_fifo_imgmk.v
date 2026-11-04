//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : cdc_fifo.v
// Author        : wyl
// Project       :
// Create Date   : 2021.04.12
// Description   : cdc_fifo
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module cdc_fifo_imgmk#(parameter DW=24)(
    input         [ DW-1 : 0]   wdata       ,
    input                       wvalid      ,
    output                      wready      ,

    output        [ DW-1 : 0]   rdata       ,
    output                      rvalid      ,
    input                       rready      ,

    output        [    2 : 0]   fifo_st     ,
    input                       wrst        ,
    input                       wclk        ,
    input                       rrst        ,
    input                       rclk
);

    wire                 fifo_rst         ;
    wire  [ DW-1 : 0]    fifo_din         ;
    wire  [ DW-1 : 0]    fifo_dout        ;
    wire                 fifo_wr          ;
    wire                 fifo_rd          ;
    wire                 fifo_full        ;
    wire                 fifo_pfull       ;
    wire                 fifo_empty       ;
    reg                  fifo_werr        ;

    assign fifo_rst = wrst | rrst ;
    assign fifo_din = wdata;
    assign fifo_wr  = wvalid & wready;
    assign wready   = ~fifo_pfull;

    assign fifo_rd  = ~fifo_empty & rready ;
    assign rdata    = fifo_dout ;
    assign rvalid   = ~fifo_empty ;

    assign fifo_st = {fifo_werr, fifo_empty, fifo_full};

    always@(posedge wclk)begin
        if(wrst)
            fifo_werr <= 1'b0;
        else if(fifo_full & fifo_wr)
            fifo_werr <= 1'b1;
    end

    cdc_fifo_imgmk_base cdc_fifo_imgmk_base_u0(
        .rst             (fifo_rst        ),

        .wr_clk          (wclk            ),
        .din             (fifo_din        ),
        .wr_en           (fifo_wr         ),

        .rd_clk          (rclk            ),
        .rd_en           (fifo_rd         ),
        .dout            (fifo_dout       ),

        .prog_full       (fifo_pfull      ),
        .full            (fifo_full       ),
        .empty           (fifo_empty      )
    );
endmodule
