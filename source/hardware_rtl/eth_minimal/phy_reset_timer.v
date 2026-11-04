`timescale 1ns / 1ps
`default_nettype none

module phy_reset_timer #
(
    parameter RESET_HOLD_CYCLES = 12500000
)
(
    input  wire clk,
    input  wire rst,
    output reg  phy_reset_n,
    output wire phy_ready
);

reg [31:0] reset_count = 32'd0;

assign phy_ready = phy_reset_n;

always @(posedge clk) begin
    if (rst) begin
        reset_count <= 32'd0;
        phy_reset_n <= 1'b0;
    end else if (RESET_HOLD_CYCLES <= 1) begin
        reset_count <= 32'd0;
        phy_reset_n <= 1'b1;
    end else if (reset_count < RESET_HOLD_CYCLES-1) begin
        reset_count <= reset_count + 32'd1;
        phy_reset_n <= 1'b0;
    end else begin
        reset_count <= reset_count;
        phy_reset_n <= 1'b1;
    end
end

endmodule

`resetall
