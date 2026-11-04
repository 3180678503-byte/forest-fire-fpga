`timescale 1ns / 1ps
`default_nettype none

module eth_pll_125m (
    input  wire ref_clk_200mhz,
    input  wire rst,
    output wire clk_125m,
    output wire clk_125m_90,
    output wire locked
);

wire clkfb;
wire clkfb_buf;
wire clk_125m_pre;
wire clk_125m_90_pre;
wire [15:0] do_unused;
wire drdy_unused;

PLLE2_ADV #(
    .BANDWIDTH("OPTIMIZED"),
    .COMPENSATION("ZHOLD"),
    .STARTUP_WAIT("FALSE"),
    .DIVCLK_DIVIDE(1),
    .CLKFBOUT_MULT(5),
    .CLKFBOUT_PHASE(0.000),
    .CLKIN1_PERIOD(5.000),
    .CLKOUT0_DIVIDE(8),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .CLKOUT1_DIVIDE(8),
    .CLKOUT1_DUTY_CYCLE(0.500),
    .CLKOUT1_PHASE(90.000),
    .CLKOUT2_DIVIDE(8),
    .CLKOUT2_DUTY_CYCLE(0.500),
    .CLKOUT2_PHASE(0.000),
    .CLKOUT3_DIVIDE(8),
    .CLKOUT3_DUTY_CYCLE(0.500),
    .CLKOUT3_PHASE(0.000),
    .CLKOUT4_DIVIDE(8),
    .CLKOUT4_DUTY_CYCLE(0.500),
    .CLKOUT4_PHASE(0.000),
    .CLKOUT5_DIVIDE(8),
    .CLKOUT5_DUTY_CYCLE(0.500),
    .CLKOUT5_PHASE(0.000)
)
pll_inst (
    .CLKFBOUT(clkfb),
    .CLKOUT0 (clk_125m_pre),
    .CLKOUT1 (clk_125m_90_pre),
    .CLKOUT2 (),
    .CLKOUT3 (),
    .CLKOUT4 (),
    .CLKOUT5 (),
    .CLKFBIN (clkfb_buf),
    .CLKIN1  (ref_clk_200mhz),
    .CLKIN2  (1'b0),
    .CLKINSEL(1'b1),
    .DADDR   (7'd0),
    .DCLK    (1'b0),
    .DEN     (1'b0),
    .DI      (16'd0),
    .DO      (do_unused),
    .DRDY    (drdy_unused),
    .DWE     (1'b0),
    .LOCKED  (locked),
    .PWRDWN  (1'b0),
    .RST     (rst)
);

BUFG clkfb_buf_inst (
    .I(clkfb),
    .O(clkfb_buf)
);

BUFG clk_125m_buf_inst (
    .I(clk_125m_pre),
    .O(clk_125m)
);

BUFG clk_125m_90_buf_inst (
    .I(clk_125m_90_pre),
    .O(clk_125m_90)
);

endmodule

`resetall