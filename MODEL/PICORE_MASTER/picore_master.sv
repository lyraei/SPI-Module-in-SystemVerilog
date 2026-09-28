module spi_master(i_clk, i_rst, 
                  i_data, i_send, 
                  o_data, o_busy, 
                  i_miso, o_mosi, o_sclk, o_ss);
parameter BITS = 28;
parameter SLAVES_NUMBER = 3;

input logic             i_clk, i_rst, i_send, i_miso;
input logic  [BITS-1:0] i_data;
output logic [BITS-1:0] o_data;
output logic            o_busy, o_mosi, o_sclk, o_ss;

logic s_sout_en, s_sout_wrt;
logic s_sin_en,  s_sin_wrt;
logic s_inter,   s_watchdog_we;

localparam STATES_NUM = 6;
localparam  [$clog2(STATES_NUM)-1:0] 
                    STATE_READY     = 0, 
                    STATE_LOAD      = 1,
                    STATE_HIGH      = 2,
                    STATE_LOW       = 3,
                    STATE_END       = 4,
                    STATE_SS        = 5;

logic       [$clog2(STATES_NUM)-1:0] s_state, s_state_next;

logic s_bit, s_bit_in;

shifter #(.N(BITS))
    shift (
        .i_clk_p(o_sclk), 
        .i_rst_n(i_rst), 
        .i_bit(s_bit_in),      
        .i_data(i_data),     
        .i_en(s_sout_en),       
        .i_wrt(s_sout_wrt),          
        .o_data(o_data),
        .o_bit(s_bit)
    );

watchdog #(.N($clog2(BITS)+1))
    watchdog (
        .i_clk_p(o_sclk),
        .i_rst_n(i_rst),
        .i_cycles(BITS),
        .i_we(s_watchdog_we),
        .o_inter(s_inter)
    );


always @(*)
begin
    {s_sout_en, s_sout_wrt}  = '0;
    {s_sin_en,  s_sin_wrt }  = '0;
    {s_watchdog_we}  = '0;
    {o_busy, o_sclk} = '0;
    {o_ss}   = '1;

    s_state_next = s_state;

    case (s_state)
        STATE_READY:
            begin
                if (i_send)
                begin
                    s_state_next    = STATE_SS;
                end 
            end
        STATE_SS:
            begin
                s_state_next    = STATE_LOAD;
                s_sout_en       = '1;
                s_sout_wrt      = '1;                
                s_watchdog_we   = '1;
                o_ss            = '0;
                o_busy          = '1;
            end
        STATE_LOAD:
            begin
                s_state_next    = STATE_LOW;
                o_sclk  = '1;
                s_sout_en       = '1;
                s_sout_wrt      = '1;                
                s_watchdog_we   = '1;
                o_ss            = '0;
                o_busy          = '1;
            end
        STATE_HIGH:
            begin
                s_state_next    = STATE_LOW;
                o_sclk  = '1;

                s_sout_en       = '1;
                o_ss            = '0;
                o_busy          = '1;
            end 
        STATE_LOW:
            begin
                s_state_next    = STATE_HIGH;
                o_sclk  = '0;
                s_sout_en       = '1;
                o_ss            = '0;
                o_busy          = '1;
                if (s_inter)
                    s_state_next    = STATE_END;   
            end 
        STATE_END:
            begin
                s_state_next    = STATE_READY;
                o_ss            = '1;
                o_busy          = '1;
            end

        default:
            begin
                s_state_next = STATE_READY;
            end
    endcase

end

always @(posedge i_clk, negedge i_rst)
begin
    if (!i_rst)
    begin
        s_state <= STATE_READY;

    end
    else
    begin
        s_state <= s_state_next;

    end
end

always @(negedge o_sclk, negedge i_rst)
if (!i_rst)
    o_mosi <= 0;
else
    o_mosi <= s_bit;

// Dodatkowy rejestr wejsciowy
// w celu opoznienia wejscia o jeden takt
always @(posedge o_sclk, negedge i_rst)
if (!i_rst)
    s_bit_in <= 0;
else
    s_bit_in <= i_miso;


endmodule
