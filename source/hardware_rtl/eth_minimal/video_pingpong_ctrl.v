`timescale 1ns / 1ps
`default_nettype none

module video_pingpong_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire [31:0] base0_byte_addr,
    input  wire [31:0] base1_byte_addr,

    input  wire        writer_frame_start_pulse,
    input  wire        writer_frame_done_pulse,
    input  wire        reader_frame_done_pulse,
    input  wire        reader_frame_active,

    output wire [31:0] writer_base_byte_addr,
    output wire [31:0] reader_base_byte_addr,
    output reg         reader_start,

    output wire        writer_buf_index,
    output wire        reader_buf_index,
    output wire        latest_buf_index,
    output wire        latest_frame_valid,
    output wire        reader_frame_valid
);

reg writer_buf_reg = 1'b0;
reg reader_buf_reg = 1'b0;
reg latest_buf_reg = 1'b0;
reg latest_valid_reg = 1'b0;
reg reader_valid_reg = 1'b0;
reg writer_busy_reg = 1'b0;
reg reader_start_pending_reg = 1'b0;

reg next_writer_buf;
reg next_reader_buf;
reg next_latest_buf;
reg next_latest_valid;
reg next_reader_valid;
reg next_writer_busy;
reg next_reader_start_pending;

assign writer_base_byte_addr = writer_buf_reg ? base1_byte_addr : base0_byte_addr;
assign reader_base_byte_addr = reader_buf_reg ? base1_byte_addr : base0_byte_addr;

assign writer_buf_index = writer_buf_reg;
assign reader_buf_index = reader_buf_reg;
assign latest_buf_index = latest_buf_reg;
assign latest_frame_valid = latest_valid_reg;
assign reader_frame_valid = reader_valid_reg;

always @* begin
    next_writer_buf = writer_buf_reg;
    next_reader_buf = reader_buf_reg;
    next_latest_buf = latest_buf_reg;
    next_latest_valid = latest_valid_reg;
    next_reader_valid = reader_valid_reg;
    next_writer_busy = writer_busy_reg;
    next_reader_start_pending = reader_start_pending_reg;

    if (writer_frame_start_pulse) begin
        next_writer_busy = 1'b1;
        if (latest_valid_reg && latest_buf_reg == writer_buf_reg) begin
            next_latest_valid = 1'b0;
        end
    end

    if (writer_frame_done_pulse) begin
        next_writer_busy = 1'b0;
        next_latest_buf = writer_buf_reg;
        next_latest_valid = 1'b1;

        if (reader_valid_reg && (~writer_buf_reg) == reader_buf_reg) begin
            next_writer_buf = writer_buf_reg;
        end else begin
            next_writer_buf = ~writer_buf_reg;
        end
    end

    if (!reader_frame_active && !reader_start && !reader_start_pending_reg) begin
        if (next_latest_valid) begin
            if (!next_reader_valid || next_latest_buf != reader_buf_reg) begin
                next_reader_buf = next_latest_buf;
                next_reader_valid = 1'b1;
                next_latest_valid = 1'b0;
                next_reader_start_pending = 1'b1;

                if (!next_writer_busy && next_writer_buf == next_latest_buf) begin
                    next_writer_buf = ~next_latest_buf;
                end
            end else if (next_reader_valid) begin
                next_latest_valid = 1'b0;
                next_reader_start_pending = 1'b1;
            end
        end else if (next_reader_valid || reader_frame_done_pulse) begin
            next_reader_start_pending = next_reader_valid;
        end
    end
end

always @(posedge clk) begin
    if (rst || !enable) begin
        writer_buf_reg <= 1'b0;
        reader_buf_reg <= 1'b0;
        latest_buf_reg <= 1'b0;
        latest_valid_reg <= 1'b0;
        reader_valid_reg <= 1'b0;
        writer_busy_reg <= 1'b0;
        reader_start_pending_reg <= 1'b0;
        reader_start <= 1'b0;
    end else begin
        reader_start <= 1'b0;

        writer_buf_reg <= next_writer_buf;
        reader_buf_reg <= next_reader_buf;
        latest_buf_reg <= next_latest_buf;
        latest_valid_reg <= next_latest_valid;
        reader_valid_reg <= next_reader_valid;
        writer_busy_reg <= next_writer_busy;
        reader_start_pending_reg <= next_reader_start_pending;

        if (reader_start_pending_reg) begin
            reader_start <= 1'b1;
            reader_start_pending_reg <= 1'b0;
        end
    end
end

endmodule

`resetall
