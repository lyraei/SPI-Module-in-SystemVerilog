SHELL:= /bin/bash
SYNTH = yosys

rtl: 
	${SYNTH} -s picore_master.ys  |& tee picore_master.yosys.log
	${SYNTH} -s picore_slave.ys |& tee picore_slave.yosys.log


RTL_FILES   = ../RTL/*.sv
TB_FILES    = ../TEST/testbench.sv

sim: clear
	iverilog -g2005-sv ${RTL_FILES} ${TB_FILES} -o picore_test.iveri.run |& tee picore_test.iveri.log
	./picore_test.iveri.run
	
clear:
	if [ -f picore_test.iveri.run ] ; then rm picore_test.iveri.run ; fi

wave:
	gtkwave waves.vcd &
    