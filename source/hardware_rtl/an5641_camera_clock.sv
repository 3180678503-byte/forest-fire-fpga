`timescale 1ns/1ps
// Keep the existing 1080p HDMI pixel domain at 148.5 MHz.
// 200 / 8 * 37.125 / 6.25 = 148.5 MHz; MMCM VCO = 928.125 MHz.
module an5641_camera_clock (
    input wire ref_clk_200m,
    input wire reset,
    output wire pixel_clk,
    output wire pixel_reset,
    output wire locked
);
    wire feedback_raw, feedback, pixel_raw;
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"), .COMPENSATION("ZHOLD"),
        .STARTUP_WAIT("FALSE"), .DIVCLK_DIVIDE(8),
        .CLKFBOUT_MULT_F(37.125), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(6.25), .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5), .CLKIN1_PERIOD(5.0)
    ) mmcm (
        .CLKIN1(ref_clk_200m), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(feedback), .CLKFBOUT(feedback_raw), .CLKOUT0(pixel_raw),
        .LOCKED(locked), .RST(reset), .PWRDWN(1'b0),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0)
    );
    BUFG feedback_buffer (.I(feedback_raw), .O(feedback));
    BUFG pixel_buffer (.I(pixel_raw), .O(pixel_clk));
    wire reset_async = reset || !locked;
    (* ASYNC_REG="TRUE" *) reg [2:0] reset_sync = 3'b111;
    always @(posedge pixel_clk or posedge reset_async)
        if (reset_async) reset_sync <= 3'b111;
        else reset_sync <= {reset_sync[1:0], 1'b0};
    assign pixel_reset = reset_sync[2];
endmodule
