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

module lut_sil9134(
	input[9:0]             lut_index, // Look-up table index address
	output reg[31:0]       lut_data   // I2C device address register address register data
);

always@(*)
begin
	case(lut_index)
		//To be compatible with the 16bit register address, add 8'h00
		8'd0 	: 	lut_data	<= 	{8'he2,24'h000010}; 
		8'd1 	: 	lut_data	<= 	{8'h72,24'h000835};    	
		8'd2 	: 	lut_data	<= 	{8'h7a,24'h002f00};
		default:lut_data <= {8'hff,16'hffff,8'hff};
	endcase
end


endmodule 