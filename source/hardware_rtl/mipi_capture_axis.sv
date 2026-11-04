`timescale 1ns / 1ps
`default_nettype none

//------------------------------------------------------------------------------
// Clean MIPI capture wrapper for the current PS-controlled project.
//
// AXI-Lite map relative to the 0x400C_0000 GP0/MIPI aperture:
//   0x00000 - 0x03fff : wrapper status
//   0x04000 - 0x04fff : CSI2 RX subsystem
//   0x08000 - 0x08fff : demosaic HLS IP
//   0x0c000 - 0x0ffff : gamma HLS IP
//------------------------------------------------------------------------------
module mipi_capture_axis #(
    parameter integer ADDR_WIDTH = 18
)(
    input wire [31:0] diag_frames_in,
    input wire [31:0] diag_frames_out,
    input wire [31:0] diag_lines,
    input wire [31:0] diag_errors,
    input wire [31:0] diag_stalls,
    input  wire                   ctrl_aclk,
    input  wire                   ctrl_aresetn,
    input  wire                   video_aclk,
    input  wire                   video_aresetn,
    input  wire                   dphy_clk_200m,

    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,
    input  wire [31:0]            s_axi_wdata,
    input  wire [3:0]             s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,
    output wire [31:0]            s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    input  wire                   mipi_phy_if_clk_hs_n,
    input  wire                   mipi_phy_if_clk_hs_p,
    input  wire                   mipi_phy_if_clk_lp_n,
    input  wire                   mipi_phy_if_clk_lp_p,
    input  wire [1:0]             mipi_phy_if_data_hs_n,
    input  wire [1:0]             mipi_phy_if_data_hs_p,
    input  wire [1:0]             mipi_phy_if_data_lp_n,
    input  wire [1:0]             mipi_phy_if_data_lp_p,

    output wire [23:0]            m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tuser,
    output wire                   m_axis_tlast,

    output wire                   csi_irq,
    output wire                   demosaic_irq,
    output wire                   gamma_irq,
    output wire                   dlyctrl_rdy,
    output wire                   csi_system_rst
);

localparam [31:0] REG_ID      = 32'h4D49_5049; // "MIPI"
localparam [31:0] REG_VERSION = 32'h0003_0000;

wire sel_status_wr   = s_axi_awaddr[15:14] == 2'b00;
wire sel_csi_wr      = s_axi_awaddr[15:14] == 2'b01;
wire sel_demosaic_wr = s_axi_awaddr[15:14] == 2'b10;
wire sel_gamma_wr    = s_axi_awaddr[15:14] == 2'b11;

wire sel_status_rd   = s_axi_araddr[15:14] == 2'b00;
wire sel_csi_rd      = s_axi_araddr[15:14] == 2'b01;
wire sel_demosaic_rd = s_axi_araddr[15:14] == 2'b10;
wire sel_gamma_rd    = s_axi_araddr[15:14] == 2'b11;

reg        status_awready;
reg        status_wready;
reg        status_bvalid;
reg        status_arready;
reg        status_rvalid;
reg [31:0] status_rdata;

wire       csi_awready;
wire       csi_wready;
wire [1:0] csi_bresp;
wire       csi_bvalid;
wire       csi_arready;
wire [31:0] csi_rdata;
wire [1:0] csi_rresp;
wire       csi_rvalid;

wire       demux_awready;
wire       demux_wready;
wire [1:0] demux_bresp;
wire       demux_bvalid;
wire       demux_arready;
wire [31:0] demux_rdata;
wire [1:0] demux_rresp;
wire       demux_rvalid;

wire       gammax_awready;
wire       gammax_wready;
wire [1:0] gammax_bresp;
wire       gammax_bvalid;
wire       gammax_arready;
wire [31:0] gammax_rdata;
wire [1:0] gammax_rresp;
wire       gammax_rvalid;

wire       demosaic_awready;
wire       demosaic_wready;
wire [1:0] demosaic_bresp;
wire       demosaic_bvalid;
wire       demosaic_arready;
wire [31:0] demosaic_rdata;
wire [1:0] demosaic_rresp;
wire       demosaic_rvalid;
wire [5:0]  demosaic_awaddr;
wire        demosaic_awvalid;
wire [31:0] demosaic_wdata;
wire [3:0]  demosaic_wstrb;
wire        demosaic_wvalid;
wire        demosaic_bready;
wire [5:0]  demosaic_araddr;
wire        demosaic_arvalid;
wire        demosaic_rready;

wire       gamma_awready;
wire       gamma_wready;
wire [1:0] gamma_bresp;
wire       gamma_bvalid;
wire       gamma_arready;
wire [31:0] gamma_rdata;
wire [1:0] gamma_rresp;
wire       gamma_rvalid;
wire [12:0] gamma_awaddr;
wire        gamma_awvalid;
wire [31:0] gamma_wdata;
wire [3:0]  gamma_wstrb;
wire        gamma_wvalid;
wire        gamma_bready;
wire [12:0] gamma_araddr;
wire        gamma_arvalid;
wire        gamma_rready;

assign s_axi_awready = sel_status_wr   ? status_awready :
                       sel_csi_wr      ? csi_awready :
                       sel_demosaic_wr ? demux_awready :
                                         gammax_awready;
assign s_axi_wready  = sel_status_wr   ? status_wready :
                       sel_csi_wr      ? csi_wready :
                       sel_demosaic_wr ? demux_wready :
                                         gammax_wready;
assign s_axi_bresp   = status_bvalid ? 2'b00 :
                       csi_bvalid    ? csi_bresp :
                       demux_bvalid  ? demux_bresp :
                                        gammax_bresp;
assign s_axi_bvalid  = status_bvalid | csi_bvalid | demux_bvalid | gammax_bvalid;
assign s_axi_arready = sel_status_rd   ? status_arready :
                       sel_csi_rd      ? csi_arready :
                       sel_demosaic_rd ? demux_arready :
                                         gammax_arready;
assign s_axi_rdata   = status_rvalid ? status_rdata :
                       csi_rvalid    ? csi_rdata :
                       demux_rvalid  ? demux_rdata :
                                       gammax_rdata;
assign s_axi_rresp   = status_rvalid ? 2'b00 :
                       csi_rvalid    ? csi_rresp :
                       demux_rvalid  ? demux_rresp :
                                       gammax_rresp;
assign s_axi_rvalid  = status_rvalid | csi_rvalid | demux_rvalid | gammax_rvalid;

wire csi_awvalid      = s_axi_awvalid && sel_csi_wr;
wire csi_wvalid       = s_axi_wvalid  && sel_csi_wr;
wire csi_arvalid      = s_axi_arvalid && sel_csi_rd;
wire demux_awvalid    = s_axi_awvalid && sel_demosaic_wr;
wire demux_wvalid     = s_axi_wvalid  && sel_demosaic_wr;
wire demux_arvalid    = s_axi_arvalid && sel_demosaic_rd;
wire gammax_awvalid   = s_axi_awvalid && sel_gamma_wr;
wire gammax_wvalid    = s_axi_wvalid  && sel_gamma_wr;
wire gammax_arvalid   = s_axi_arvalid && sel_gamma_rd;

wire _unused_axi = ^{s_axi_awprot, s_axi_arprot, s_axi_awaddr[ADDR_WIDTH-1:16],
                     s_axi_araddr[ADDR_WIDTH-1:16]};

always @(posedge ctrl_aclk) begin
    if (!ctrl_aresetn) begin
        status_awready <= 1'b0;
        status_wready  <= 1'b0;
        status_bvalid  <= 1'b0;
        status_arready <= 1'b0;
        status_rvalid  <= 1'b0;
        status_rdata   <= 32'd0;
    end else begin
        status_awready <= !status_bvalid && s_axi_awvalid && s_axi_wvalid && sel_status_wr;
        status_wready  <= !status_bvalid && s_axi_awvalid && s_axi_wvalid && sel_status_wr;
        status_arready <= !status_rvalid && s_axi_arvalid && sel_status_rd;

        if (status_awready && s_axi_wready) begin
            status_bvalid <= 1'b1;
        end else if (status_bvalid && s_axi_bready) begin
            status_bvalid <= 1'b0;
        end

        if (status_arready) begin
            case (s_axi_araddr[7:0])
                8'h00: status_rdata <= REG_ID;
                8'h04: status_rdata <= REG_VERSION;
                8'h08: status_rdata <= {28'd0, gamma_irq, demosaic_irq, csi_irq, dlyctrl_rdy};
                8'h0c: status_rdata <= {31'd0, csi_system_rst};
                8'h10: status_rdata <= 32'h0000_4000;
                8'h14: status_rdata <= 32'h0000_8000;
                8'h18: status_rdata <= 32'h0000_C000;
                8'h40: status_rdata <= 32'h414E_3536; // "AN56" independent bridge ID
                8'h44: status_rdata <= diag_frames_in;
                8'h48: status_rdata <= diag_frames_out;
                8'h4c: status_rdata <= diag_lines;
                8'h50: status_rdata <= diag_errors;
                8'h54: status_rdata <= diag_stalls;
                8'h58: status_rdata <= 32'd1920;
                8'h5c: status_rdata <= 32'd1080;
                default: status_rdata <= 32'hDEAD_4D49;
            endcase
            status_rvalid <= 1'b1;
        end else if (status_rvalid && s_axi_rready) begin
            status_rvalid <= 1'b0;
        end
    end
end

wire [15:0] csi_tdata;
wire [9:0]  csi_tdest;
wire        csi_tlast;
wire        csi_tready;
wire [0:0]  csi_tuser;
wire        csi_tvalid;

wire [31:0] demosaic_tdata;
wire [3:0]  demosaic_tkeep;
wire [3:0]  demosaic_tstrb;
wire [0:0]  demosaic_tuser;
wire [0:0]  demosaic_tlast;
wire [0:0]  demosaic_tid;
wire [0:0]  demosaic_tdest;
wire        demosaic_tvalid;
wire        demosaic_tready;

wire [31:0] gamma_tdata;
wire [3:0]  gamma_tkeep;
wire [3:0]  gamma_tstrb;
wire [0:0]  gamma_tuser;
wire [0:0]  gamma_tlast;
wire [0:0]  gamma_tid;
wire [0:0]  gamma_tdest;
wire        gamma_tvalid;
wire        gamma_tready;

wire [2:0]  subset_tkeep;
wire [2:0]  subset_tstrb;
wire [0:0]  subset_tid;
wire [0:0]  subset_tdest;
wire [0:0]  subset_tuser;

wire        rxbyteclkhs;

design_1_mipi_csi2_rx_subsyst_0_0 u_csi2_rx (
    .lite_aclk                  (ctrl_aclk),
    .lite_aresetn               (ctrl_aresetn),
    .dphy_clk_200M              (dphy_clk_200m),
    .dlyctrl_rdy_out            (dlyctrl_rdy),
    .rxbyteclkhs                (rxbyteclkhs),
    .system_rst_out             (csi_system_rst),
    .csirxss_csi_irq            (csi_irq),
    .video_aclk                 (video_aclk),
    .video_aresetn              (video_aresetn),
    .csirxss_s_axi_araddr       (s_axi_araddr[7:0]),
    .csirxss_s_axi_arready      (csi_arready),
    .csirxss_s_axi_arvalid      (csi_arvalid),
    .csirxss_s_axi_awaddr       (s_axi_awaddr[7:0]),
    .csirxss_s_axi_awready      (csi_awready),
    .csirxss_s_axi_awvalid      (csi_awvalid),
    .csirxss_s_axi_bready       (s_axi_bready),
    .csirxss_s_axi_bresp        (csi_bresp),
    .csirxss_s_axi_bvalid       (csi_bvalid),
    .csirxss_s_axi_rdata        (csi_rdata),
    .csirxss_s_axi_rready       (s_axi_rready),
    .csirxss_s_axi_rresp        (csi_rresp),
    .csirxss_s_axi_rvalid       (csi_rvalid),
    .csirxss_s_axi_wdata        (s_axi_wdata),
    .csirxss_s_axi_wready       (csi_wready),
    .csirxss_s_axi_wstrb        (s_axi_wstrb),
    .csirxss_s_axi_wvalid       (csi_wvalid),
    .video_out_tdata            (csi_tdata),
    .video_out_tdest            (csi_tdest),
    .video_out_tlast            (csi_tlast),
    .video_out_tready           (csi_tready),
    .video_out_tuser            (csi_tuser),
    .video_out_tvalid           (csi_tvalid),
    .mipi_phy_if_clk_hs_n       (mipi_phy_if_clk_hs_n),
    .mipi_phy_if_clk_hs_p       (mipi_phy_if_clk_hs_p),
    .mipi_phy_if_clk_lp_n       (mipi_phy_if_clk_lp_n),
    .mipi_phy_if_clk_lp_p       (mipi_phy_if_clk_lp_p),
    .mipi_phy_if_data_hs_n      (mipi_phy_if_data_hs_n),
    .mipi_phy_if_data_hs_p      (mipi_phy_if_data_hs_p),
    .mipi_phy_if_data_lp_n      (mipi_phy_if_data_lp_n),
    .mipi_phy_if_data_lp_p      (mipi_phy_if_data_lp_p)
);

design_1_auto_cc_0 u_demosaic_ctrl_cdc (
    .s_axi_aclk      (ctrl_aclk),
    .s_axi_aresetn   (ctrl_aresetn),
    .s_axi_awaddr    (s_axi_awaddr[5:0]),
    .s_axi_awprot    (s_axi_awprot),
    .s_axi_awvalid   (demux_awvalid),
    .s_axi_awready   (demux_awready),
    .s_axi_wdata     (s_axi_wdata),
    .s_axi_wstrb     (s_axi_wstrb),
    .s_axi_wvalid    (demux_wvalid),
    .s_axi_wready    (demux_wready),
    .s_axi_bresp     (demux_bresp),
    .s_axi_bvalid    (demux_bvalid),
    .s_axi_bready    (s_axi_bready),
    .s_axi_araddr    (s_axi_araddr[5:0]),
    .s_axi_arprot    (s_axi_arprot),
    .s_axi_arvalid   (demux_arvalid),
    .s_axi_arready   (demux_arready),
    .s_axi_rdata     (demux_rdata),
    .s_axi_rresp     (demux_rresp),
    .s_axi_rvalid    (demux_rvalid),
    .s_axi_rready    (s_axi_rready),
    .m_axi_aclk      (video_aclk),
    .m_axi_aresetn   (video_aresetn),
    .m_axi_awaddr    (demosaic_awaddr),
    .m_axi_awprot    (),
    .m_axi_awvalid   (demosaic_awvalid),
    .m_axi_awready   (demosaic_awready),
    .m_axi_wdata     (demosaic_wdata),
    .m_axi_wstrb     (demosaic_wstrb),
    .m_axi_wvalid    (demosaic_wvalid),
    .m_axi_wready    (demosaic_wready),
    .m_axi_bresp     (demosaic_bresp),
    .m_axi_bvalid    (demosaic_bvalid),
    .m_axi_bready    (demosaic_bready),
    .m_axi_araddr    (demosaic_araddr),
    .m_axi_arprot    (),
    .m_axi_arvalid   (demosaic_arvalid),
    .m_axi_arready   (demosaic_arready),
    .m_axi_rdata     (demosaic_rdata),
    .m_axi_rresp     (demosaic_rresp),
    .m_axi_rvalid    (demosaic_rvalid),
    .m_axi_rready    (demosaic_rready)
);

design_1_v_demosaic_0_1 u_demosaic (
    .s_axi_CTRL_AWADDR     (demosaic_awaddr),
    .s_axi_CTRL_AWVALID    (demosaic_awvalid),
    .s_axi_CTRL_AWREADY    (demosaic_awready),
    .s_axi_CTRL_WDATA      (demosaic_wdata),
    .s_axi_CTRL_WSTRB      (demosaic_wstrb),
    .s_axi_CTRL_WVALID     (demosaic_wvalid),
    .s_axi_CTRL_WREADY     (demosaic_wready),
    .s_axi_CTRL_BRESP      (demosaic_bresp),
    .s_axi_CTRL_BVALID     (demosaic_bvalid),
    .s_axi_CTRL_BREADY     (demosaic_bready),
    .s_axi_CTRL_ARADDR     (demosaic_araddr),
    .s_axi_CTRL_ARVALID    (demosaic_arvalid),
    .s_axi_CTRL_ARREADY    (demosaic_arready),
    .s_axi_CTRL_RDATA      (demosaic_rdata),
    .s_axi_CTRL_RRESP      (demosaic_rresp),
    .s_axi_CTRL_RVALID     (demosaic_rvalid),
    .s_axi_CTRL_RREADY     (demosaic_rready),
    .ap_clk                (video_aclk),
    .ap_rst_n              (video_aresetn),
    .interrupt             (demosaic_irq),
    .s_axis_video_TVALID   (csi_tvalid),
    .s_axis_video_TREADY   (csi_tready),
    .s_axis_video_TDATA    (csi_tdata),
    .s_axis_video_TKEEP    (2'b11),
    .s_axis_video_TSTRB    (2'b11),
    .s_axis_video_TUSER    (csi_tuser),
    .s_axis_video_TLAST    (csi_tlast),
    .s_axis_video_TID      (1'b0),
    .s_axis_video_TDEST    (csi_tdest[0]),
    .m_axis_video_TVALID   (demosaic_tvalid),
    .m_axis_video_TREADY   (demosaic_tready),
    .m_axis_video_TDATA    (demosaic_tdata),
    .m_axis_video_TKEEP    (demosaic_tkeep),
    .m_axis_video_TSTRB    (demosaic_tstrb),
    .m_axis_video_TUSER    (demosaic_tuser),
    .m_axis_video_TLAST    (demosaic_tlast),
    .m_axis_video_TID      (demosaic_tid),
    .m_axis_video_TDEST    (demosaic_tdest)
);

design_1_auto_cc_1 u_gamma_ctrl_cdc (
    .s_axi_aclk      (ctrl_aclk),
    .s_axi_aresetn   (ctrl_aresetn),
    .s_axi_awaddr    (s_axi_awaddr[12:0]),
    .s_axi_awprot    (s_axi_awprot),
    .s_axi_awvalid   (gammax_awvalid),
    .s_axi_awready   (gammax_awready),
    .s_axi_wdata     (s_axi_wdata),
    .s_axi_wstrb     (s_axi_wstrb),
    .s_axi_wvalid    (gammax_wvalid),
    .s_axi_wready    (gammax_wready),
    .s_axi_bresp     (gammax_bresp),
    .s_axi_bvalid    (gammax_bvalid),
    .s_axi_bready    (s_axi_bready),
    .s_axi_araddr    (s_axi_araddr[12:0]),
    .s_axi_arprot    (s_axi_arprot),
    .s_axi_arvalid   (gammax_arvalid),
    .s_axi_arready   (gammax_arready),
    .s_axi_rdata     (gammax_rdata),
    .s_axi_rresp     (gammax_rresp),
    .s_axi_rvalid    (gammax_rvalid),
    .s_axi_rready    (s_axi_rready),
    .m_axi_aclk      (video_aclk),
    .m_axi_aresetn   (video_aresetn),
    .m_axi_awaddr    (gamma_awaddr),
    .m_axi_awprot    (),
    .m_axi_awvalid   (gamma_awvalid),
    .m_axi_awready   (gamma_awready),
    .m_axi_wdata     (gamma_wdata),
    .m_axi_wstrb     (gamma_wstrb),
    .m_axi_wvalid    (gamma_wvalid),
    .m_axi_wready    (gamma_wready),
    .m_axi_bresp     (gamma_bresp),
    .m_axi_bvalid    (gamma_bvalid),
    .m_axi_bready    (gamma_bready),
    .m_axi_araddr    (gamma_araddr),
    .m_axi_arprot    (),
    .m_axi_arvalid   (gamma_arvalid),
    .m_axi_arready   (gamma_arready),
    .m_axi_rdata     (gamma_rdata),
    .m_axi_rresp     (gamma_rresp),
    .m_axi_rvalid    (gamma_rvalid),
    .m_axi_rready    (gamma_rready)
);

design_1_v_gamma_lut_0_1 u_gamma (
    .s_axi_CTRL_AWADDR     (gamma_awaddr),
    .s_axi_CTRL_AWVALID    (gamma_awvalid),
    .s_axi_CTRL_AWREADY    (gamma_awready),
    .s_axi_CTRL_WDATA      (gamma_wdata),
    .s_axi_CTRL_WSTRB      (gamma_wstrb),
    .s_axi_CTRL_WVALID     (gamma_wvalid),
    .s_axi_CTRL_WREADY     (gamma_wready),
    .s_axi_CTRL_BRESP      (gamma_bresp),
    .s_axi_CTRL_BVALID     (gamma_bvalid),
    .s_axi_CTRL_BREADY     (gamma_bready),
    .s_axi_CTRL_ARADDR     (gamma_araddr),
    .s_axi_CTRL_ARVALID    (gamma_arvalid),
    .s_axi_CTRL_ARREADY    (gamma_arready),
    .s_axi_CTRL_RDATA      (gamma_rdata),
    .s_axi_CTRL_RRESP      (gamma_rresp),
    .s_axi_CTRL_RVALID     (gamma_rvalid),
    .s_axi_CTRL_RREADY     (gamma_rready),
    .ap_clk                (video_aclk),
    .ap_rst_n              (video_aresetn),
    .interrupt             (gamma_irq),
    .s_axis_video_TVALID   (demosaic_tvalid),
    .s_axis_video_TREADY   (demosaic_tready),
    .s_axis_video_TDATA    (demosaic_tdata),
    .s_axis_video_TKEEP    (demosaic_tkeep),
    .s_axis_video_TSTRB    (demosaic_tstrb),
    .s_axis_video_TUSER    (demosaic_tuser),
    .s_axis_video_TLAST    (demosaic_tlast),
    .s_axis_video_TID      (demosaic_tid),
    .s_axis_video_TDEST    (demosaic_tdest),
    .m_axis_video_TVALID   (gamma_tvalid),
    .m_axis_video_TREADY   (gamma_tready),
    .m_axis_video_TDATA    (gamma_tdata),
    .m_axis_video_TKEEP    (gamma_tkeep),
    .m_axis_video_TSTRB    (gamma_tstrb),
    .m_axis_video_TUSER    (gamma_tuser),
    .m_axis_video_TLAST    (gamma_tlast),
    .m_axis_video_TID      (gamma_tid),
    .m_axis_video_TDEST    (gamma_tdest)
);

design_1_axis_subset_converter_0_0 u_axis_subset (
    .aclk           (video_aclk),
    .aresetn        (video_aresetn),
    .s_axis_tvalid  (gamma_tvalid),
    .s_axis_tready  (gamma_tready),
    .s_axis_tdata   (gamma_tdata),
    .s_axis_tstrb   (gamma_tstrb),
    .s_axis_tkeep   (gamma_tkeep),
    .s_axis_tlast   (gamma_tlast[0]),
    .s_axis_tid     (gamma_tid),
    .s_axis_tdest   (gamma_tdest),
    .s_axis_tuser   (gamma_tuser),
    .m_axis_tvalid  (m_axis_tvalid),
    .m_axis_tready  (m_axis_tready),
    .m_axis_tdata   (m_axis_tdata),
    .m_axis_tstrb   (subset_tstrb),
    .m_axis_tkeep   (subset_tkeep),
    .m_axis_tlast   (m_axis_tlast),
    .m_axis_tid     (subset_tid),
    .m_axis_tdest   (subset_tdest),
    .m_axis_tuser   (subset_tuser)
);

assign m_axis_tuser = subset_tuser[0];

wire _unused_axis = ^{rxbyteclkhs, subset_tkeep, subset_tstrb, subset_tid, subset_tdest};

endmodule

`resetall
