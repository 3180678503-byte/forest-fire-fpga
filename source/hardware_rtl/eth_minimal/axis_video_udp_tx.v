`timescale 1ns / 1ps
`default_nettype none

module axis_video_udp_tx #
(
    parameter [31:0] LOCAL_IP = {8'd192, 8'd168, 8'd1, 8'd88},
    parameter [31:0] REMOTE_IP = {8'd192, 8'd168, 8'd1, 8'd100},
    parameter [15:0] SRC_PORT = 16'd50000,
    parameter [15:0] DST_PORT = 16'd50001,
    parameter integer FRAME_WIDTH = 1920,
    parameter integer FRAME_HEIGHT = 1080,
    parameter integer PIXELS_PER_PACKET = 480,
    parameter integer APP_HEADER_BYTES = 16
)
(
    input  wire        clk,
    input  wire        rst,
    input  wire        flush_req,

    input  wire [23:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,

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

    output reg  [31:0] packet_count,
    output reg  [31:0] frame_count
);

localparam [2:0]
    ST_IDLE       = 3'd0,
    ST_UDP_HDR    = 3'd1,
    ST_APP_HDR    = 3'd2,
    ST_PIXEL_LOAD = 3'd3,
    ST_PIXEL_SEND = 3'd4;

localparam integer PACKET_PAYLOAD_BYTES = APP_HEADER_BYTES + PIXELS_PER_PACKET*3;

reg [2:0]  state_reg = ST_IDLE;
reg [15:0] app_hdr_index_reg = 16'd0;
reg [15:0] x_start_reg = 16'd0;
reg [15:0] y_reg = 16'd0;
reg [15:0] frame_id_reg = 16'd0;
reg [15:0] pixel_count_reg = 16'd0;
reg [1:0]  pixel_byte_index_reg = 2'd0;
reg [23:0] pixel_data_reg = 24'd0;
reg        synced_reg = 1'b0;
reg        abort_pending_reg = 1'b0;

wire packet_first = x_start_reg == 16'd0 && y_reg == 16'd0;
wire packet_last = x_start_reg + PIXELS_PER_PACKET >= FRAME_WIDTH &&
                   y_reg == FRAME_HEIGHT-1;
wire [7:0] packet_flags = {6'd0, packet_last, packet_first};

wire payload_last = state_reg == ST_PIXEL_SEND &&
                    pixel_byte_index_reg == 2'd2 &&
                    pixel_count_reg == PIXELS_PER_PACKET-1;
wire abort_payload = abort_pending_reg &&
                     (state_reg == ST_APP_HDR ||
                      state_reg == ST_PIXEL_LOAD ||
                      state_reg == ST_PIXEL_SEND);

assign s_axis_tready = !flush_req && !abort_pending_reg && state_reg == ST_PIXEL_LOAD;

assign tx_udp_hdr_valid = state_reg == ST_UDP_HDR;
assign tx_udp_ip_dscp = 6'd0;
assign tx_udp_ip_ecn = 2'd0;
assign tx_udp_ip_ttl = 8'd64;
assign tx_udp_ip_source_ip = LOCAL_IP;
assign tx_udp_ip_dest_ip = REMOTE_IP;
assign tx_udp_source_port = SRC_PORT;
assign tx_udp_dest_port = DST_PORT;
assign tx_udp_length = PACKET_PAYLOAD_BYTES[15:0] + 16'd8;
assign tx_udp_checksum = 16'd0;

assign tx_udp_payload_axis_tvalid = abort_payload ||
                                    state_reg == ST_APP_HDR ||
                                    state_reg == ST_PIXEL_SEND;
assign tx_udp_payload_axis_tdata = abort_payload ? 8'd0 :
                                   state_reg == ST_APP_HDR ?
                                   app_header_byte(app_hdr_index_reg[3:0]) :
                                   pixel_byte(pixel_byte_index_reg);
assign tx_udp_payload_axis_tlast = abort_payload || payload_last;
assign tx_udp_payload_axis_tuser = abort_payload;

function [7:0] app_header_byte;
    input [3:0] index;
    begin
        case (index)
            4'd0: app_header_byte = 8'h43; // C
            4'd1: app_header_byte = 8'h42; // B
            4'd2: app_header_byte = 8'h41; // A
            4'd3: app_header_byte = 8'h52; // R
            4'd4: app_header_byte = 8'd1;
            4'd5: app_header_byte = APP_HEADER_BYTES[7:0];
            4'd6: app_header_byte = packet_flags;
            4'd7: app_header_byte = 8'd0;
            4'd8: app_header_byte = frame_id_reg[15:8];
            4'd9: app_header_byte = frame_id_reg[7:0];
            4'd10: app_header_byte = y_reg[15:8];
            4'd11: app_header_byte = y_reg[7:0];
            4'd12: app_header_byte = x_start_reg[15:8];
            4'd13: app_header_byte = x_start_reg[7:0];
            4'd14: app_header_byte = PIXELS_PER_PACKET[15:8];
            default: app_header_byte = PIXELS_PER_PACKET[7:0];
        endcase
    end
endfunction

function [7:0] pixel_byte;
    input [1:0] index;
    begin
        case (index)
            2'd0: pixel_byte = pixel_data_reg[23:16];
            2'd1: pixel_byte = pixel_data_reg[15:8];
            default: pixel_byte = pixel_data_reg[7:0];
        endcase
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state_reg <= ST_IDLE;
        app_hdr_index_reg <= 16'd0;
        x_start_reg <= 16'd0;
        y_reg <= 16'd0;
        frame_id_reg <= 16'd0;
        pixel_count_reg <= 16'd0;
        pixel_byte_index_reg <= 2'd0;
        pixel_data_reg <= 24'd0;
        synced_reg <= 1'b0;
        abort_pending_reg <= 1'b0;
        packet_count <= 32'd0;
        frame_count <= 32'd0;
    end else begin
        if (flush_req && state_reg != ST_IDLE) begin
            abort_pending_reg <= 1'b1;
        end

        case (state_reg)
            ST_IDLE: begin
                app_hdr_index_reg <= 16'd0;
                pixel_count_reg <= 16'd0;
                pixel_byte_index_reg <= 2'd0;
                abort_pending_reg <= 1'b0;

                if (flush_req) begin
                    x_start_reg <= 16'd0;
                    y_reg <= 16'd0;
                    synced_reg <= 1'b0;
                end else if (s_axis_tvalid) begin
                    if (s_axis_tuser) begin
                        if (synced_reg && (x_start_reg != 16'd0 || y_reg != 16'd0)) begin
                            frame_id_reg <= frame_id_reg + 16'd1;
                        end
                        x_start_reg <= 16'd0;
                        y_reg <= 16'd0;
                        synced_reg <= 1'b1;
                        state_reg <= ST_UDP_HDR;
                    end else begin
                        synced_reg <= 1'b1;
                        state_reg <= ST_UDP_HDR;
                    end
                end
            end

            ST_UDP_HDR: begin
                if (tx_udp_hdr_ready) begin
                    app_hdr_index_reg <= 16'd0;
                    state_reg <= ST_APP_HDR;
                end
            end

            ST_APP_HDR: begin
                if (abort_payload && tx_udp_payload_axis_tready) begin
                    app_hdr_index_reg <= 16'd0;
                    pixel_count_reg <= 16'd0;
                    pixel_byte_index_reg <= 2'd0;
                    x_start_reg <= 16'd0;
                    y_reg <= 16'd0;
                    synced_reg <= 1'b0;
                    abort_pending_reg <= 1'b0;
                    state_reg <= ST_IDLE;
                end else if (tx_udp_payload_axis_tready) begin
                    if (app_hdr_index_reg == APP_HEADER_BYTES-1) begin
                        app_hdr_index_reg <= 16'd0;
                        state_reg <= ST_PIXEL_LOAD;
                    end else begin
                        app_hdr_index_reg <= app_hdr_index_reg + 16'd1;
                    end
                end
            end

            ST_PIXEL_LOAD: begin
                if (abort_payload && tx_udp_payload_axis_tready) begin
                    app_hdr_index_reg <= 16'd0;
                    pixel_count_reg <= 16'd0;
                    pixel_byte_index_reg <= 2'd0;
                    x_start_reg <= 16'd0;
                    y_reg <= 16'd0;
                    synced_reg <= 1'b0;
                    abort_pending_reg <= 1'b0;
                    state_reg <= ST_IDLE;
                end else if (s_axis_tvalid) begin
                    pixel_data_reg <= s_axis_tdata;
                    state_reg <= ST_PIXEL_SEND;
                end
            end

            ST_PIXEL_SEND: begin
                if (abort_payload && tx_udp_payload_axis_tready) begin
                    app_hdr_index_reg <= 16'd0;
                    pixel_count_reg <= 16'd0;
                    pixel_byte_index_reg <= 2'd0;
                    x_start_reg <= 16'd0;
                    y_reg <= 16'd0;
                    synced_reg <= 1'b0;
                    abort_pending_reg <= 1'b0;
                    state_reg <= ST_IDLE;
                end else if (tx_udp_payload_axis_tready) begin
                    if (pixel_byte_index_reg == 2'd2) begin
                        pixel_byte_index_reg <= 2'd0;

                        if (pixel_count_reg == PIXELS_PER_PACKET-1) begin
                            pixel_count_reg <= 16'd0;
                            packet_count <= packet_count + 32'd1;
                            state_reg <= ST_IDLE;

                            if (x_start_reg + PIXELS_PER_PACKET >= FRAME_WIDTH) begin
                                x_start_reg <= 16'd0;

                                if (y_reg == FRAME_HEIGHT-1) begin
                                    y_reg <= 16'd0;
                                    frame_id_reg <= frame_id_reg + 16'd1;
                                    frame_count <= frame_count + 32'd1;
                                end else begin
                                    y_reg <= y_reg + 16'd1;
                                end
                            end else begin
                                x_start_reg <= x_start_reg + PIXELS_PER_PACKET[15:0];
                            end
                        end else begin
                            pixel_count_reg <= pixel_count_reg + 16'd1;
                            state_reg <= ST_PIXEL_LOAD;
                        end
                    end else begin
                        pixel_byte_index_reg <= pixel_byte_index_reg + 2'd1;
                    end
                end
            end

            default: begin
                state_reg <= ST_IDLE;
                abort_pending_reg <= 1'b0;
            end
        endcase
    end
end

endmodule

`resetall
