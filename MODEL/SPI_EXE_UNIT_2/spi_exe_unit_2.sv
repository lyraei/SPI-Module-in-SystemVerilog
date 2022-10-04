module spi_exe_unit_2 (i_rst, i_sclk, i_mosi, o_miso, i_cs);
parameter BITS = 28;
localparam M = 8;
localparam N = 4;
input logic i_rst, i_sclk, i_mosi, i_cs;
output logic o_miso;

logic [M-1:0] s_argA, s_argB, s_oper, s_result;
logic [3:0] s_flags;
logic [M-1:0] s_argA_next, s_argB_next, s_oper_next, s_result_next;
logic [3:0] s_flags_next;
logic [M-1:0] s_data_next;
logic [3:0] s_cycles;
logic s_we, s_inter;
logic argA_enable, argB_enable, oper_enable, result_enable;

exe_unit_rtl_2 exe2(
                    .i_argA(s_argA),
                    .i_argB(s_argB),
                    .i_oper(s_oper[7:4]),
                    .o_result(s_result_next),
                    .o_VF(s_flags_next[0]),
                    .o_BF(s_flags_next[1]),
                    .o_SF(s_flags_next[2]),
                    .o_OF(s_flags_next[3])
                    );

logic s_en_in, s_wrt_in;
shifter #(.N(M)) shift_in (
                            .i_clk_p(i_sclk),
                            .i_rst_n(i_rst),
                            .i_bit(i_mosi),
                            .i_en(s_en_in),
                            .i_wrt(s_wrt_in),
                            .o_data(s_data_next)
                             );

logic s_en_out, s_wrt_out;
shifter #(.N(BITS)) shift_out (   
                               .i_clk_p(i_sclk),
                               .i_rst_n(i_rst),
                               .i_data({s_result, s_flags, {16{1'b0}}}),
                               .i_en(s_en_out),
                               .i_wrt(s_wrt_out),
                               .o_bit(o_miso)
                            );

watchdog #(.N(4)) counter(
                            .i_clk_p(i_sclk),
                            .i_rst_n(i_rst),
                            .i_cycles(s_cycles),
                            .i_we(s_we),
                            .o_inter(s_inter)
                            );

localparam STATES_NUM = 5;
localparam [$clog2(STATES_NUM)-1:0] READY = 0, 
                                    LOAD_A = 1, 
                                    LOAD_B = 2, 
                                    LOAD_OPER = 3, 
                                    STORE_RESULT = 4;

logic [$clog2(STATES_NUM)-1:0] s_state, s_state_next;

always @(*)
begin
    s_state_next = s_state;
    result_enable = '0;
    {s_en_out, s_en_in} = '1;
    {s_wrt_in, s_wrt_out} = 2'b00;
    s_cycles = 0;
    s_we = '0;
    {argA_enable, argB_enable, oper_enable} = '0;
    s_oper_next[3:0] = '0;

    case(s_state)

    READY:
    begin
        {s_en_out, s_en_in} = '0;

        if(!i_cs)
        begin
            s_state_next = LOAD_A;
            {s_en_out, s_en_in} = '1;
            s_cycles = 8;
            s_we = '1;
        end
    end

    LOAD_A:
    begin
        if(s_inter)
        begin
            s_state_next = LOAD_B;
            {s_en_out, s_en_in} = '1;
            argA_enable = '1;
            s_argA_next = s_data_next;
        end
    end

    LOAD_B:
    begin
        if(s_inter)
        begin
            s_state_next = LOAD_OPER;
            {s_en_out, s_en_in} = '1;    
            argB_enable = '1;
            s_argB_next = s_data_next;
        end
    end

    LOAD_OPER:
    begin
        if(s_inter)
        begin
            s_state_next = STORE_RESULT;
            {s_en_out, s_en_in} = '1;
            oper_enable = '1;
            s_oper_next = s_data_next;
            s_oper_next[3:0] = '0;
        end
    end

    STORE_RESULT:
    begin
        s_state_next = READY;
        s_wrt_out = '1;
        s_result = s_result_next;
        s_flags = s_flags_next;
    end

    default: s_state_next = READY;

    endcase
end

always @(posedge i_sclk, negedge i_rst)
begin : FSM
 if (!i_rst)
     s_state <= READY;
 else
     s_state <= s_state_next;
end

always @(posedge i_sclk, negedge i_rst)
begin : regA
 if (!i_rst)
     s_argA <= '0;
 else
 if(argA_enable)
     s_argA <= s_argA_next;
end

always @(posedge i_sclk, negedge i_rst)
begin : regB
 if (!i_rst)
     s_argB <= '0;
 else
 if(argB_enable)
     s_argB <= s_argB_next;
end

always @(posedge i_sclk, negedge i_rst)
begin : regOper
 if (!i_rst)
     s_oper <= '0;
 else
  if(oper_enable)
     s_oper <= s_oper_next;
end

endmodule