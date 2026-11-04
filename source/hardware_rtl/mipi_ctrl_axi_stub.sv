//==============================================================================
// File Name   : mipi_ctrl_axi_stub.sv
// Description :
//   Temporary AXI4-Lite endpoint for the MIPI/HLS control aperture.
//
//   This keeps the PS-visible 0x400C_0000 window responsive while the real
//   CSI2/demosaic/gamma AXI-Lite interconnect is being migrated.
//==============================================================================

module mipi_ctrl_axi_stub #(
    parameter int ADDR_WIDTH = 18
)(
    input                       S_AXI_ACLK,
    input                       S_AXI_ARESETN,

    input      [ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input      [2:0]            S_AXI_AWPROT,
    input                       S_AXI_AWVALID,
    output reg                  S_AXI_AWREADY,

    input      [31:0]           S_AXI_WDATA,
    input      [3:0]            S_AXI_WSTRB,
    input                       S_AXI_WVALID,
    output reg                  S_AXI_WREADY,

    output     [1:0]            S_AXI_BRESP,
    output reg                  S_AXI_BVALID,
    input                       S_AXI_BREADY,

    input      [ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input      [2:0]            S_AXI_ARPROT,
    input                       S_AXI_ARVALID,
    output reg                  S_AXI_ARREADY,

    output reg [31:0]           S_AXI_RDATA,
    output     [1:0]            S_AXI_RRESP,
    output reg                  S_AXI_RVALID,
    input                       S_AXI_RREADY
);

localparam [31:0] REG_ID          = 32'h4D49_5049; // "MIPI"
localparam [31:0] REG_VERSION     = 32'h0001_0000;
localparam [31:0] REG_WINDOW_SIZE = 32'h0000_4000;

reg [31:0] control_reg;
reg [31:0] scratch0_reg;
reg [31:0] scratch1_reg;

wire write_fire = S_AXI_AWVALID && S_AXI_WVALID && S_AXI_AWREADY && S_AXI_WREADY;
wire read_fire  = S_AXI_ARVALID && S_AXI_ARREADY;

assign S_AXI_BRESP = 2'b00;
assign S_AXI_RRESP = 2'b00;

wire _unused_axi = ^{S_AXI_AWPROT, S_AXI_ARPROT};

function [31:0] apply_wstrb;
    input [31:0] old_data;
    input [31:0] new_data;
    input [3:0]  wstrb;
    integer      byte_idx;
    begin
        apply_wstrb = old_data;
        for (byte_idx = 0; byte_idx < 4; byte_idx = byte_idx + 1) begin
            if (wstrb[byte_idx]) begin
                apply_wstrb[byte_idx*8 +: 8] = new_data[byte_idx*8 +: 8];
            end
        end
    end
endfunction

function [31:0] read_reg;
    input [ADDR_WIDTH-1:0] addr;
    begin
        case (addr[7:0])
            8'h00: read_reg = REG_ID;
            8'h04: read_reg = REG_VERSION;
            8'h08: read_reg = control_reg;
            8'h0c: read_reg = {31'd0, control_reg[0]};
            8'h14: read_reg = REG_WINDOW_SIZE;
            8'h20: read_reg = scratch0_reg;
            8'h24: read_reg = scratch1_reg;
            default: read_reg = 32'hDEAD_4D49;
        endcase
    end
endfunction

always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        S_AXI_AWREADY <= 1'b0;
        S_AXI_WREADY  <= 1'b0;
        S_AXI_BVALID  <= 1'b0;
        S_AXI_ARREADY <= 1'b0;
        S_AXI_RDATA   <= 32'd0;
        S_AXI_RVALID  <= 1'b0;
        control_reg   <= 32'd0;
        scratch0_reg  <= 32'd0;
        scratch1_reg  <= 32'd0;
    end else begin
        S_AXI_AWREADY <= !S_AXI_BVALID && S_AXI_AWVALID && S_AXI_WVALID;
        S_AXI_WREADY  <= !S_AXI_BVALID && S_AXI_AWVALID && S_AXI_WVALID;
        S_AXI_ARREADY <= !S_AXI_RVALID && S_AXI_ARVALID;

        if (write_fire) begin
            case (S_AXI_AWADDR[7:0])
                8'h08: control_reg  <= apply_wstrb(control_reg, S_AXI_WDATA, S_AXI_WSTRB);
                8'h20: scratch0_reg <= apply_wstrb(scratch0_reg, S_AXI_WDATA, S_AXI_WSTRB);
                8'h24: scratch1_reg <= apply_wstrb(scratch1_reg, S_AXI_WDATA, S_AXI_WSTRB);
                default: begin
                    control_reg  <= control_reg;
                    scratch0_reg <= scratch0_reg;
                    scratch1_reg <= scratch1_reg;
                end
            endcase
            S_AXI_BVALID <= 1'b1;
        end else if (S_AXI_BVALID && S_AXI_BREADY) begin
            S_AXI_BVALID <= 1'b0;
        end

        if (read_fire) begin
            S_AXI_RDATA  <= read_reg(S_AXI_ARADDR);
            S_AXI_RVALID <= 1'b1;
        end else if (S_AXI_RVALID && S_AXI_RREADY) begin
            S_AXI_RVALID <= 1'b0;
        end
    end
end

endmodule
