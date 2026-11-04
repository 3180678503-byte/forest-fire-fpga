`timescale 1ns / 1ps
`default_nettype none

module sync_reset #
(
    parameter N = 4
)
(
    input  wire clk,
    input  wire rst,
    output wire out
);

(* ASYNC_REG = "TRUE" *)
reg [N-1:0] sync_reg = {N{1'b1}};

always @(posedge clk) begin
    sync_reg <= {sync_reg[N-2:0], rst};
end

assign out = |sync_reg;

endmodule

`resetall
