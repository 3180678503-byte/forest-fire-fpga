`timescale 1ns / 1ps
`default_nettype none

module eth_colorbar_udp_tx #
(
    parameter [31:0] LOCAL_IP = {8'd192, 8'd168, 8'd1, 8'd88},
    parameter [31:0] REMOTE_IP = {8'd192, 8'd168, 8'd1, 8'd100},
    parameter [15:0] SRC_PORT = 16'd50000,
    parameter [15:0] DST_PORT = 16'd50001,
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer FRAME_PERIOD_CYCLES = 12500000,
    parameter integer MOTION_STEP_PIXELS = 16,
    parameter integer PIXELS_PER_PACKET = 480,
    parameter integer APP_HEADER_BYTES = 16
)
(
    input  wire        clk,
    input  wire        rst,
    input  wire        video_axis_rst,

    input  wire [1:0]  video_select,

    input  wire [23:0] ddr_axis_tdata,
    input  wire        ddr_axis_tvalid,
    output wire        ddr_axis_tready,
    input  wire        ddr_axis_tlast,
    input  wire        ddr_axis_tuser,

    input  wire [23:0] spare_axis_tdata,
    input  wire        spare_axis_tvalid,
    output wire        spare_axis_tready,
    input  wire        spare_axis_tlast,
    input  wire        spare_axis_tuser,

    output wire        tx_udp_hdr_valid,
    input  wire        tx_udp_hdr_ready,
    output wire [5:0]  tx_udp_ip_dscp,
    output wire [1:0]  tx_udp_ip_ecn,
    output wire [7:0]  tx_udp_ip_ttl,
    output wire [31:0] tx_udp_ip_source_ip,
    output wire [31:0] tx_udp_ip_dest_ip,
    output wire [15:0] tx_udp_source_port,
    output wire [15:0] tx_udp_dest_port,
    output wire [15:0] tx_udp_length,
    output wire [15:0] tx_udp_checksum,
    output wire [7:0]  tx_udp_payload_axis_tdata,
    output wire        tx_udp_payload_axis_tvalid,
    input  wire        tx_udp_payload_axis_tready,
    output wire        tx_udp_payload_axis_tlast,
    output wire        tx_udp_payload_axis_tuser,

    output wire [31:0] packet_count,
    output wire [31:0] frame_count
);

wire [23:0] video_axis_tdata;
wire        video_axis_tvalid;
wire        video_axis_tready;
wire        video_axis_tlast;
wire        video_axis_tuser;

wire [23:0] colorbar_axis_tdata;
wire        colorbar_axis_tvalid;
wire        colorbar_axis_tready;
wire        colorbar_axis_tlast;
wire        colorbar_axis_tuser;
wire        video_tx_rst = rst;

wire select_colorbar = video_select == 2'd0;
wire select_ddr      = video_select == 2'd1;
wire select_spare    = video_select == 2'd2;

axis_colorbar_gen #(
    .FRAME_WIDTH        (FRAME_WIDTH),
    .FRAME_HEIGHT       (FRAME_HEIGHT),
    .FRAME_PERIOD_CYCLES(FRAME_PERIOD_CYCLES),
    .MOTION_STEP_PIXELS (MOTION_STEP_PIXELS)
)
colorbar_gen_inst (
    .clk          (clk),
    .rst          (rst),
    .m_axis_tdata (colorbar_axis_tdata),
    .m_axis_tvalid(colorbar_axis_tvalid),
    .m_axis_tready(colorbar_axis_tready),
    .m_axis_tlast (colorbar_axis_tlast),
    .m_axis_tuser (colorbar_axis_tuser)
);

assign video_axis_tdata = select_colorbar ? colorbar_axis_tdata :
                          select_ddr      ? ddr_axis_tdata :
                          select_spare    ? spare_axis_tdata :
                          24'd0;
assign video_axis_tvalid = select_colorbar ? colorbar_axis_tvalid :
                           select_ddr      ? ddr_axis_tvalid :
                           select_spare    ? spare_axis_tvalid :
                           1'b0;
assign video_axis_tlast = select_colorbar ? colorbar_axis_tlast :
                          select_ddr      ? ddr_axis_tlast :
                          select_spare    ? spare_axis_tlast :
                          1'b0;
assign video_axis_tuser = select_colorbar ? colorbar_axis_tuser :
                          select_ddr      ? ddr_axis_tuser :
                          select_spare    ? spare_axis_tuser :
                          1'b0;

assign colorbar_axis_tready = select_colorbar && video_axis_tready;
assign ddr_axis_tready = select_ddr && video_axis_tready;
assign spare_axis_tready = select_spare && video_axis_tready;

axis_video_udp_tx #(
    .LOCAL_IP         (LOCAL_IP),
    .REMOTE_IP        (REMOTE_IP),
    .SRC_PORT         (SRC_PORT),
    .DST_PORT         (DST_PORT),
    .FRAME_WIDTH      (FRAME_WIDTH),
    .FRAME_HEIGHT     (FRAME_HEIGHT),
    .PIXELS_PER_PACKET(PIXELS_PER_PACKET),
    .APP_HEADER_BYTES (APP_HEADER_BYTES)
)
video_udp_tx_inst (
    .clk                         (clk),
    .rst                         (video_tx_rst),
    .flush_req                   (video_axis_rst),
    .s_axis_tdata                (video_axis_tdata),
    .s_axis_tvalid               (video_axis_tvalid),
    .s_axis_tready               (video_axis_tready),
    .s_axis_tlast                (video_axis_tlast),
    .s_axis_tuser                (video_axis_tuser),
    .tx_udp_hdr_valid            (tx_udp_hdr_valid),
    .tx_udp_hdr_ready            (tx_udp_hdr_ready),
    .tx_udp_ip_dscp              (tx_udp_ip_dscp),
    .tx_udp_ip_ecn               (tx_udp_ip_ecn),
    .tx_udp_ip_ttl               (tx_udp_ip_ttl),
    .tx_udp_ip_source_ip         (tx_udp_ip_source_ip),
    .tx_udp_ip_dest_ip           (tx_udp_ip_dest_ip),
    .tx_udp_source_port          (tx_udp_source_port),
    .tx_udp_dest_port            (tx_udp_dest_port),
    .tx_udp_length               (tx_udp_length),
    .tx_udp_checksum             (tx_udp_checksum),
    .tx_udp_payload_axis_tdata   (tx_udp_payload_axis_tdata),
    .tx_udp_payload_axis_tvalid  (tx_udp_payload_axis_tvalid),
    .tx_udp_payload_axis_tready  (tx_udp_payload_axis_tready),
    .tx_udp_payload_axis_tlast   (tx_udp_payload_axis_tlast),
    .tx_udp_payload_axis_tuser   (tx_udp_payload_axis_tuser),
    .packet_count                (packet_count),
    .frame_count                 (frame_count)
);

endmodule

`resetall
