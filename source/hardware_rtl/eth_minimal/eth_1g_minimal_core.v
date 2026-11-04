`timescale 1ns / 1ps
`default_nettype none

module eth_1g_minimal_core #
(
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
)
(
    input  wire       clk,
    input  wire       clk90,
    input  wire       rst,
    input  wire       video_axis_rst,

    input  wire       phy_rx_clk,
    input  wire [3:0] phy_rxd,
    input  wire       phy_rx_ctl,
    output wire       phy_tx_clk,
    output wire [3:0] phy_txd,
    output wire       phy_tx_ctl,

    input  wire [1:0] tx_video_select,
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

    output wire [1:0] led
);

wire [7:0] rx_axis_tdata;
wire [0:0] rx_axis_tkeep;
wire       rx_axis_tvalid;
wire       rx_axis_tready;
wire       rx_axis_tlast;
wire       rx_axis_tuser;

wire [7:0] tx_axis_tdata;
wire [0:0] tx_axis_tkeep;
wire       tx_axis_tvalid;
wire       tx_axis_tready;
wire       tx_axis_tlast;
wire       tx_axis_tuser;

wire       rx_eth_hdr_valid;
wire       rx_eth_hdr_ready;
wire [47:0] rx_eth_dest_mac;
wire [47:0] rx_eth_src_mac;
wire [15:0] rx_eth_type;
wire [7:0]  rx_eth_payload_axis_tdata;
wire [0:0]  rx_eth_payload_axis_tkeep;
wire        rx_eth_payload_axis_tvalid;
wire        rx_eth_payload_axis_tready;
wire        rx_eth_payload_axis_tlast;
wire        rx_eth_payload_axis_tuser;

wire        tx_eth_hdr_valid;
wire        tx_eth_hdr_ready;
wire [47:0] tx_eth_dest_mac;
wire [47:0] tx_eth_src_mac;
wire [15:0] tx_eth_type;
wire [7:0]  tx_eth_payload_axis_tdata;
wire        tx_eth_payload_axis_tvalid;
wire        tx_eth_payload_axis_tready;
wire        tx_eth_payload_axis_tlast;
wire        tx_eth_payload_axis_tuser;

wire        tx_udp_hdr_valid;
wire        tx_udp_hdr_ready;
wire [5:0]  tx_udp_ip_dscp;
wire [1:0]  tx_udp_ip_ecn;
wire [7:0]  tx_udp_ip_ttl;
wire [31:0] tx_udp_ip_source_ip;
wire [31:0] tx_udp_ip_dest_ip;
wire [15:0] tx_udp_source_port;
wire [15:0] tx_udp_dest_port;
wire [15:0] tx_udp_length;
wire [15:0] tx_udp_checksum;
wire [7:0]  tx_udp_payload_axis_tdata;
wire        tx_udp_payload_axis_tvalid;
wire        tx_udp_payload_axis_tready;
wire        tx_udp_payload_axis_tlast;
wire        tx_udp_payload_axis_tuser;

wire        ip_tx_error_arp_failed;
wire        udp_tx_error_payload_early_termination;
wire [31:0] packet_count;
wire [31:0] frame_count;
reg  [26:0] heartbeat_reg = 27'd0;

assign led[0] = heartbeat_reg[26];
assign led[1] = frame_count[0] ^ ip_tx_error_arp_failed ^ udp_tx_error_payload_early_termination;

always @(posedge clk) begin
    if (rst) begin
        heartbeat_reg <= 27'd0;
    end else begin
        heartbeat_reg <= heartbeat_reg + 27'd1;
    end
end

eth_colorbar_udp_tx #(
    .LOCAL_IP           (LOCAL_IP),
    .REMOTE_IP          (REMOTE_IP),
    .SRC_PORT           (SRC_PORT),
    .DST_PORT           (DST_PORT),
    .FRAME_WIDTH        (FRAME_WIDTH),
    .FRAME_HEIGHT       (FRAME_HEIGHT),
    .FRAME_PERIOD_CYCLES(FRAME_PERIOD_CYCLES),
    .MOTION_STEP_PIXELS (MOTION_STEP_PIXELS),
    .PIXELS_PER_PACKET  (PIXELS_PER_PACKET),
    .APP_HEADER_BYTES   (16)
)
colorbar_udp_tx_inst (
    .clk                       (clk),
    .rst                       (rst),
    .video_axis_rst            (video_axis_rst),
    .video_select              (tx_video_select),
    .ddr_axis_tdata            (ddr_axis_tdata),
    .ddr_axis_tvalid           (ddr_axis_tvalid),
    .ddr_axis_tready           (ddr_axis_tready),
    .ddr_axis_tlast            (ddr_axis_tlast),
    .ddr_axis_tuser            (ddr_axis_tuser),
    .spare_axis_tdata          (spare_axis_tdata),
    .spare_axis_tvalid         (spare_axis_tvalid),
    .spare_axis_tready         (spare_axis_tready),
    .spare_axis_tlast          (spare_axis_tlast),
    .spare_axis_tuser          (spare_axis_tuser),
    .tx_udp_hdr_valid          (tx_udp_hdr_valid),
    .tx_udp_hdr_ready          (tx_udp_hdr_ready),
    .tx_udp_ip_dscp            (tx_udp_ip_dscp),
    .tx_udp_ip_ecn             (tx_udp_ip_ecn),
    .tx_udp_ip_ttl             (tx_udp_ip_ttl),
    .tx_udp_ip_source_ip       (tx_udp_ip_source_ip),
    .tx_udp_ip_dest_ip         (tx_udp_ip_dest_ip),
    .tx_udp_source_port        (tx_udp_source_port),
    .tx_udp_dest_port          (tx_udp_dest_port),
    .tx_udp_length             (tx_udp_length),
    .tx_udp_checksum           (tx_udp_checksum),
    .tx_udp_payload_axis_tdata (tx_udp_payload_axis_tdata),
    .tx_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .tx_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .tx_udp_payload_axis_tlast (tx_udp_payload_axis_tlast),
    .tx_udp_payload_axis_tuser (tx_udp_payload_axis_tuser),
    .packet_count              (packet_count),
    .frame_count               (frame_count)
);

eth_mac_1g_rgmii_fifo #(
    .TARGET("XILINX"),
    .IODDR_STYLE("IODDR"),
    .CLOCK_INPUT_STYLE("BUFR"),
    .USE_CLK90("TRUE"),
    .ENABLE_PADDING(1),
    .MIN_FRAME_LENGTH(64),
    .TX_FIFO_DEPTH(4096),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(4096),
    .RX_FRAME_FIFO(1)
)
eth_mac_inst (
    .gtx_clk          (clk),
    .gtx_clk90        (clk90),
    .gtx_rst          (rst),
    .logic_clk        (clk),
    .logic_rst        (rst),

    .tx_axis_tdata    (tx_axis_tdata),
    .tx_axis_tkeep    (tx_axis_tkeep),
    .tx_axis_tvalid   (tx_axis_tvalid),
    .tx_axis_tready   (tx_axis_tready),
    .tx_axis_tlast    (tx_axis_tlast),
    .tx_axis_tuser    (tx_axis_tuser),

    .rx_axis_tdata    (rx_axis_tdata),
    .rx_axis_tkeep    (rx_axis_tkeep),
    .rx_axis_tvalid   (rx_axis_tvalid),
    .rx_axis_tready   (rx_axis_tready),
    .rx_axis_tlast    (rx_axis_tlast),
    .rx_axis_tuser    (rx_axis_tuser),

    .rgmii_rx_clk     (phy_rx_clk),
    .rgmii_rxd        (phy_rxd),
    .rgmii_rx_ctl     (phy_rx_ctl),
    .rgmii_tx_clk     (phy_tx_clk),
    .rgmii_txd        (phy_txd),
    .rgmii_tx_ctl     (phy_tx_ctl),

    .tx_error_underflow(),
    .tx_fifo_overflow (),
    .tx_fifo_bad_frame(),
    .tx_fifo_good_frame(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs (),
    .rx_fifo_overflow (),
    .rx_fifo_bad_frame(),
    .rx_fifo_good_frame(),
    .speed            (),

    .cfg_ifg          (8'd12),
    .cfg_tx_enable    (1'b1),
    .cfg_rx_enable    (1'b1)
);

eth_axis_rx #(
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0)
)
eth_axis_rx_inst (
    .clk                        (clk),
    .rst                        (rst),
    .s_axis_tdata               (rx_axis_tdata),
    .s_axis_tkeep               (rx_axis_tkeep),
    .s_axis_tvalid              (rx_axis_tvalid),
    .s_axis_tready              (rx_axis_tready),
    .s_axis_tlast               (rx_axis_tlast),
    .s_axis_tuser               (rx_axis_tuser),
    .m_eth_hdr_valid            (rx_eth_hdr_valid),
    .m_eth_hdr_ready            (rx_eth_hdr_ready),
    .m_eth_dest_mac             (rx_eth_dest_mac),
    .m_eth_src_mac              (rx_eth_src_mac),
    .m_eth_type                 (rx_eth_type),
    .m_eth_payload_axis_tdata   (rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep   (rx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid  (rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready  (rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast   (rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser   (rx_eth_payload_axis_tuser),
    .busy                       (),
    .error_header_early_termination()
);

eth_axis_tx #(
    .DATA_WIDTH(8),
    .KEEP_ENABLE(0)
)
eth_axis_tx_inst (
    .clk                        (clk),
    .rst                        (rst),
    .s_eth_hdr_valid            (tx_eth_hdr_valid),
    .s_eth_hdr_ready            (tx_eth_hdr_ready),
    .s_eth_dest_mac             (tx_eth_dest_mac),
    .s_eth_src_mac              (tx_eth_src_mac),
    .s_eth_type                 (tx_eth_type),
    .s_eth_payload_axis_tdata   (tx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep   (1'b1),
    .s_eth_payload_axis_tvalid  (tx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready  (tx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast   (tx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser   (tx_eth_payload_axis_tuser),
    .m_axis_tdata               (tx_axis_tdata),
    .m_axis_tkeep               (tx_axis_tkeep),
    .m_axis_tvalid              (tx_axis_tvalid),
    .m_axis_tready              (tx_axis_tready),
    .m_axis_tlast               (tx_axis_tlast),
    .m_axis_tuser               (tx_axis_tuser),
    .busy                       ()
);

udp_complete #(
    .ARP_CACHE_ADDR_WIDTH(9),
    .ARP_REQUEST_RETRY_COUNT(4),
    .ARP_REQUEST_RETRY_INTERVAL(125000000),
    .ARP_REQUEST_TIMEOUT(1250000000),
    .UDP_CHECKSUM_GEN_ENABLE(1),
    .UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH(2048),
    .UDP_CHECKSUM_HEADER_FIFO_DEPTH(8)
)
udp_complete_inst (
    .clk                                (clk),
    .rst                                (rst),

    .s_eth_hdr_valid                    (rx_eth_hdr_valid),
    .s_eth_hdr_ready                    (rx_eth_hdr_ready),
    .s_eth_dest_mac                     (rx_eth_dest_mac),
    .s_eth_src_mac                      (rx_eth_src_mac),
    .s_eth_type                         (rx_eth_type),
    .s_eth_payload_axis_tdata           (rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tvalid          (rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready          (rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast           (rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser           (rx_eth_payload_axis_tuser),

    .m_eth_hdr_valid                    (tx_eth_hdr_valid),
    .m_eth_hdr_ready                    (tx_eth_hdr_ready),
    .m_eth_dest_mac                     (tx_eth_dest_mac),
    .m_eth_src_mac                      (tx_eth_src_mac),
    .m_eth_type                         (tx_eth_type),
    .m_eth_payload_axis_tdata           (tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tvalid          (tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready          (tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast           (tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser           (tx_eth_payload_axis_tuser),

    .s_ip_hdr_valid                     (1'b0),
    .s_ip_hdr_ready                     (),
    .s_ip_dscp                          (6'd0),
    .s_ip_ecn                           (2'd0),
    .s_ip_length                        (16'd0),
    .s_ip_ttl                           (8'd0),
    .s_ip_protocol                      (8'd0),
    .s_ip_source_ip                     (32'd0),
    .s_ip_dest_ip                       (32'd0),
    .s_ip_payload_axis_tdata            (8'd0),
    .s_ip_payload_axis_tvalid           (1'b0),
    .s_ip_payload_axis_tready           (),
    .s_ip_payload_axis_tlast            (1'b0),
    .s_ip_payload_axis_tuser            (1'b0),

    .m_ip_hdr_valid                     (),
    .m_ip_hdr_ready                     (1'b1),
    .m_ip_eth_dest_mac                  (),
    .m_ip_eth_src_mac                   (),
    .m_ip_eth_type                      (),
    .m_ip_version                       (),
    .m_ip_ihl                           (),
    .m_ip_dscp                          (),
    .m_ip_ecn                           (),
    .m_ip_length                        (),
    .m_ip_identification                (),
    .m_ip_flags                         (),
    .m_ip_fragment_offset               (),
    .m_ip_ttl                           (),
    .m_ip_protocol                      (),
    .m_ip_header_checksum               (),
    .m_ip_source_ip                     (),
    .m_ip_dest_ip                       (),
    .m_ip_payload_axis_tdata            (),
    .m_ip_payload_axis_tvalid           (),
    .m_ip_payload_axis_tready           (1'b1),
    .m_ip_payload_axis_tlast            (),
    .m_ip_payload_axis_tuser            (),

    .s_udp_hdr_valid                    (tx_udp_hdr_valid),
    .s_udp_hdr_ready                    (tx_udp_hdr_ready),
    .s_udp_ip_dscp                      (tx_udp_ip_dscp),
    .s_udp_ip_ecn                       (tx_udp_ip_ecn),
    .s_udp_ip_ttl                       (tx_udp_ip_ttl),
    .s_udp_ip_source_ip                 (tx_udp_ip_source_ip),
    .s_udp_ip_dest_ip                   (tx_udp_ip_dest_ip),
    .s_udp_source_port                  (tx_udp_source_port),
    .s_udp_dest_port                    (tx_udp_dest_port),
    .s_udp_length                       (tx_udp_length),
    .s_udp_checksum                     (tx_udp_checksum),
    .s_udp_payload_axis_tdata           (tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tvalid          (tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready          (tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast           (tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser           (tx_udp_payload_axis_tuser),

    .m_udp_hdr_valid                    (),
    .m_udp_hdr_ready                    (1'b1),
    .m_udp_eth_dest_mac                 (),
    .m_udp_eth_src_mac                  (),
    .m_udp_eth_type                     (),
    .m_udp_ip_version                   (),
    .m_udp_ip_ihl                       (),
    .m_udp_ip_dscp                      (),
    .m_udp_ip_ecn                       (),
    .m_udp_ip_length                    (),
    .m_udp_ip_identification            (),
    .m_udp_ip_flags                     (),
    .m_udp_ip_fragment_offset           (),
    .m_udp_ip_ttl                       (),
    .m_udp_ip_protocol                  (),
    .m_udp_ip_header_checksum           (),
    .m_udp_ip_source_ip                 (),
    .m_udp_ip_dest_ip                   (),
    .m_udp_source_port                  (),
    .m_udp_dest_port                    (),
    .m_udp_length                       (),
    .m_udp_checksum                     (),
    .m_udp_payload_axis_tdata           (),
    .m_udp_payload_axis_tvalid          (),
    .m_udp_payload_axis_tready          (1'b1),
    .m_udp_payload_axis_tlast           (),
    .m_udp_payload_axis_tuser           (),

    .ip_rx_busy                         (),
    .ip_tx_busy                         (),
    .udp_rx_busy                        (),
    .udp_tx_busy                        (),
    .ip_rx_error_header_early_termination(),
    .ip_rx_error_payload_early_termination(),
    .ip_rx_error_invalid_header         (),
    .ip_rx_error_invalid_checksum       (),
    .ip_tx_error_payload_early_termination(),
    .ip_tx_error_arp_failed             (ip_tx_error_arp_failed),
    .udp_rx_error_header_early_termination(),
    .udp_rx_error_payload_early_termination(),
    .udp_tx_error_payload_early_termination(udp_tx_error_payload_early_termination),

    .local_mac                          (LOCAL_MAC),
    .local_ip                           (LOCAL_IP),
    .gateway_ip                         (GATEWAY_IP),
    .subnet_mask                        (SUBNET_MASK),
    .clear_arp_cache                    (1'b0)
);

endmodule

`resetall
