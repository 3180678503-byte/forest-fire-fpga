module img_data_crossbar #(parameter DW = 32) (
    input      [ DW-1 : 0]  s0_data    ,
    input                   s0_valid   ,
    output                  s0_ready   ,
    
    input      [ DW-1 : 0]  s1_data    ,
    input                   s1_valid   ,
    output                  s1_ready   ,

    input      [ DW-1 : 0]  s2_data    ,
    input                   s2_valid   ,
    output                  s2_ready   ,

    input      [ DW-1 : 0]  s3_data    ,
    input                   s3_valid   ,
    output                  s3_ready   ,

    output reg [ DW-1 : 0]  m_data     ,
    output reg              m_valid    ,
    input                   m_ready         
);

reg [ 1 : 0 ] awmux_id ;

always@ (*) begin
    if(s0_valid)
        awmux_id <= 2'd0;
    else if(s1_valid)
        awmux_id <= 2'd1;
    else if(s2_valid)
        awmux_id <= 2'd2;
    else if(s3_valid)
        awmux_id <= 2'd3;
    else 
        awmux_id <= 2'd0; 
end

assign s0_ready = (awmux_id==2'd0) && m_ready;
assign s1_ready = (awmux_id==2'd1) && m_ready;
assign s2_ready = (awmux_id==2'd2) && m_ready;
assign s3_ready = (awmux_id==2'd3) && m_ready;

always@ (*) begin
    if(awmux_id == 2'd0)
        m_data <= s0_data;
    else if(awmux_id == 2'd1)
        m_data <= s1_data;
    else if(awmux_id == 2'd2)
        m_data <= s2_data;
    else if(awmux_id == 2'd3)
        m_data <= s3_data;
    else 
        m_data <= s0_data; 
end

always@ (*) begin
    if(awmux_id == 2'd0)
        m_valid <= s0_valid;
    else if(awmux_id == 2'd1)
        m_valid <= s1_valid;
    else if(awmux_id == 2'd2)
        m_valid <= s2_valid;
    else if(awmux_id == 2'd3)
        m_valid <= s3_valid;
    else 
        m_valid <= s0_valid; 
end

endmodule
