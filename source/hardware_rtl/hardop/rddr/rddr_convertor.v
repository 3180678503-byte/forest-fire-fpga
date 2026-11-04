//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : rddr_convertor.v
// Author        : Wang Rui 
// Project       : NB2138
// Create Date   : 2021.10.26
// Description   : 
// -  
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================
module rddr_convertor(
        output reg            	rddr_arvalid  ,
        output reg  [  31 :0]   rddr_araddr   ,
		input                   rddr_arready  ,

		input                   img_arvalid   ,
        input       [  31 :0]   img_araddr    ,
		output                  img_arready   ,

		input                   img_rddr_start,
		input                   img_rdata_end ,

		input                   rddr_rvalid   ,
		input       [ 511 :0]   rddr_rdata    ,
		output                	rddr_rready   ,

		output                  img_rvalid    ,
		output      [  63 :0]   img_rdata     ,
		input                   img_rready    ,

		input                   clk           ,
		input                   rst           

);  
   
    wire                  img_arack ;
	wire                  img_rack  ;
	reg      [  9 :0]     wait_cnt  ;
	wire                  sft_en    ;         //shift enable
	reg      [  2 :0]     sft_cnt   ;
	reg      [  2 :0]     img_arcnt ;


    assign img_arack = img_arvalid && img_arready;
    assign img_rack = img_rvalid && img_rready;

    always @(posedge clk) begin
				if(rst)
						wait_cnt <= 0;
				else if(img_rddr_start)
						wait_cnt <= 0;
			  else if(img_arack && !img_rack)
						wait_cnt <= wait_cnt + 1'b1;
				else if(!img_arack && img_rack)
						wait_cnt <= wait_cnt - 1'b1;
		end
	
		assign sft_en = wait_cnt > 0;

		always @(posedge clk) begin
				if(rst) 
						img_arcnt <= 0;
				else if(img_rddr_start)
						img_arcnt <= 0;
				else if(img_arack)
						img_arcnt <= img_arcnt + 1'b1;
		end

		always @(posedge clk) begin
				if(rst)
						rddr_arvalid <= 1'b0;
				else if(img_arack && img_arcnt==0)
						rddr_arvalid <= 1'b1;	
				else if(rddr_arready)
                        rddr_arvalid <= 1'b0;							
	  end

		always @(posedge clk) begin
				if(rst)
						rddr_araddr <= 0;
				else if(img_arack)
						rddr_araddr <= {img_araddr[31:6],6'h0};
                    //    rddr_araddr <= img_araddr[31:6];
		end

		assign img_arready = !(rddr_arvalid && img_arcnt==0);

		always @(posedge clk) begin
				if(rst)
						sft_cnt <= 0;
				else if(img_rddr_start)
						sft_cnt <= 0;
				else if(img_rack)
						sft_cnt <= sft_cnt + 1'b1;
		end

		assign rddr_rready = !img_rvalid;

		reg  [ 511 :0]    sft_rdata;

		always @(posedge clk) begin
				if(rst)
						sft_rdata <= 0;
				else if(rddr_rvalid && rddr_rready)
						sft_rdata <= rddr_rdata;
				else if(sft_en && img_rack)
						sft_rdata <= sft_rdata >> 64;
		end

		reg  img_rreq;
		reg  img_rdata_end_reg;

		always @(posedge clk) begin
		    if(rst)
				    img_rdata_end_reg <= 1'b0;
				else 
				    img_rdata_end_reg <= img_rdata_end;
		end


		always @(posedge clk) begin
				if(rst)
						img_rreq <= 1'b0;
				else if(rddr_rvalid && rddr_rready)
						img_rreq <= 1'b1;
				else if((sft_cnt==7 && img_rack)||img_rdata_end_reg)
						img_rreq <= 1'b0;
		end
    
		assign img_rdata = sft_rdata[63:0];
		assign img_rvalid = img_rreq && (wait_cnt > 0);


endmodule



