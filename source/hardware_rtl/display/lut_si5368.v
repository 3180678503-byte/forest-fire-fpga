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
module lut_si5368(
	input[9:0]             lut_index, // Look-up table index address
	output reg[31:0]       lut_data   // I2C device address register address register data
);

always@(*)
begin
	case(lut_index)
		//To be compatible with the 16bit register address, add 8'h00
		10'd0 	: 	lut_data	<= 	{8'hd0,24'h000014};
		10'd1 	: 	lut_data	<= 	{8'hd0,24'h0001E4};
		10'd2 	: 	lut_data	<= 	{8'hd0,24'h0002A2};
		10'd3 	: 	lut_data	<= 	{8'hd0,24'h000315};
		10'd4 	: 	lut_data	<= 	{8'hd0,24'h000492};
		10'd5 	: 	lut_data	<= 	{8'hd0,24'h0005FF};
		10'd6 	: 	lut_data	<= 	{8'hd0,24'h00063F};
		10'd7 	: 	lut_data	<= 	{8'hd0,24'h00073A};
		10'd8 	: 	lut_data	<= 	{8'hd0,24'h000800};
		10'd9 	: 	lut_data	<= 	{8'hd0,24'h0009C0};
		10'd10 	: 	lut_data	<= 	{8'hd0,24'h000a00};
		10'd11 	: 	lut_data	<= 	{8'hd0,24'h000b40};
		10'd12 	: 	lut_data	<= 	{8'hd0,24'h000c88};
		10'd13 	: 	lut_data	<= 	{8'hd0,24'h000d01};
		10'd14 	: 	lut_data	<= 	{8'hd0,24'h000e00};
		10'd15 	: 	lut_data	<= 	{8'hd0,24'h000f00};
		10'd16 	: 	lut_data	<= 	{8'hd0,24'h001000};
		10'd17 	: 	lut_data	<= 	{8'hd0,24'h001180};
		10'd18 	: 	lut_data	<= 	{8'hd0,24'h001200};
		10'd19 	: 	lut_data	<= 	{8'hd0,24'h00132C};
		10'd20 	: 	lut_data	<= 	{8'hd0,24'h00143E};
		10'd21 	: 	lut_data	<= 	{8'hd0,24'h0015FE};
		10'd22 	: 	lut_data	<= 	{8'hd0,24'h0016DF};
		10'd23 	: 	lut_data	<= 	{8'hd0,24'h00171F};
		10'd24 	: 	lut_data	<= 	{8'hd0,24'h00183F};
		10'd25 	: 	lut_data	<= 	{8'hd0,24'h001940};
		10'd26 	: 	lut_data	<= 	{8'hd0,24'h001a00};
		10'd27 	: 	lut_data	<= 	{8'hd0,24'h001b05};
		10'd28 	: 	lut_data	<= 	{8'hd0,24'h001c00};
		10'd29 	: 	lut_data	<= 	{8'hd0,24'h001d00};
		10'd30 	: 	lut_data	<= 	{8'hd0,24'h001e05};
		10'd31 	: 	lut_data	<= 	{8'hd0,24'h001f00};
		10'd32 	: 	lut_data	<= 	{8'hd0,24'h002000};
		10'd33 	: 	lut_data	<= 	{8'hd0,24'h002105};
		10'd34 	: 	lut_data	<= 	{8'hd0,24'h002200};
		10'd35 	: 	lut_data	<= 	{8'hd0,24'h002300};
		10'd36 	: 	lut_data	<= 	{8'hd0,24'h002405};
		10'd37 	: 	lut_data	<= 	{8'hd0,24'h002500};
		10'd38 	: 	lut_data	<= 	{8'hd0,24'h002600};
		10'd39 	: 	lut_data	<= 	{8'hd0,24'h002705};
		10'd40 	: 	lut_data	<= 	{8'hd0,24'h0028A0};
		10'd41 	: 	lut_data	<= 	{8'hd0,24'h002901};
		10'd42 	: 	lut_data	<= 	{8'hd0,24'h002a3B};
		10'd43 	: 	lut_data	<= 	{8'hd0,24'h002b00};
		10'd44 	: 	lut_data	<= 	{8'hd0,24'h002c00};
		10'd45 	: 	lut_data	<= 	{8'hd0,24'h002d4E};
		10'd46 	: 	lut_data	<= 	{8'hd0,24'h002e00};
		10'd47 	: 	lut_data	<= 	{8'hd0,24'h002f00};
		10'd48 	: 	lut_data	<= 	{8'hd0,24'h00304E};
		10'd49 	: 	lut_data	<= 	{8'hd0,24'h003100};
		10'd50 	: 	lut_data	<= 	{8'hd0,24'h003200};
		10'd51 	: 	lut_data	<= 	{8'hd0,24'h00334E};
		10'd52 	: 	lut_data	<= 	{8'hd0,24'h003400};
		10'd53 	: 	lut_data	<= 	{8'hd0,24'h003500};
		10'd54 	: 	lut_data	<= 	{8'hd0,24'h00364E};
		10'd55 	: 	lut_data	<= 	{8'hd0,24'h003700};
		10'd56 	: 	lut_data	<= 	{8'hd0,24'h003800};
		10'd57 	: 	lut_data	<= 	{8'hd0,24'h00831F};
		10'd58 	: 	lut_data	<= 	{8'hd0,24'h008402};
		10'd59 	: 	lut_data	<= 	{8'hd0,24'h008a0F};
		10'd60 	: 	lut_data	<= 	{8'hd0,24'h008bFF};
		10'd61 	: 	lut_data	<= 	{8'hd0,24'h008c00};
		10'd62 	: 	lut_data	<= 	{8'hd0,24'h008d00};
		10'd63 	: 	lut_data	<= 	{8'hd0,24'h008e00};
		10'd64 	: 	lut_data	<= 	{8'hd0,24'h008f00};
		10'd65 	: 	lut_data	<= 	{8'hd0,24'h009000};
		10'd66 	: 	lut_data	<= 	{8'hd0,24'h008840};
		default:lut_data <= {8'hff,16'hffff,8'hff};
	endcase
end

endmodule 
