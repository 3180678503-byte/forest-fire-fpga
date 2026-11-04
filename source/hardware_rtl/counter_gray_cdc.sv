`timescale 1ns/1ps
`default_nettype none
// For counters that change by at most one per source clock. Diagnostics only.
module counter_gray_cdc(
    input wire src_clk, src_rst,
    input wire [31:0] value,
    input wire dst_clk, dst_rst,
    output reg [31:0] sampled
);
    reg [31:0] gray;
    (* ASYNC_REG="TRUE" *) reg [31:0] sync1, sync2;
    integer k;
    reg [31:0] decoded;
    always @* begin
        decoded[31]=sync2[31];
        for(k=30;k>=0;k=k-1) decoded[k]=decoded[k+1]^sync2[k];
    end
    always @(posedge src_clk) begin
        if(src_rst) gray<=0;else gray<=value^(value>>1);
    end
    always @(posedge dst_clk) begin
        if(dst_rst) begin sync1<=0;sync2<=0;sampled<=0;end
        else begin sync1<=gray;sync2<=sync1;sampled<=decoded;end
    end
endmodule
`default_nettype wire
