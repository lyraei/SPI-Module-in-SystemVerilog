// Modul wystawiajacy jedynke na wyjsciu o_inter
// gdy licznik wewnetrzny s_count osiagnie wartosc 0
// Gdy to nastapi to 
module watchdog(i_clk_p, i_rst_n, 
                i_cycles, i_we, o_inter);
parameter N = 4;
input logic [N-1:0] i_cycles;           // Wejscie okreslające wartosc poczatkowa liczenia w dol
input logic         i_clk_p, i_rst_n;
input logic         i_we;               // Zezwolenie na wpis wartosci gornej
output logic        o_inter;

logic [N-1:0] s_count;      // rejestr licznika
logic [N-1:0] s_count_next;

logic [N-1:0] s_cycles;     // Rejestr liczby cykli
logic [N-1:0] s_cycles_next;


// blok synchronizowany
always @(posedge i_clk_p, negedge i_rst_n)
begin
    if (!i_rst_n)
    begin
        s_count  <= '0;
        s_cycles <= '0;
    end
    else
    begin
        s_count  <= s_count_next;
        s_cycles <= s_cycles_next;
    end
end 

// blok kombinacyjny
always @(*)
begin
    // Ustalenie wartosci domyslnych
    
    o_inter       = '0;
    s_cycles_next = s_cycles;
    s_count_next  = s_count;
    
    // Jesli i_we == 1'b1 to 
    // wpisywany jest nowy zakres do zliczania
    if (i_we)
    begin
        s_cycles_next = i_cycles;
        s_count_next  = i_cycles;
    end
    else
    begin
        // Sprawdzenie czy licznik doszedl do 0
        if (s_count > 0)
            s_count_next = s_count - 1;
        else
        begin
            // Zgloszenie o_inter i ustawienie
            // licznika ponownie na wartosc poczatkowa zliczania
            o_inter = 1'b1;
            s_count_next = s_cycles;
        end
    end
    // Jesli wartosc w rejestrze cykli jest 0 to nie zglaszaj o_inter - watczdog jest wylaczony
    if (s_cycles == '0)
        o_inter = 1'b0;
end
endmodule