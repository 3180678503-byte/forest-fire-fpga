`timescale 1ns / 1ps
`default_nettype none

module pl_eth_colorbar_top #(
    parameter [47:0] LOCAL_MAC = 48'h02_0A_35_01_10_80,
    parameter [31:0] LOCAL_IP  = {8'd192, 8'd168, 8'd1, 8'd88},
    parameter [31:0] REMOTE_IP = {8'd192, 8'd168, 8'd1, 8'd100},
    parameter [31:0] GATEWAY_IP = {8'd192, 8'd168, 8'd1, 8'd1},
    parameter [31:0] SUBNET_MASK = {8'd255, 8'd255, 8'd255, 8'd0},
    parameter [15:0] SRC_PORT = 16'd50000,
    parameter [15:0] DST_PORT = 16'd50001,
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer FRAME_PERIOD_CYCLES = 12500000,
    parameter integer MOTION_STEP_PIXELS = 16,
    parameter integer PIXELS_PER_PACKET = 480
) (
    input  wire       ref_clk_200mhz,
    input  wire       rst,

    output wire       pl_phy_txc,
    output wire       pl_phy_tx_ctl,
    output wire [3:0] pl_phy_txd,
    input  wire       pl_phy_rxc,
    input  wire       pl_phy_rx_ctl,
    input  wire [3:0] pl_phy_rxd,
    output wire       pl_phy_mdc,
    inout  wire       pl_phy_mdio,
    output wire       pl_phy_reset_n,

    input  wire [1:0] tx_video_select,

    input  wire       s_video_axis_aclk,
    input  wire       s_video_axis_aresetn,
    input  wire [23:0] s_video_axis_tdata,
    input  wire       s_video_axis_tvalid,
    output wire       s_video_axis_tready,
    input  wire       s_video_axis_tlast,
    input  wire       s_video_axis_tuser,

    input  wire [23:0] spare_axis_tdata,
    input  wire        spare_axis_tvalid,
    output wire        spare_axis_tready,
    input  wire        spare_axis_tlast,
    input  wire        spare_axis_tuser,

    output wire [1:0] led,
    output wire       eth_clk_out,
    output wire       eth_clk_locked
);

wire eth_clk;
wire eth_clk_90;
wire eth_pll_locked;
wire rst_125m;
wire phy_ready;
wire core_rst;
wire [23:0] ddr_fifo_axis_tdata;
wire [2:0] ddr_fifo_axis_tkeep;
wire        ddr_fifo_axis_tvalid;
wire        ddr_fifo_axis_tready;
wire        ddr_fifo_axis_tlast;
wire        ddr_fifo_axis_tuser;
wire        video_axis_rst_125m;
reg  [2:0] video_axis_rst_sync_reg = 3'b111;

assign pl_phy_mdc = 1'b0;
assign pl_phy_mdio = 1'bz;
assign eth_clk_locked = eth_pll_locked;
assign eth_clk_out = eth_clk;
assign core_rst = rst_125m | ~phy_ready;
assign video_axis_rst_125m = video_axis_rst_sync_reg[2];

always @(posedge eth_clk) begin
    if (core_rst) begin
        video_axis_rst_sync_reg <= 3'b111;
    end else begin
        video_axis_rst_sync_reg <= {video_axis_rst_sync_reg[1:0], ~s_video_axis_aresetn};
    end
end

eth_pll_125m eth_pll_125m_inst (
    .ref_clk_200mhz(ref_clk_200mhz),
    .rst         (rst),
    .clk_125m    (eth_clk),
    .clk_125m_90 (eth_clk_90),
    .locked      (eth_pll_locked)
);

sync_reset #(
    .N(4)
)
sync_reset_inst (
    .clk(eth_clk),
    .rst(rst | ~eth_pll_locked),
    .out(rst_125m)
);

phy_reset_timer #(
    .RESET_HOLD_CYCLES(12500000)
)
phy_reset_timer_inst (
    .clk        (eth_clk),
    .rst        (rst_125m),
    .phy_reset_n(pl_phy_reset_n),
    .phy_ready  (phy_ready)
);

axis_async_fifo #(
    .DEPTH(8192),
    .DATA_WIDTH(24),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(3),
    .LAST_ENABLE(1),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .FRAME_FIFO(0)
)
video_cdc_fifo_inst (
    .s_clk                  (s_video_axis_aclk),
    .s_rst                  (~s_video_axis_aresetn),
    .s_axis_tdata           (s_video_axis_tdata),
    .s_axis_tkeep           (3'b111),
    .s_axis_tvalid          (s_video_axis_tvalid),
    .s_axis_tready          (s_video_axis_tready),
    .s_axis_tlast           (s_video_axis_tlast),
    .s_axis_tid             (8'd0),
    .s_axis_tdest           (8'd0),
    .s_axis_tuser           (s_video_axis_tuser),
    .m_clk                  (eth_clk),
    .m_rst                  (core_rst),
    .m_axis_tdata           (ddr_fifo_axis_tdata),
    .m_axis_tkeep           (ddr_fifo_axis_tkeep),
    .m_axis_tvalid          (ddr_fifo_axis_tvalid),
    .m_axis_tready          (ddr_fifo_axis_tready),
    .m_axis_tlast           (ddr_fifo_axis_tlast),
    .m_axis_tid             ( ),
    .m_axis_tdest           ( ),
    .m_axis_tuser           (ddr_fifo_axis_tuser),
    .s_pause_req            (1'b0),
    .s_pause_ack            ( ),
    .m_pause_req            (1'b0),
    .m_pause_ack            ( ),
    .s_status_depth         ( ),
    .s_status_depth_commit  ( ),
    .s_status_overflow      ( ),
    .s_status_bad_frame     ( ),
    .s_status_good_frame    ( ),
    .m_status_depth         ( ),
    .m_status_depth_commit  ( ),
    .m_status_overflow      ( ),
    .m_status_bad_frame     ( ),
    .m_status_good_frame    ( )
);

eth_1g_minimal_core #(
    .LOCAL_MAC          (LOCAL_MAC),
    .LOCAL_IP           (LOCAL_IP),
    .REMOTE_IP          (REMOTE_IP),
    .GATEWAY_IP         (GATEWAY_IP),
    .SUBNET_MASK        (SUBNET_MASK),
    .SRC_PORT           (SRC_PORT),
    .DST_PORT           (DST_PORT),
    .FRAME_WIDTH        (FRAME_WIDTH),
    .FRAME_HEIGHT       (FRAME_HEIGHT),
    .FRAME_PERIOD_CYCLES(FRAME_PERIOD_CYCLES),
    .MOTION_STEP_PIXELS (MOTION_STEP_PIXELS),
    .PIXELS_PER_PACKET  (PIXELS_PER_PACKET)
)
core_inst (
    .clk       (eth_clk),
    .clk90     (eth_clk_90),
    .rst       (core_rst),
    .video_axis_rst(video_axis_rst_125m),
    .phy_rx_clk(pl_phy_rxc),
    .phy_rxd   (pl_phy_rxd),
    .phy_rx_ctl(pl_phy_rx_ctl),
    .phy_tx_clk(pl_phy_txc),
    .phy_txd   (pl_phy_txd),
    .phy_tx_ctl(pl_phy_tx_ctl),
    .tx_video_select(tx_video_select),
    .ddr_axis_tdata(ddr_fifo_axis_tdata),
    .ddr_axis_tvalid(ddr_fifo_axis_tvalid),
    .ddr_axis_tready(ddr_fifo_axis_tready),
    .ddr_axis_tlast(ddr_fifo_axis_tlast),
    .ddr_axis_tuser(ddr_fifo_axis_tuser),
    .spare_axis_tdata(spare_axis_tdata),
    .spare_axis_tvalid(spare_axis_tvalid),
    .spare_axis_tready(spare_axis_tready),
    .spare_axis_tlast(spare_axis_tlast),
    .spare_axis_tuser(spare_axis_tuser),
    .led       (led)
);

endmodule

`resetall
