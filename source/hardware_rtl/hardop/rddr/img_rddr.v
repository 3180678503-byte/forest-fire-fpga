//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : img_rddr.v
// Author        : Luo Wei
// Project       : NB2138
// Create Date   : 2021.09.07
// Description   :
// -
// -
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
//ICN : input channel number
//SCN : shift channel number
//HP_NUM: number of HP splicing
module img_rddr #(parameter AS=64,ICN=3,SCN=3,HP_NUM=3,IEDW=8)(
    input       [64*HP_NUM-1 : 0]       img_rddr_data    ,
    input                               img_rddr_valid   ,
    output                              img_rddr_ready   ,
      
    output reg  [         31 : 0]       img_rddr_araddr  ,
    output reg                          img_rddr_arvalid ,
    input                               img_rddr_arready ,
     
    output reg                          img_rddr_done    ,
    input                               img_rddr_start   ,
    input       [         31 : 0]       img_rddr_base    ,
    input       [         23 : 0]       img_rddr_len     , 
    input       [          4 : 0]       img_last_sft     , // w*h - 21*(len-1)
    input       [          6 : 0]       channel_each     ,
    input       [          6 : 0]       channel_times    ,    
      
    output reg  [ IEDW*SCN-1 : 0]       img_data         , // max 8 channel data
    output reg                          img_dv           ,
    input                               img_ready        ,
    output      [          3 : 0]       img_rddr_st      ,
    output                              img_rdata_end    ,

    input                               clk              ,
    input                               rst
);

reg        [        23 : 0]       img_rddr_cnt    ;  
reg        [        23 : 0]       img_rdata_cnt   ;
wire                              img_rddr_end    ;
//wire                              img_rdata_end   ;
reg                               img_running     ;
reg        [         9 : 0]       wait_cnt        ;
reg                               rddr_done_alrdy ;

wire                              din_last        ;
reg                               dout_last       ;
wire       [ 64*HP_NUM : 0]       fifo_din        ;
wire       [ 64*HP_NUM : 0]       fifo_dout       ;
wire                              fifo_rd         ;
wire                              fifo_full       ;
wire                              fifo_empty      ;
wire       [         4 : 0]       fifo_dcnt       ;
wire       [         5 : 0]       fifo_acnt       ;  // all cnt
wire       [         1 : 0]       fifo_err        ;
reg        [64*HP_NUM-1: 0]       sft_data        ;
    
reg         [        6 : 0]       sft_data_bit    ;  //1---8bit  2---16bit  ... 
wire                              sft_do          ;
wire                              sft_end         ;
reg        [         6 : 0]       sft_cnt         ;
reg        [         6 : 0]       pcnt            ; //processing cnt
wire       [         6 : 0]       sft_total       ;
reg                               sft_busy        ;
wire                              img_ack         ;
wire                              rddr_req_enable ;
wire                              img_rddr_ack    ;
wire                              fifo_wr         ;
wire                              img_rdata_ack   ;
reg        [         4 : 0]       img_sft         ; // w*h - 21*(len-1)

assign img_rddr_st = {img_running, rddr_done_alrdy};

assign img_rddr_ack = img_rddr_arvalid & img_rddr_arready;
assign img_rdata_ack = img_rddr_valid & img_rddr_ready;

assign img_rddr_ready = ~fifo_full;
always@(posedge clk) begin
    if(rst)
        img_running <= 1'b0;
    else if(img_rddr_start)
        img_running <= 1'b1;
    else if(img_rddr_end)
        img_running <= 1'b0;
end

always@(posedge clk) begin
    if(rst)
        wait_cnt <= 0;
    else if(img_rddr_start)
        wait_cnt <= 0;
    else if(img_rddr_ack & ~img_rdata_ack)
        wait_cnt <= wait_cnt + 10'b1;
    else if(~img_rddr_ack & img_rdata_ack)
        wait_cnt <= wait_cnt - 10'd3;
    else if(img_rddr_ack & img_rdata_ack)
        wait_cnt <= wait_cnt - 10'd2;
end

assign fifo_acnt = fifo_dcnt + (wait_cnt>>1);
assign rddr_req_enable =(img_rddr_start | img_running) && ~img_rddr_end && fifo_acnt < 16;

always@(posedge clk) begin
    if(rst)
        img_rddr_arvalid <= 1'b0;
    else if(rddr_req_enable)
        img_rddr_arvalid <= 1'b1;
    else
        img_rddr_arvalid <= 1'b0;
end

always@(posedge clk) begin
    if(rst)
        img_rddr_araddr <= 0;
    else if(img_rddr_start)
        img_rddr_araddr <= img_rddr_base;
    else if(img_rddr_ack)
        img_rddr_araddr <= img_rddr_araddr + AS;
end

always@(posedge clk) begin
    if(rst)
        img_rddr_cnt <= 24'b0;
    else if(img_rddr_start)
        img_rddr_cnt <= 24'b1;
    else if(img_rddr_ack)
        img_rddr_cnt <= img_rddr_cnt + 1'b1;
end

assign img_rddr_end = (img_rddr_cnt == img_rddr_len && img_rddr_ack) || (img_rddr_len == 'd0);

always@(posedge clk) begin
    if(rst)
        img_rdata_cnt <= 24'b0;
    else if(img_rddr_start)
        img_rdata_cnt <= 24'b1;
    else if(img_rdata_ack)
        img_rdata_cnt <= img_rdata_cnt + 1'b1;
end
assign img_rdata_end = (img_rdata_cnt == img_rddr_len/HP_NUM) && img_rdata_ack;

always@(posedge clk) begin
    if(rst)
        img_rddr_done <= 1'b0;
    else
        img_rddr_done <= img_rddr_end;
end

always@(posedge clk) begin
    if(rst)
        rddr_done_alrdy <= 1'b0;
    else if(img_rddr_end)
        rddr_done_alrdy <= 1'b1;
    else if(img_rddr_start)
        rddr_done_alrdy <= 1'b0;
end

assign fifo_din = {din_last, img_rddr_data};
assign fifo_wr  = img_rdata_ack & (~fifo_full);
assign din_last = rddr_done_alrdy && wait_cnt==HP_NUM && img_rdata_ack;

img_mini_fifo mini_fifo_u0 (
  .clk       (clk        ),              // input wire clk
  .srst      (rst        ),              // input wire srst
  .din       (fifo_din   ),              // input wire [192 : 0] din
  .wr_en     (fifo_wr    ),              // input wire wr_en
  .rd_en     (fifo_rd    ),              // input wire rd_en
  .dout      (fifo_dout  ),              // output wire [192 : 0] dout
  .full      (fifo_full  ),              // output wire full
  .empty     (fifo_empty ),              // output wire empty
  .data_count(fifo_dcnt  )               // output wire [4 : 0] data_count
);

always@(*) begin
    case(channel_each) 
         0        : img_sft  <=  5'd0;
         1        : img_sft  <=  5'd24;
         2        : img_sft  <=  5'd12;
         3        : img_sft  <=  5'd8;
         4        : img_sft  <=  5'd6;
         default  : img_sft  <=  5'd0;
    endcase
end

assign sft_total    = dout_last ? img_last_sft : img_sft; //##
assign sft_end      = sft_cnt==sft_total;
assign img_ack      = img_dv & img_ready;
assign sft_do       = img_ack & ~sft_end;
assign fifo_rd      = (~fifo_empty) && (~sft_busy | (img_ack & sft_end));

always@(posedge clk) begin
    if(rst)
        sft_busy <= 1'b0;
    else if(fifo_rd)
        sft_busy <= 1'b1;
    else if(sft_end && img_ack)
        sft_busy <= 1'b0;
end

always@(posedge clk) begin
    if(rst)
        dout_last <= 1'b0;
    else if(fifo_rd)
        dout_last <= fifo_dout[64*HP_NUM];
end

always@(*) begin
    case(channel_each) 
         0        : sft_data_bit  <=  7'd0;
         1        : sft_data_bit  <=  7'd8;
         2        : sft_data_bit  <=  7'd16;
         3        : sft_data_bit  <=  7'd24;
         4        : sft_data_bit  <=  7'd32;
         default  : sft_data_bit  <=  7'd0;
    endcase
end

always@(posedge clk) begin
    if(rst)
        sft_data <= 'b0;
    else if(fifo_rd)
        sft_data <= fifo_dout[64*HP_NUM-1:0];
    else if(sft_do)
        sft_data <= sft_data >> sft_data_bit;
end

always@(posedge clk) begin
    if(rst)
        sft_cnt <= 7'd1;
    else if(fifo_rd)
        sft_cnt <= 7'd1;
    else if(sft_do)
        sft_cnt <= sft_cnt + 1'b1;
end

always@(posedge clk) begin
    if(rst)
        pcnt <= 7'd1;
    else if(img_rddr_start || (pcnt == channel_times))
        pcnt <= 7'd1;
    else if(img_dv && img_ready)
        pcnt <= pcnt + 1'b1;
end

always@(posedge clk) begin
    if(rst)
        img_dv <= 1'b0;
    else if(fifo_rd | sft_do)
        img_dv <= 1'b1;
    else if(img_ready)
        img_dv <= 1'b0;
end

always@(*) begin
    case(channel_each) 
         0        : img_data  <=  32'd0;
         1        : img_data  <=  {24'd0,sft_data[7:0]};
         2        : img_data  <=  {16'd0,sft_data[15:0]};
         3        : img_data  <=  {8'd0,sft_data[23:0]};
         4        : img_data  <=  sft_data[31:0];
         default  : img_data  <=  32'd0;
    endcase
end

endmodule
