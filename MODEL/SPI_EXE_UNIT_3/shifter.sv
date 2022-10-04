 module shifter (i_clk_p, i_rst_n, 
                i_bit,      // wejscie szeregowe bitow
                i_data,     // wejscie rownolegle bitow
                i_en,       // zezwolenie na przesuwanie/wpis
                i_wrt,      // wpis rownolegly/prezesuwanie
                o_data,     // wyjscie rownolegle
                o_bit);     // wyjscie szeregowe
parameter N = 4;
input logic [N-1:0] i_data;
input logic         i_clk_p, i_rst_n;
input logic         i_bit, i_en, i_wrt;
output logic        o_bit;
output logic [N-1:0] o_data;

logic [N-1:0] s_shifter, s_shifter_next;

// blok kombinacyjny
always @(*)
begin
    
    o_data  = s_shifter;
    s_shifter_next  = s_shifter;
    o_bit = s_shifter[N-1];

    if (i_en)
    begin
        if (i_wrt)
            s_shifter_next = i_data;
        else
        begin
            s_shifter_next = {s_shifter, i_bit};
        end
    end
end

// blok synchronizowany
always @(posedge i_clk_p, negedge i_rst_n)
begin
    if (!i_rst_n)
        s_shifter   <= '0;
    else
    begin
        s_shifter   <= s_shifter_next;
    end
end 


endmodule