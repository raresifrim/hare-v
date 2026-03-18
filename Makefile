simulator = vivado
wave_viewer = manual
fpga_part = xc7a35tcpg236-1
openfpga_board = cmoda7_35t
top_module = tb
with_openfpga = false

sim: $(wildcard src/design/*.v) $(wildcard src/design/*.sv) $(wildcard src/sim/*.v) $(wildcard src/sim/*.sv)
	./run-sim.tcl -s $(simulator) -w $(wave_viewer) -m $(top_module)

synth: $(wildcard src/design/*.v) $(wildcard src/design/*.sv) $(wildcard src/constr/*.xdc)
	./run-synth.tcl $(top_module) $(fpga_part)

impl: $(wildcard src/design/*.v) $(wildcard src/design/*.sv) $(wildcard src/constr/*.xdc)
	./run-impl.tcl $(top_module) $(fpga_part)

program: ./build/impl/bitstream.bit
ifneq ($(with_openfpga), false)
	./program-board.tcl openfpga $(openfpga_board)
else #vivado can automatically recognize the connected board
	./program-board.tcl
endif

clean:
	rm -rf build/sim
	rm -rf build/impl
	rm -rf .Xil
	rm -rf *.log
	rm -f vivado.jou
	rm -f vivado.log
	rm -f vivado_*.backup.log
	rm -f vivado_*.backup.jou