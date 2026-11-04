`timescale 1ns / 1ps
`default_nettype none

module axis_video_fifo #
(
    parameter integer DATA_WIDTH = 24,
    parameter integer DEPTH = 2048
)
(
    input  wire                  clk,
    input  wire                  rst,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,
    input  wire                  s_axis_tuser,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,
    output wire                  m_axis_tuser,

    output reg                   overflow
);

localparam integer ADDR_WIDTH = DEPTH <= 2 ? 1 : $clog2(DEPTH);
localparam integer COUNT_WIDTH = $clog2(DEPTH + 1);
localparam [COUNT_WIDTH-1:0] DEPTH_VALUE = DEPTH;

(* ram_style = "block" *) reg [DATA_WIDTH+1:0] mem [0:DEPTH-1];

reg [ADDR_WIDTH-1:0] wr_ptr_reg = {ADDR_WIDTH{1'b0}};
reg [ADDR_WIDTH-1:0] rd_ptr_reg = {ADDR_WIDTH{1'b0}};
reg [COUNT_WIDTH-1:0] count_reg = {COUNT_WIDTH{1'b0}};

wire pop = m_axis_tvalid && m_axis_tready;
wire push = s_axis_tvalid && s_axis_tready;
wire full = count_reg == DEPTH_VALUE;
wire empty = count_reg == {COUNT_WIDTH{1'b0}};
wire [DATA_WIDTH+1:0] rd_word = mem[rd_ptr_reg];

assign s_axis_tready = !full || pop;
assign m_axis_tvalid = !empty;
assign m_axis_tdata = rd_word[DATA_WIDTH-1:0];
assign m_axis_tlast = rd_word[DATA_WIDTH];
assign m_axis_tuser = rd_word[DATA_WIDTH+1];

always @(posedge clk) begin
    if (rst) begin
        wr_ptr_reg <= {ADDR_WIDTH{1'b0}};
        rd_ptr_reg <= {ADDR_WIDTH{1'b0}};
        count_reg <= {COUNT_WIDTH{1'b0}};
        overflow <= 1'b0;
    end else begin
        overflow <= s_axis_tvalid && full && !pop;

        if (push) begin
            mem[wr_ptr_reg] <= {s_axis_tuser, s_axis_tlast, s_axis_tdata};
            wr_ptr_reg <= wr_ptr_reg + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end

        if (pop) begin
            rd_ptr_reg <= rd_ptr_reg + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
        end

        case ({push, pop})
            2'b10: count_reg <= count_reg + {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
            2'b01: count_reg <= count_reg - {{(COUNT_WIDTH-1){1'b0}}, 1'b1};
            default: count_reg <= count_reg;
        endcase
    end
end

endmodule

`resetall
