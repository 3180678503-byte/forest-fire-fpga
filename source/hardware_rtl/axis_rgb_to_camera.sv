`timescale 1ns/1ps
`default_nettype none
// Synchronous RGB AXIS -> legacy camera video. Entire lines are buffered so
// source TVALID bubbles never become false line boundaries downstream.
module axis_rgb_to_camera #(
    parameter integer FRAME_WIDTH=1920,
    parameter integer FRAME_HEIGHT=1080,
    // Legacy PS writer round-trip request/ACK CDC resets its FIFO after VS.
    // Keep pixels out until that reset has completed (16 cycles was too short).
    parameter integer VSYNC_CYCLES=256,
    parameter integer LINE_GAP_CYCLES=8
)(
    input wire clk, input wire rst,
    input wire [23:0] s_tdata,
    input wire s_tvalid, output wire s_tready,
    input wire s_tuser, input wire s_tlast,
    output reg [23:0] cam_rgb,
    output reg cam_de, output reg cam_vs,
    output reg [31:0] frames_in, frames_out, lines_in, format_errors, stall_cycles
);
    (* ram_style="block" *) reg [23:0] line0 [0:FRAME_WIDTH-1];
    (* ram_style="block" *) reg [23:0] line1 [0:FRAME_WIDTH-1];
    reg [1:0] full, first_line;
    reg wr_bank, rd_bank, in_frame, wr_first;
    localparam integer X_BITS=(FRAME_WIDTH>1)?$clog2(FRAME_WIDTH):1;
    localparam integer Y_BITS=(FRAME_HEIGHT>1)?$clog2(FRAME_HEIGHT):1;
    localparam integer MAX_DELAY=(VSYNC_CYCLES>LINE_GAP_CYCLES)?VSYNC_CYCLES:LINE_GAP_CYCLES;
    localparam integer D_BITS=(MAX_DELAY>1)?$clog2(MAX_DELAY):1;
    reg [X_BITS-1:0] wr_x, rd_x;
    reg [Y_BITS-1:0] wr_y;
    reg [D_BITS-1:0] delay_count;
    localparam [1:0] WAIT_LINE=0, VERTICAL=1, PIXELS=2, LINE_GAP=3;
    reg [1:0] state;
    wire take=s_tvalid && s_tready;
    assign s_tready=!rst && !full[wr_bank];
    wire mem_write=take && (s_tuser || in_frame);
    wire [X_BITS-1:0] mem_waddr=s_tuser ? {X_BITS{1'b0}} : wr_x;
    // Prefetch the next pixel into the synchronous RAM output registers.
    wire [X_BITS-1:0] mem_raddr=(state==PIXELS && rd_x!=FRAME_WIDTH-1) ?
                                rd_x+1'b1 : {X_BITS{1'b0}};
    reg [23:0] read0, read1;
    always @(posedge clk) begin
        if(mem_write && !wr_bank) line0[mem_waddr]<=s_tdata;
        read0<=line0[mem_raddr];
    end
    always @(posedge clk) begin
        if(mem_write && wr_bank) line1[mem_waddr]<=s_tdata;
        read1<=line1[mem_raddr];
    end

    always @(posedge clk) begin
        if (rst) begin
            full<=0;first_line<=0;wr_bank<=0;rd_bank<=0;
            in_frame<=0;wr_first<=0;wr_x<=0;wr_y<=0;rd_x<=0;
            state<=WAIT_LINE;delay_count<=0;cam_de<=0;cam_vs<=0;cam_rgb<=0;
            frames_in<=0;frames_out<=0;lines_in<=0;format_errors<=0;stall_cycles<=0;
        end else begin
            cam_de<=0;
            cam_vs<=0;
            if (s_tvalid && !s_tready) stall_cycles<=stall_cycles+1;
            if (take) begin
                if (s_tuser) begin
                    // A fresh SOF also provides recovery after malformed input.
                    if (in_frame) format_errors<=format_errors+1;
                    in_frame<=1;wr_x<=1;wr_y<=0;wr_first<=1;
                    if(s_tlast) begin
                        format_errors<=format_errors+1;in_frame<=0;wr_x<=0;
                    end
                end else if (in_frame) begin
                    if(s_tlast != (wr_x==FRAME_WIDTH-1)) begin
                        // Drop this incomplete line and ignore data until next SOF.
                        format_errors<=format_errors+1;in_frame<=0;wr_x<=0;
                    end else if(s_tlast) begin
                        full[wr_bank]<=1;first_line[wr_bank]<=wr_first;
                        lines_in<=lines_in+1;wr_bank<=!wr_bank;wr_x<=0;wr_first<=0;
                        if(wr_y==FRAME_HEIGHT-1) begin
                            frames_in<=frames_in+1;in_frame<=0;wr_y<=0;
                        end else wr_y<=wr_y+1;
                    end else wr_x<=wr_x+1;
                end
            end
            case(state)
                WAIT_LINE: if(full[rd_bank]) begin
                    rd_x<=0;
                    if(first_line[rd_bank]) begin
                        cam_vs<=1;delay_count<=VSYNC_CYCLES-1;
                        frames_out<=frames_out+1;state<=VERTICAL;
                    end else state<=PIXELS;
                end
                VERTICAL: begin
                    if(delay_count>0) begin cam_vs<=1;delay_count<=delay_count-1;end
                    else state<=PIXELS;
                end
                PIXELS: begin
                    cam_de<=1;
                    cam_rgb<=rd_bank ? read1 : read0;
                    if(rd_x==FRAME_WIDTH-1) begin
                        full[rd_bank]<=0;rd_bank<=!rd_bank;rd_x<=0;
                        delay_count<=LINE_GAP_CYCLES-1;state<=LINE_GAP;
                    end else rd_x<=rd_x+1;
                end
                LINE_GAP: begin
                    if(delay_count>0) delay_count<=delay_count-1;
                    else state<=WAIT_LINE;
                end
                default: state<=WAIT_LINE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(FRAME_WIDTH<2 || FRAME_HEIGHT<1 || VSYNC_CYCLES<1 || LINE_GAP_CYCLES<1)
            $fatal(1,"Invalid camera bridge dimensions/timing");
    end
`endif
endmodule
`default_nettype wire
