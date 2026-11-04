//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : n2w_bwc_sp.v
// Author        : wyl
// Project       : NB1917
// Create Date   : 2020.01.07
// Description   :
// - n2w_bwc   : Narrow to Wide bit width converter
// - NDW       : Narrow Data width
// - WDW       : Wide Data width
// - CBW       : Counter Bit width, CBW=ceilf(log2(WDW-NDW))
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module n2w_bwc_sp #(parameter NDW=64, WDW=512, CBW=3)(
    input        [NDW-1: 0]    n2w_ndata       ,
    input                      n2w_nvalid      ,
    input                      n2w_nlast       ,
    output                     n2w_nready      ,

    output       [WDW-1: 0]    n2w_wdata       ,
    output                     n2w_wlast       ,
    output                     n2w_wvalid      ,
    input                      n2w_wready      ,

    input                      n2w_clk_rst     ,
    input                      n2w_clk
);

   localparam MULT = WDW/NDW;

// bit-width convert from narrow to wide
    (*KEEP="TRUE"*)reg   [CBW-1 : 0]       n2w_cnt       ;
    reg   [WDW-1 : 0]       n2w_reg       ;
    reg                     n2w_reg_valid ;
    reg                     n2w_reg_last  ;
    wire                    n2w_nack      ;
    wire                    n2w_wack      ;
    wire                    n2w_nack_here ;

    assign n2w_nack = n2w_nvalid & n2w_nready;
    assign n2w_wack = n2w_wvalid & n2w_wready;
    
    assign n2w_nack_here = n2w_nack | n2w_reg_last;
    
    assign n2w_wvalid = n2w_reg_valid;
    assign n2w_wdata = n2w_reg;
    assign n2w_wlast = n2w_reg_last;
    assign n2w_nready = ((~n2w_reg_valid) | n2w_wready) & ~n2w_reg_last;
      
    always @(posedge n2w_clk) begin
        if(n2w_clk_rst)
            n2w_reg_last <= 1'b0;
        else if(n2w_nack)
            n2w_reg_last <= n2w_nlast;
        else if(n2w_wack)
            n2w_reg_last <= 1'b0;
    end

    //always @(posedge n2w_clk) begin
    //    if(n2w_clk_rst)
    //        n2w_wlast <= 1'b0;
    //    else if(n2w_nack_here)
    //        n2w_wlast <= n2w_reg_last;
    //end

    always @(posedge n2w_clk) begin
        if(n2w_clk_rst)
            n2w_reg <= 0;
        else if(n2w_nack_here)
            n2w_reg <= {n2w_ndata, n2w_reg[WDW-1:NDW]};
    end

    always @(posedge n2w_clk) begin
        if(n2w_clk_rst)
            n2w_reg_valid <= 1'b0;
        else if(n2w_nack_here && n2w_cnt==(MULT-1))
            n2w_reg_valid <= 1'b1;
        else if(n2w_wack)
            n2w_reg_valid <= 1'b0;
    end

    always @(posedge n2w_clk) begin
        if(n2w_clk_rst)
            n2w_cnt <= 0;
        else if(n2w_nack_here && n2w_cnt==(MULT-1))
            n2w_cnt <= 'd0;
        else if(n2w_nack_here)
            n2w_cnt <= n2w_cnt + 1;
    end

endmodule
