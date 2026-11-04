//                                                                             //
//                                                                             //
//  Author:                                                                    //
//                                                                             //
//  WEB:                                                                       //
//                                                                             //
//*****************************************************************************/
// 
// (c) Copyright 2008 - 2019 xxx. All rights reserved.
// 
// This file contains confidential and proprietary information
// of xxx. and is protected under China and
// international copyright and other intellectual property laws.
// 
//*****************************************************************************/
//-----------------------------------------------------------------------------//
//  Revision History:
//  Revision            Date                By           Change Description
//-----------------------------------------------------------------------------//
//  1.0                 2019/07/09                       new created
//*****************************************************************************/

module i2c_config(
	input              rst,
	input              clk,
	input[15:0]        clk_div_cnt,
	input              i2c_addr_2byte,
	output reg[9:0]    reg_file_index,
	input[7:0]         reg_device_addr,
	input[15:0]        reg_file_addr,
	input[7:0]         reg_file_data,
	output reg         config_error,
	output             config_done,
	inout              i2c_scl,
	inout              i2c_sda
);
wire scl_pad_i;
wire scl_pad_o;
wire scl_padoen_o;

wire sda_pad_i;
wire sda_pad_o;
wire sda_padoen_o;

reg i2c_read_req;
wire i2c_read_req_ack;
reg i2c_write_req;
wire i2c_write_req_ack;
wire[7:0] i2c_slave_dev_addr;
wire[15:0] i2c_slave_reg_addr;
wire[7:0] i2c_write_data;
wire[7:0] i2c_read_data;

wire i2c_error;
reg[2:0] config_state;

localparam CONFIG_IDLE            =  3'b000;
localparam CONFIG_WR_CHECK        =  3'b001;
localparam CONFIG_WR              =  3'b010;
localparam CONFIG_WR_DONE         =  3'b011;

always@(posedge clk or posedge rst)
begin
	if(rst)
	begin
		config_state <= CONFIG_IDLE;
		config_error <= 1'b0;
		reg_file_index <= 8'd0;
	end
	else 
		case(config_state)
			CONFIG_IDLE:
			begin
				config_state <= CONFIG_WR_CHECK;
				config_error <= 1'b0;
				reg_file_index <= 8'd0;
			end
			CONFIG_WR_CHECK:
			begin
				if(i2c_slave_dev_addr != 8'hff)
				begin
					i2c_write_req <= 1'b1;
					config_state <= CONFIG_WR;
				end
				else
				begin
					config_state <= CONFIG_WR_DONE;
				end
			end
			CONFIG_WR:
			begin
				if(i2c_write_req_ack)
				begin
					config_error <= i2c_error ? 1'b1 : config_error; 
					reg_file_index <= reg_file_index + 8'd1;
					i2c_write_req <= 1'b0;
					config_state <= CONFIG_WR_CHECK;
				end
			end
			CONFIG_WR_DONE:
			begin
				config_state <= CONFIG_WR_DONE;
			end
			default:
				config_state <= CONFIG_IDLE;
		endcase
end

i2c_master_top i2c_master_top_m0
(
	.rst(rst),
	.clk(clk),
	.clk_div_cnt(clk_div_cnt),
	
	// I2C signals
	// i2c clock line
	.scl_pad_i(scl_pad_i),       // SCL-line input
	.scl_pad_o(scl_pad_o),       // SCL-line output (always 1'b0)
	.scl_padoen_o(scl_padoen_o),    // SCL-line output enable (active low)

	// i2c data line
	.sda_pad_i(sda_pad_i),       // SDA-line input
	.sda_pad_o(sda_pad_o),       // SDA-line output (always 1'b0)
	.sda_padoen_o(sda_padoen_o),    // SDA-line output enable (active low)
	
	.i2c_read_req(i2c_read_req),
	.i2c_addr_2byte(i2c_addr_2byte),
	.i2c_read_req_ack(i2c_read_req_ack),
	.i2c_write_req(i2c_write_req),
	.i2c_write_req_ack(i2c_write_req_ack),
	.i2c_slave_dev_addr(i2c_slave_dev_addr),
	.i2c_slave_reg_addr(i2c_slave_reg_addr),
	.i2c_write_data(i2c_write_data),
	.i2c_read_data(i2c_read_data),
	.error(i2c_error)
);
//assign parts
assign config_done = (config_state == CONFIG_WR_DONE);
assign i2c_slave_dev_addr  = reg_device_addr;
assign i2c_slave_reg_addr = reg_file_addr;
assign i2c_write_data  = reg_file_data;
/*
assign sda_pad_i = i2c_sda;
assign i2c_sda = ~sda_padoen_o ? sda_pad_o : 1'bz;
assign scl_pad_i = i2c_scl;
assign i2c_scl = ~scl_padoen_o ? scl_pad_o : 1'bz;
*/

    IOBUF #(
          .DRIVE(12), // Specify the output drive strength
          .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE"
          .IOSTANDARD("DEFAULT"), // Specify the I/O standard
          .SLEW("SLOW") // Specify the output slew rate
       ) IOBUF_inst0 (
          .O(scl_pad_i),     // Buffer output
          .IO(i2c_scl),   // Buffer inout port (connect directly to top-level port)
          .I(scl_pad_o),     // Buffer input
          .T(scl_padoen_o)      // 3-state enable input, high=input, low=output
       );
       
     IOBUF #(
             .DRIVE(12), // Specify the output drive strength
             .IBUF_LOW_PWR("TRUE"),  // Low Power - "TRUE", High Performance = "FALSE"
             .IOSTANDARD("DEFAULT"), // Specify the I/O standard
             .SLEW("SLOW") // Specify the output slew rate
          ) IOBUF_inst1 (
             .O(sda_pad_i),     // Buffer output
             .IO(i2c_sda),   // Buffer inout port (connect directly to top-level port)
             .I(sda_pad_o),     // Buffer input
             .T(sda_padoen_o)      // 3-state enable input, high=input, low=output
          );  

endmodule
