`define LICZBA_LOSOWAN 2000
`define TIME_STEP 1

module testbench;
parameter M = 8;
parameter N = 4;

//sygnały wejściowe
logic [M-1:0] s_argA = '0;
logic [M-1:0] s_argB = '0;
logic [N-1:0] s_oper;

//sygnały wyjściowe
logic [M-1:0] s_result_model, s_result_synth;
logic [M-1:0] s_flags_model, s_flags_synth;

//liczniki informujace o weryfikacji
integer liczba_bledow_wynikow     = 0;
integer liczba_bledow_flag        = 0;
integer liczba_poprawnych_wynikow = 0;
integer liczba_poprawnych_flag    = 0;

event test_results;

exe_unit #(.M(M), .N(N))
    exe_unit_model (.i_argA(s_argA),
                    .i_argB(s_argB),
                    .i_oper(s_oper),
                    .o_result(s_result_model),

                    .o_OF(s_flags_model[0]),
                    .o_SF(s_flags_model[1]),
                    .o_BF(s_flags_model[2]),
                    .o_VF(s_flags_model[3])
                    );

exe_unit_rtl #()
    exe_unit_synth (.i_argA(s_argA),
                    .i_argB(s_argB),
                    .i_oper(s_oper),
                    .o_result(s_result_synth),

                    .o_OF(s_flags_synth[0]),
                    .o_SF(s_flags_synth[1]),
                    .o_BF(s_flags_synth[2]),
                    .o_VF(s_flags_synth[3])
                    );


always @(test_results)
begin
    if(s_result_model == s_result_synth & s_oper < 11) //sprawdzamy tylko przypadki gdy s_oper jest mniejszt od 10 ponieważ wyniki dla większych wartości nie są ważne
    begin
        $display("send_data = 28'b%8b0%8b0%4b000000;\nexpected_data = 28'b%8b%1b%1b%1b%1b;\n@(next_data);\n",s_argA, s_argB, s_oper, s_result_model, s_flags_synth[0], s_flags_synth[1], s_flags_synth[2], s_flags_synth[3]);
        liczba_bledow_wynikow = liczba_bledow_wynikow + 1;
    end
    else liczba_poprawnych_wynikow = liczba_poprawnych_wynikow + 1;
end

integer seed, count;

initial begin
    $dumpfile("signals.vcd");
    $dumpvars(0, testbench);

    {s_oper, s_argA, s_argB, count} = '0;
    seed = 1;

    while (count < `LICZBA_LOSOWAN)
    begin: LOT_LOOP

        # `TIME_STEP;

        count = count + 1;
        s_oper <= s_oper + 1;
        s_argA <= $random(seed);
        s_argB <= $random(seed);

        -> test_results;

    end: LOT_LOOP

    # `TIME_STEP;
    $display("\n------------------------------------");
    $display("Koniec generacji sygnalow");
    $display("liczba blednych wynikow   %c[1;32m  %0d %c[0m ", 27, liczba_bledow_wynikow, 27);
    $display("liczba blednych flag      %c[1;32m  %0d %c[0m ", 27, liczba_bledow_flag, 27);
    $display("liczba poprawnych wynikow %c[1:32m  %0d %c[0m ", 27, liczba_poprawnych_wynikow, 27);
    $display("liczba poprawnych flag    %c[1:32m  %0d %c[0m ", 27, liczba_poprawnych_flag, 27);
    $display("--------------------------------------\n");

    # `TIME_STEP;
    $finish;

end
endmodule