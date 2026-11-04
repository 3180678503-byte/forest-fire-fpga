//==============================================================================
// Orgnization   : Shanghai Fudan Microelectronics Co., Ltd. Confidential
// File Name     : custom_hp_itcn.v
// Author        : 
// Project       : NB2337
// Create Date   : 2023.11.15
// Description   :  awvalid = wvalid    awready = wready
//------------------------------------------------------------------------------
// Modification History :
// Rev     Date         Who          Description
//==============================================================================

module custom_hp_itcn #(parameter DW=64, AW=32)(
    mna_hp_std_itf.master     m_hp_itf        ,

    mna_hp_std_itf.slave      s0_hp_itf       ,
    mna_hp_std_itf.slave      s1_hp_itf       ,
    mna_hp_std_itf.slave      s2_hp_itf       ,
    mna_hp_std_itf.slave      s3_hp_itf       ,        

    input                     hp_clk          ,
    input                     hp_rst
);

    reg   [   3 : 0]   ack_awid          ;
    reg   [   3 : 0]   ack_wid           ;
    wire  [   2 : 0]   ack_arid          ;
    wire  [   2 : 0]   idfifo_din        ;
    wire  [   2 : 0]   idfifo_dout       ;
    wire               idfifo_wr         ;
    wire               idfifo_rd         ;
    wire               idfifo_full       ;
	wire               idfifo_pfull      ;
    wire               idfifo_empty      ;
    wire               arready           ;

    //aw  w
    always@(*)begin
        if(s0_hp_itf.awvalid)
            ack_awid <= 4'h0;
        else if(s1_hp_itf.awvalid)
            ack_awid <= 4'h1;
        else if(s2_hp_itf.awvalid)
            ack_awid <= 4'h2;
        else if(s3_hp_itf.awvalid)
            ack_awid <= 4'h3;
        else
            ack_awid <= 4'hF;
    end
    assign m_hp_itf.awvalid = (ack_awid!=4'hF);
    assign s0_hp_itf.awready = (ack_awid==4'd0) && m_hp_itf.awready ;
    assign s1_hp_itf.awready = (ack_awid==4'd1) && m_hp_itf.awready ;
    assign s2_hp_itf.awready = (ack_awid==4'd2) && m_hp_itf.awready ;
    assign s3_hp_itf.awready = (ack_awid==4'd3) && m_hp_itf.awready ;

    always@(*) begin
        case(ack_awid)
            4'd0   : m_hp_itf.awaddr <= s0_hp_itf.awaddr ;
            4'd1   : m_hp_itf.awaddr <= s1_hp_itf.awaddr ;
            4'd2   : m_hp_itf.awaddr <= s2_hp_itf.awaddr ;
            4'd3   : m_hp_itf.awaddr <= s3_hp_itf.awaddr ;
            default: m_hp_itf.awaddr <= 0;
        endcase
    end

    always@(*)begin
        if(s0_hp_itf.wvalid)
            ack_wid <= 4'h0;
        else if(s1_hp_itf.wvalid)
            ack_wid <= 4'h1;
        else if(s2_hp_itf.wvalid)
            ack_wid <= 4'h2;
        else if(s3_hp_itf.wvalid)
            ack_wid <= 4'h3;
        else
            ack_wid <= 4'hF;
    end

    assign m_hp_itf.wvalid = (ack_wid!=4'hF);
    assign s0_hp_itf.wready = (ack_wid==4'd0) && m_hp_itf.wready ;
    assign s1_hp_itf.wready = (ack_wid==4'd1) && m_hp_itf.wready ;
    assign s2_hp_itf.wready = (ack_wid==4'd2) && m_hp_itf.wready ;
    assign s3_hp_itf.wready = (ack_wid==4'd3) && m_hp_itf.wready ;

    always@(*) begin
        case(ack_wid)
            4'd0   : m_hp_itf.wdata <= s0_hp_itf.wdata ;
            4'd1   : m_hp_itf.wdata <= s1_hp_itf.wdata ;
            4'd2   : m_hp_itf.wdata <= s2_hp_itf.wdata ;
            4'd3   : m_hp_itf.wdata <= s3_hp_itf.wdata ;
            default: m_hp_itf.wdata <= 0;
        endcase
    end

    //ar r
    assign ack_arid   = s0_hp_itf.arvalid ? 3'd0 :
                       (s1_hp_itf.arvalid ? 3'd1 :
                       (s2_hp_itf.arvalid ? 3'd2 :
                       (s3_hp_itf.arvalid ? 3'd3 : 3'd7)));

    assign m_hp_itf.arvalid  = (~idfifo_pfull) && (s0_hp_itf.arvalid|s1_hp_itf.arvalid|s2_hp_itf.arvalid|s3_hp_itf.arvalid); 
    assign arready        = (~idfifo_pfull) && m_hp_itf.arready;

    assign s0_hp_itf.arready = (ack_arid==3'd0) && arready ;
    assign s1_hp_itf.arready = (ack_arid==3'd1) && arready ;
    assign s2_hp_itf.arready = (ack_arid==3'd2) && arready ;
    assign s3_hp_itf.arready = (ack_arid==3'd3) && arready ;

    always@(*) begin
        case(ack_arid)
            3'd0   : m_hp_itf.araddr <= s0_hp_itf.araddr;
            3'd1   : m_hp_itf.araddr <= s1_hp_itf.araddr;
            3'd2   : m_hp_itf.araddr <= s2_hp_itf.araddr;
            3'd3   : m_hp_itf.araddr <= s3_hp_itf.araddr;
            default: m_hp_itf.araddr <= 0;
        endcase
    end

    assign s0_hp_itf.rdata  = m_hp_itf.rdata      ;
    assign s1_hp_itf.rdata  = m_hp_itf.rdata      ;
    assign s2_hp_itf.rdata  = m_hp_itf.rdata      ;
    assign s3_hp_itf.rdata  = m_hp_itf.rdata      ;
    
    assign s0_hp_itf.rvalid = ((idfifo_dout[2:0]==3'd0) & ~idfifo_empty)  ? m_hp_itf.rvalid :  1'b0 ;
    assign s1_hp_itf.rvalid = ((idfifo_dout[2:0]==3'd1) & ~idfifo_empty)  ? m_hp_itf.rvalid :  1'b0 ;
    assign s2_hp_itf.rvalid = ((idfifo_dout[2:0]==3'd2) & ~idfifo_empty)  ? m_hp_itf.rvalid :  1'b0 ;
    assign s3_hp_itf.rvalid = ((idfifo_dout[2:0]==3'd3) & ~idfifo_empty)  ? m_hp_itf.rvalid :  1'b0 ; 

    always@(*) begin
        case(idfifo_dout[2:0])
            3'd0   : m_hp_itf.rready <= s0_hp_itf.rready & ~idfifo_empty;
            3'd1   : m_hp_itf.rready <= s1_hp_itf.rready & ~idfifo_empty;
            3'd2   : m_hp_itf.rready <= s2_hp_itf.rready & ~idfifo_empty;
            3'd3   : m_hp_itf.rready <= s3_hp_itf.rready & ~idfifo_empty;       
            default: m_hp_itf.rready <= 0;
        endcase
    end

    assign idfifo_din = ack_arid;
    assign idfifo_wr  = m_hp_itf.arvalid  & m_hp_itf.arready  ;
    assign idfifo_rd  = m_hp_itf.rvalid & m_hp_itf.rready;

    mna_idfifo mna_idfifo_u0(
        .clk       (hp_clk          ),
        .srst      (hp_rst          ),
        .din       (idfifo_din      ),
        .wr_en     (idfifo_wr       ),
        .rd_en     (idfifo_rd       ),
        .dout      (idfifo_dout     ),
        .prog_full (idfifo_pfull    ),
        .full      (idfifo_full     ),
        .empty     (idfifo_empty    )
    );

endmodule
