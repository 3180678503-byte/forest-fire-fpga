//==============================================================================
// File Name     : mna_gp2axi_lite_mipi.sv
// Description   :
//   MIPI control bridge from the local MNA GP register bus to AXI4-Lite.
//
//   This bridge is intended for the MIPI camera control aperture that replaces
//   the original MicroBlaze control path. Keep ADDR_WIDTH wide enough for the
//   AXI-Lite interconnect that fans out to CSI/demosaic/gamma blocks.
//==============================================================================

module mna_gp2axi_lite_mipi #(
    parameter int ADDR_WIDTH = 18
)(
    mna_gp_ww_itf.slave         gpx,
    input                       gpx_clk,
    input                       gpx_rst,

    // AXI4-Lite master toward the MIPI control interconnect.
    output                      S_AXI_ACLK,
    output                      S_AXI_ARESETN,

    output      [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    output      [2:0]            S_AXI_AWPROT,
    output                       S_AXI_AWVALID,
    input                        S_AXI_AWREADY,

    output      [31:0]           S_AXI_WDATA,
    output      [3:0]            S_AXI_WSTRB,
    output                       S_AXI_WVALID,
    input                        S_AXI_WREADY,

    input       [1:0]            S_AXI_BRESP,
    input                        S_AXI_BVALID,
    output                       S_AXI_BREADY,

    output      [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    output      [2:0]            S_AXI_ARPROT,
    output                       S_AXI_ARVALID,
    input                        S_AXI_ARREADY,

    input       [31:0]           S_AXI_RDATA,
    input       [1:0]            S_AXI_RRESP,
    input                        S_AXI_RVALID,
    output                       S_AXI_RREADY
);

reg                      wr_active;
reg                      aw_pending;
reg                      w_pending;
reg  [ADDR_WIDTH-1:0]    awaddr_reg;
reg  [31:0]              wdata_reg;

wire aw_fire = aw_pending & S_AXI_AWREADY;
wire w_fire  = w_pending  & S_AXI_WREADY;
wire wr_done = wr_active &&
               ((~aw_pending) || S_AXI_AWREADY) &&
               ((~w_pending)  || S_AXI_WREADY);

assign S_AXI_ACLK    = gpx_clk;
assign S_AXI_ARESETN = ~gpx_rst;

// The MNA GP bus uses absolute addresses. The selected GP window base has
// already been decoded upstream, so AXI-Lite sees only the local offset inside
// that MIPI control aperture.
assign S_AXI_AWADDR  = awaddr_reg;
assign S_AXI_AWPROT  = 3'h0;
assign S_AXI_AWVALID = aw_pending;

assign gpx.awwready  = wr_done;

assign S_AXI_WDATA   = wdata_reg;
assign S_AXI_WSTRB   = 4'hf;
assign S_AXI_WVALID  = w_pending;

assign S_AXI_BREADY  = 1'b1;

assign S_AXI_ARADDR  = gpx.araddr[ADDR_WIDTH-1:0];
assign S_AXI_ARPROT  = 3'h0;
assign S_AXI_ARVALID = gpx.arvalid;

assign gpx.arready   = S_AXI_ARREADY;
assign gpx.rdata     = S_AXI_RDATA;
assign gpx.rvalid    = S_AXI_RVALID;
assign S_AXI_RREADY  = gpx.rready;

always @(posedge gpx_clk) begin
    if (gpx_rst) begin
        wr_active  <= 1'b0;
        aw_pending <= 1'b0;
        w_pending  <= 1'b0;
        awaddr_reg <= {ADDR_WIDTH{1'b0}};
        wdata_reg  <= 32'd0;
    end else begin
        if (!wr_active && gpx.awwvalid) begin
            wr_active  <= 1'b1;
            aw_pending <= 1'b1;
            w_pending  <= 1'b1;
            awaddr_reg <= gpx.awwaddr[ADDR_WIDTH-1:0];
            wdata_reg  <= gpx.awwdata;
        end else if (wr_active) begin
            if (aw_fire) begin
                aw_pending <= 1'b0;
            end

            if (w_fire) begin
                w_pending <= 1'b0;
            end

            if (wr_done) begin
                wr_active  <= 1'b0;
                aw_pending <= 1'b0;
                w_pending  <= 1'b0;
            end
        end
    end
end

endmodule
