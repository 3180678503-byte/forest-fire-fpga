`timescale 1ns / 1ps
`default_nettype none

module mig_to_axis_video_reader #
(
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer APP_DATA_WIDTH = 512,
    parameter integer APP_DATA_BYTES = APP_DATA_WIDTH / 8
)
(
    input  wire                       clk,
    input  wire                       rst,
    input  wire                       enable,
    input  wire                       start,
    input  wire [31:0]                base_byte_addr,

    output wire [28:0]                app_addr,
    output wire [2:0]                 app_cmd,
    output wire                       app_en,
    output wire [APP_DATA_WIDTH-1:0]  app_wdf_data,
    output wire                       app_wdf_end,
    output wire [APP_DATA_BYTES-1:0]  app_wdf_mask,
    output wire                       app_wdf_wren,
    input  wire [APP_DATA_WIDTH-1:0]  app_rd_data,
    input  wire                       app_rd_data_valid,
    input  wire                       app_rdy,
    output wire                       app_read_pending,

    output wire [23:0]                m_axis_tdata,
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,
    output wire                       m_axis_tlast,
    output wire                       m_axis_tuser,

    output reg                        frame_active,
    output reg                        frame_done_pulse
);

localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
localparam integer FRAME_BYTES = FRAME_PIXELS * 3;
localparam integer FRAME_BEATS = FRAME_BYTES / APP_DATA_BYTES;
localparam integer PIXEL_COUNT_WIDTH = FRAME_PIXELS <= 2 ? 1 : $clog2(FRAME_PIXELS + 1);
localparam integer X_COUNT_WIDTH = FRAME_WIDTH <= 2 ? 1 : $clog2(FRAME_WIDTH + 1);
localparam integer BEAT_COUNT_WIDTH = FRAME_BEATS <= 2 ? 1 : $clog2(FRAME_BEATS + 1);
localparam integer BYTE_COUNT_WIDTH = APP_DATA_BYTES <= 2 ? 3 : $clog2(APP_DATA_BYTES * 2 + 4);
localparam integer BUFFER_WIDTH = APP_DATA_WIDTH * 2;

localparam [PIXEL_COUNT_WIDTH-1:0] FRAME_PIXELS_VALUE = FRAME_PIXELS;
localparam [X_COUNT_WIDTH-1:0] FRAME_WIDTH_VALUE = FRAME_WIDTH;
localparam [BEAT_COUNT_WIDTH-1:0] FRAME_BEATS_VALUE = FRAME_BEATS;
localparam [BYTE_COUNT_WIDTH-1:0] APP_DATA_BYTES_VALUE = APP_DATA_BYTES;
localparam [31:0] APP_DATA_BYTES_32 = APP_DATA_BYTES;

reg [BUFFER_WIDTH-1:0] byte_buffer_reg = {BUFFER_WIDTH{1'b0}};
reg [BYTE_COUNT_WIDTH-1:0] byte_count_reg = {BYTE_COUNT_WIDTH{1'b0}};
reg [PIXEL_COUNT_WIDTH-1:0] pixel_count_reg = {PIXEL_COUNT_WIDTH{1'b0}};
reg [X_COUNT_WIDTH-1:0] x_count_reg = {X_COUNT_WIDTH{1'b0}};
reg [BEAT_COUNT_WIDTH-1:0] issued_beats_reg = {BEAT_COUNT_WIDTH{1'b0}};
reg [31:0] cmd_byte_addr_reg = 32'd0;
reg read_outstanding_reg = 1'b0;

wire axis_beat = m_axis_tvalid && m_axis_tready;
wire last_frame_pixel = pixel_count_reg == FRAME_PIXELS_VALUE - {{(PIXEL_COUNT_WIDTH-1){1'b0}}, 1'b1};
wire line_last_pixel = x_count_reg == FRAME_WIDTH_VALUE - {{(X_COUNT_WIDTH-1){1'b0}}, 1'b1};
wire buffer_has_cmd_space = byte_count_reg <= APP_DATA_BYTES_VALUE;
wire can_issue_read = frame_active &&
                      issued_beats_reg < FRAME_BEATS_VALUE &&
                      !read_outstanding_reg &&
                      buffer_has_cmd_space;
wire cmd_fire = app_read_pending && app_rdy;

assign app_read_pending = enable && can_issue_read;
assign app_addr = cmd_byte_addr_reg[31:3];
assign app_cmd = 3'd1;
assign app_en = cmd_fire;
assign app_wdf_data = {APP_DATA_WIDTH{1'b0}};
assign app_wdf_end = 1'b0;
assign app_wdf_mask = {APP_DATA_BYTES{1'b0}};
assign app_wdf_wren = 1'b0;

assign m_axis_tvalid = enable && frame_active && byte_count_reg >= {{(BYTE_COUNT_WIDTH-2){1'b0}}, 2'd3};
assign m_axis_tdata = {byte_buffer_reg[7:0], byte_buffer_reg[15:8], byte_buffer_reg[23:16]};
assign m_axis_tlast = m_axis_tvalid && line_last_pixel;
assign m_axis_tuser = m_axis_tvalid && pixel_count_reg == {PIXEL_COUNT_WIDTH{1'b0}};

function [BUFFER_WIDTH-1:0] append_read_word;
    input [BUFFER_WIDTH-1:0] buffer_in;
    input [BYTE_COUNT_WIDTH-1:0] byte_count_in;
    input [APP_DATA_WIDTH-1:0] word_in;
    reg   [BUFFER_WIDTH-1:0] word_ext;
    integer shift_bits;
    begin
        word_ext = {{APP_DATA_WIDTH{1'b0}}, word_in};
        shift_bits = byte_count_in * 8;
        append_read_word = buffer_in | (word_ext << shift_bits);
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        byte_buffer_reg <= {BUFFER_WIDTH{1'b0}};
        byte_count_reg <= {BYTE_COUNT_WIDTH{1'b0}};
        pixel_count_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
        x_count_reg <= {X_COUNT_WIDTH{1'b0}};
        issued_beats_reg <= {BEAT_COUNT_WIDTH{1'b0}};
        cmd_byte_addr_reg <= base_byte_addr;
        read_outstanding_reg <= 1'b0;
        frame_active <= 1'b0;
        frame_done_pulse <= 1'b0;
    end else begin
        frame_done_pulse <= 1'b0;

        if (start) begin
            byte_buffer_reg <= {BUFFER_WIDTH{1'b0}};
            byte_count_reg <= {BYTE_COUNT_WIDTH{1'b0}};
            pixel_count_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
            x_count_reg <= {X_COUNT_WIDTH{1'b0}};
            issued_beats_reg <= {BEAT_COUNT_WIDTH{1'b0}};
            cmd_byte_addr_reg <= base_byte_addr;
            read_outstanding_reg <= 1'b0;
            frame_active <= 1'b1;
        end else begin
            if (cmd_fire) begin
                issued_beats_reg <= issued_beats_reg + {{(BEAT_COUNT_WIDTH-1){1'b0}}, 1'b1};
                cmd_byte_addr_reg <= cmd_byte_addr_reg + APP_DATA_BYTES_32;
                read_outstanding_reg <= 1'b1;
            end

            if (axis_beat && last_frame_pixel) begin
                byte_buffer_reg <= {BUFFER_WIDTH{1'b0}};
                byte_count_reg <= {BYTE_COUNT_WIDTH{1'b0}};
                pixel_count_reg <= {PIXEL_COUNT_WIDTH{1'b0}};
                x_count_reg <= {X_COUNT_WIDTH{1'b0}};
                issued_beats_reg <= {BEAT_COUNT_WIDTH{1'b0}};
                cmd_byte_addr_reg <= base_byte_addr;
                read_outstanding_reg <= 1'b0;
                frame_active <= 1'b0;
                frame_done_pulse <= 1'b1;
            end else begin
                if (axis_beat && app_rd_data_valid) begin
                    byte_buffer_reg <= append_read_word(byte_buffer_reg >> 24,
                                                        byte_count_reg - {{(BYTE_COUNT_WIDTH-2){1'b0}}, 2'd3},
                                                        app_rd_data);
                    byte_count_reg <= byte_count_reg - {{(BYTE_COUNT_WIDTH-2){1'b0}}, 2'd3} + APP_DATA_BYTES_VALUE;
                    read_outstanding_reg <= 1'b0;
                end else if (axis_beat) begin
                    byte_buffer_reg <= byte_buffer_reg >> 24;
                    byte_count_reg <= byte_count_reg - {{(BYTE_COUNT_WIDTH-2){1'b0}}, 2'd3};
                end else if (app_rd_data_valid) begin
                    byte_buffer_reg <= append_read_word(byte_buffer_reg, byte_count_reg, app_rd_data);
                    byte_count_reg <= byte_count_reg + APP_DATA_BYTES_VALUE;
                    read_outstanding_reg <= 1'b0;
                end

                if (axis_beat) begin
                    if (line_last_pixel) begin
                        x_count_reg <= {X_COUNT_WIDTH{1'b0}};
                    end else begin
                        x_count_reg <= x_count_reg + {{(X_COUNT_WIDTH-1){1'b0}}, 1'b1};
                    end
                    pixel_count_reg <= pixel_count_reg + {{(PIXEL_COUNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end
        end
    end
end

endmodule

`resetall
