`timescale 1ns / 1ps
`default_nettype none

module video_mode_ctrl #
(
    parameter integer DEBOUNCE_BITS = 20
)
(
    input  wire       clk,
    input  wire       rst,
    input  wire       button_raw,
    output reg  [1:0] mode,
    output reg        mode_pulse
);

reg button_meta_reg = 1'b0;
reg button_sync_reg = 1'b0;
reg button_stable_reg = 1'b0;
reg button_stable_d1_reg = 1'b0;
reg [DEBOUNCE_BITS-1:0] debounce_cnt_reg = {DEBOUNCE_BITS{1'b0}};

wire debounce_done = &debounce_cnt_reg;
wire button_rise = button_stable_reg && !button_stable_d1_reg;

always @(posedge clk) begin
    if (rst) begin
        button_meta_reg <= 1'b0;
        button_sync_reg <= 1'b0;
        button_stable_reg <= 1'b0;
        button_stable_d1_reg <= 1'b0;
        debounce_cnt_reg <= {DEBOUNCE_BITS{1'b0}};
        mode <= 2'd0;
        mode_pulse <= 1'b0;
    end else begin
        button_meta_reg <= button_raw;
        button_sync_reg <= button_meta_reg;
        button_stable_d1_reg <= button_stable_reg;
        mode_pulse <= 1'b0;

        if (button_sync_reg == button_stable_reg) begin
            debounce_cnt_reg <= {DEBOUNCE_BITS{1'b0}};
        end else begin
            debounce_cnt_reg <= debounce_cnt_reg + {{(DEBOUNCE_BITS-1){1'b0}}, 1'b1};
            if (debounce_done) begin
                button_stable_reg <= button_sync_reg;
                debounce_cnt_reg <= {DEBOUNCE_BITS{1'b0}};
            end
        end

        if (button_rise) begin
            mode_pulse <= 1'b1;
            if (mode == 2'd2) begin
                mode <= 2'd0;
            end else begin
                mode <= mode + 2'd1;
            end
        end
    end
end

endmodule

`resetall
