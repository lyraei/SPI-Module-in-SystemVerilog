SHELL:= /bin/bash
SYNTH = yosys

rtl: 
	${SYNTH} -s spi_master.ys  |& tee spi_master.yosys.log
	${SYNTH} -s spi_slave_1.ys |& tee spi_slave_1.yosys.log
	${SYNTH} -s spi_slave_2.ys |& tee spi_slave_2.yosys.log
	${SYNTH} -s spi_slave_3.ys |& tee spi_slave_3.yosys.log


RTL_FILES   = ../RTL/*.sv
TB_FILES    = ../TEST/testbench.sv

sim: clear
	iverilog -g2005-sv ${RTL_FILES} ${TB_FILES} -o spi_test.iveri.run |& tee spi_test.iveri.log
	./spi_test.iveri.run
	
clear:
	if [ -f spi_test.iveri.run ] ; then rm spi_test.iveri.run ; fi

wave:
	gtkwave waves.vcd &
    