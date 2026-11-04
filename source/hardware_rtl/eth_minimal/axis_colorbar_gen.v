`timescale 1ns / 1ps
`default_nettype none

module axis_colorbar_gen #
(
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer FRAME_PERIOD_CYCLES = 12500000,
    parameter integer MOTION_STEP_PIXELS = 0
)
(
    input  wire        clk,
    input  wire        rst,

    output wire [23:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire        m_axis_tuser
);

localparam integer BAR_1 = FRAME_WIDTH/8;
localparam integer BAR_2 = (FRAME_WIDTH*2)/8;
localparam integer BAR_3 = (FRAME_WIDTH*3)/8;
localparam integer BAR_4 = (FRAME_WIDTH*4)/8;
localparam integer BAR_5 = (FRAME_WIDTH*5)/8;
localparam integer BAR_6 = (FRAME_WIDTH*6)/8;
localparam integer BAR_7 = (FRAME_WIDTH*7)/8;
localparam integer MOTION_STEP_MOD = MOTION_STEP_PIXELS % FRAME_WIDTH;
localparam [16:0] FRAME_WIDTH_VALUE = FRAME_WIDTH;
localparam [16:0] MOTION_STEP_VALUE = MOTION_STEP_MOD;

reg [15:0] x_reg = 16'd0;
reg [15:0] y_reg = 16'd0;
reg [15:0] x_offset_reg = 16'd0;
reg [31:0] period_count_reg = 32'd0;
reg        active_reg = 1'b1;

wire frame_last_pixel = x_reg == FRAME_WIDTH-1 && y_reg == FRAME_HEIGHT-1;
wire line_last_pixel = x_reg == FRAME_WIDTH-1;
wire axis_beat = m_axis_tvalid && m_axis_tready;
wire period_done = FRAME_PERIOD_CYCLES <= 1 ||
                   period_count_reg >= FRAME_PERIOD_CYCLES-1;
wire [16:0] color_x_unwrapped = {1'b0, x_reg} + FRAME_WIDTH_VALUE - {1'b0, x_offset_reg};
wire [16:0] color_x_wrapped = color_x_unwrapped >= FRAME_WIDTH_VALUE ?
                              color_x_unwrapped - FRAME_WIDTH_VALUE :
                              color_x_unwrapped;
wire [16:0] next_x_offset_unwrapped = {1'b0, x_offset_reg} + MOTION_STEP_VALUE;
wire [16:0] next_x_offset_wrapped = next_x_offset_unwrapped >= FRAME_WIDTH_VALUE ?
                                    next_x_offset_unwrapped - FRAME_WIDTH_VALUE :
                                    next_x_offset_unwrapped;

assign m_axis_tvalid = active_reg;
assign m_axis_tdata = color_for_x(color_x_wrapped[15:0]);
assign m_axis_tlast = active_reg && line_last_pixel;
assign m_axis_tuser = active_reg && x_reg == 16'd0 && y_reg == 16'd0;

function [23:0] color_for_x;
    input [15:0] x;
    begin
        if (x < BAR_1) begin
            color_for_x = 24'hff_ffff; // white
        end else if (x < BAR_2) begin
            color_for_x = 24'hff_ff00; // yellow
        end else if (x < BAR_3) begin
            color_for_x = 24'h00_ffff; // cyan
        end else if (x < BAR_4) begin
            color_for_x = 24'h00_ff00; // green
        end else if (x < BAR_5) begin
            color_for_x = 24'hff_00ff; // magenta
        end else if (x < BAR_6) begin
            color_for_x = 24'hff_0000; // red
        end else if (x < BAR_7) begin
            color_for_x = 24'h00_00ff; // blue
        end else begin
            color_for_x = 24'h00_0000; // black
        end
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        x_reg <= 16'd0;
        y_reg <= 16'd0;
        x_offset_reg <= 16'd0;
        period_count_reg <= 32'd0;
        active_reg <= 1'b1;
    end else begin
        if (!period_done) begin
            period_count_reg <= period_count_reg + 32'd1;
        end

        if (active_reg) begin
            if (axis_beat) begin
                if (frame_last_pixel) begin
                    x_reg <= 16'd0;
                    y_reg <= 16'd0;
                    x_offset_reg <= next_x_offset_wrapped[15:0];

                    if (period_done) begin
                        period_count_reg <= 32'd0;
                        active_reg <= 1'b1;
                    end else begin
                        active_reg <= 1'b0;
                    end
                end else if (line_last_pixel) begin
                    x_reg <= 16'd0;
                    y_reg <= y_reg + 16'd1;
                end else begin
                    x_reg <= x_reg + 16'd1;
                end
            end
        end else if (period_done) begin
            period_count_reg <= 32'd0;
            active_reg <= 1'b1;
        end
    end
end

endmodule

`resetall
