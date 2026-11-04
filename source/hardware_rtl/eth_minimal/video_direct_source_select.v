`timescale 1ns / 1ps
`default_nettype none

module video_direct_source_select #
(
    parameter integer DATA_WIDTH = 24,
    parameter integer SDI_KEEP_EVERY_N = 6,
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer COLORBAR_PERIOD_CYCLES = FRAME_WIDTH * FRAME_HEIGHT,
    parameter integer FIFO_DEPTH = 2048
)
(
    input  wire                  clk,
    input  wire                  rst,
    input  wire [1:0]            mode,

    input  wire [DATA_WIDTH-1:0] sdi_tdata,
    input  wire                  sdi_tvalid,
    output wire                  sdi_tready,
    input  wire                  sdi_tuser,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tuser,
    output wire                  m_axis_tlast,
    output wire                  fifo_overflow
);

localparam [1:0] MODE_COLORBAR = 2'd0;
localparam [1:0] MODE_SDI      = 2'd1;

wire colorbar_selected = mode == MODE_COLORBAR;
wire sdi_selected      = mode == MODE_SDI;

reg [1:0] mode_reg = MODE_COLORBAR;
reg sdi_start_pending_reg = 1'b0;
wire mode_changed = mode != mode_reg;
wire local_rst = rst || mode_changed;

wire [DATA_WIDTH-1:0] colorbar_tdata;
wire                  colorbar_tvalid;
wire                  colorbar_tready;
wire                  colorbar_tuser;
wire                  colorbar_tlast;

wire [DATA_WIDTH-1:0] sdi_drop_tdata;
wire                  sdi_drop_tvalid;
wire                  sdi_drop_tready;
wire                  sdi_drop_tuser;
wire                  sdi_start_active;
wire                  sdi_axis_tuser;
wire                  sdi_input_beat;

wire [DATA_WIDTH-1:0] source_tdata;
wire                  source_tvalid;
wire                  source_tready;
wire                  source_tuser;
wire                  source_tlast;

always @(posedge clk) begin
    if (rst) begin
        mode_reg <= mode;
    end else begin
        mode_reg <= mode;
    end
end

assign sdi_start_active = sdi_start_pending_reg || sdi_tuser;
assign sdi_axis_tuser = sdi_selected && sdi_start_active && sdi_tvalid;
assign sdi_input_beat = sdi_selected && sdi_tvalid && sdi_drop_tready;

always @(posedge clk) begin
    if (local_rst || !sdi_selected) begin
        sdi_start_pending_reg <= 1'b0;
    end else if (sdi_input_beat && sdi_start_active) begin
        sdi_start_pending_reg <= 1'b0;
    end else if (sdi_tuser) begin
        sdi_start_pending_reg <= 1'b1;
    end
end

axis_colorbar_gen #(
    .FRAME_WIDTH          (FRAME_WIDTH),
    .FRAME_HEIGHT         (FRAME_HEIGHT),
    .FRAME_PERIOD_CYCLES  (COLORBAR_PERIOD_CYCLES),
    .MOTION_STEP_PIXELS   (0)
) u_direct_colorbar_gen (
    .clk                  (clk),
    .rst                  (local_rst || !colorbar_selected),
    .m_axis_tdata         (colorbar_tdata),
    .m_axis_tvalid        (colorbar_tvalid),
    .m_axis_tready        (colorbar_tready),
    .m_axis_tlast         (colorbar_tlast),
    .m_axis_tuser         (colorbar_tuser)
);

axis_frame_drop #(
    .DATA_WIDTH           (DATA_WIDTH),
    .KEEP_EVERY_N         (SDI_KEEP_EVERY_N)
) u_sdi_frame_drop (
    .clk                  (clk),
    .rst                  (local_rst || !sdi_selected),
    .enable               (sdi_selected),
    .s_axis_tdata         (sdi_tdata),
    .s_axis_tvalid        (sdi_tvalid),
    .s_axis_tready        (sdi_drop_tready),
    .s_axis_tuser         (sdi_axis_tuser),
    .m_axis_tdata         (sdi_drop_tdata),
    .m_axis_tvalid        (sdi_drop_tvalid),
    .m_axis_tready        (sdi_selected ? source_tready : 1'b0),
    .m_axis_tuser         (sdi_drop_tuser),
    .kept_frame_start     ()
);

assign colorbar_tready = colorbar_selected ? source_tready : 1'b0;
assign sdi_tready = sdi_selected ? sdi_drop_tready : 1'b1;

assign source_tdata = colorbar_selected ? colorbar_tdata :
                      sdi_selected      ? sdi_drop_tdata :
                                          {DATA_WIDTH{1'b0}};
assign source_tvalid = colorbar_selected ? colorbar_tvalid :
                       sdi_selected      ? sdi_drop_tvalid :
                                           1'b0;
assign source_tuser = colorbar_selected ? colorbar_tuser :
                      sdi_selected      ? sdi_drop_tuser :
                                          1'b0;
assign source_tlast = colorbar_selected ? colorbar_tlast : 1'b0;

axis_video_fifo #(
    .DATA_WIDTH           (DATA_WIDTH),
    .DEPTH                (FIFO_DEPTH)
) u_source_axis_fifo (
    .clk                  (clk),
    .rst                  (local_rst),
    .s_axis_tdata         (source_tdata),
    .s_axis_tvalid        (source_tvalid),
    .s_axis_tready        (source_tready),
    .s_axis_tlast         (source_tlast),
    .s_axis_tuser         (source_tuser),
    .m_axis_tdata         (m_axis_tdata),
    .m_axis_tvalid        (m_axis_tvalid),
    .m_axis_tready        (m_axis_tready),
    .m_axis_tlast         (m_axis_tlast),
    .m_axis_tuser         (m_axis_tuser),
    .overflow             (fifo_overflow)
);

endmodule

`resetall
