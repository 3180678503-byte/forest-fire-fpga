`timescale 1ns / 1ps
`default_nettype none

module axis_frame_drop #
(
    parameter integer DATA_WIDTH = 24,
    parameter integer KEEP_EVERY_N = 4
)
(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tuser,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tuser,

    output reg                   kept_frame_start
);

localparam integer FRAME_CNT_WIDTH = KEEP_EVERY_N <= 2 ? 1 : $clog2(KEEP_EVERY_N);

reg [FRAME_CNT_WIDTH-1:0] frame_cnt_reg = {FRAME_CNT_WIDTH{1'b0}};
reg keep_frame_reg = 1'b1;

wire next_keep_frame = frame_cnt_reg == {FRAME_CNT_WIDTH{1'b0}};
wire current_keep_frame = s_axis_tuser ? next_keep_frame : keep_frame_reg;
wire input_beat = s_axis_tvalid && s_axis_tready;
wire frame_start_beat = input_beat && s_axis_tuser;

assign s_axis_tready = !enable ? 1'b1 :
                       current_keep_frame ? m_axis_tready : 1'b1;
assign m_axis_tdata = s_axis_tdata;
assign m_axis_tvalid = enable && current_keep_frame && s_axis_tvalid;
assign m_axis_tuser = s_axis_tuser;

always @(posedge clk) begin
    if (rst) begin
        frame_cnt_reg <= {FRAME_CNT_WIDTH{1'b0}};
        keep_frame_reg <= 1'b1;
        kept_frame_start <= 1'b0;
    end else begin
        kept_frame_start <= 1'b0;

        if (!enable) begin
            frame_cnt_reg <= {FRAME_CNT_WIDTH{1'b0}};
            keep_frame_reg <= 1'b1;
        end else if (frame_start_beat) begin
            keep_frame_reg <= next_keep_frame;
            kept_frame_start <= next_keep_frame;

            if (frame_cnt_reg == KEEP_EVERY_N[FRAME_CNT_WIDTH-1:0]-{{(FRAME_CNT_WIDTH-1){1'b0}}, 1'b1}) begin
                frame_cnt_reg <= {FRAME_CNT_WIDTH{1'b0}};
            end else begin
                frame_cnt_reg <= frame_cnt_reg + {{(FRAME_CNT_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule

`resetall
