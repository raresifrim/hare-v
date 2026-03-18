# vivado-non-project
A Project Template configuration for simulating/implemanting/running FPGA designs from CLI and remotely.

Contains scripts for simulating using either Vivado xsim, Verilator or Icarus Verilog.

Can use Vivado, Surfer, or GTKWave to view wave forms.

Has scripts in place for running synth, impl and bitstream generation of design with Vivado.

Can program FPGA bitstream using either Vivado or OpenFPGALoader.

## Simulation

The included scripts will automatically place all outputs of the simulation such as execution files and the dumped vcd into the `./build/sim` folder.

Simulation includes steps for compiling, elaborating and running the final simulation executables, plus displaying the generated output, and, if specified, opening the generated `.vcd` wave file.

Example for simulating module *tb* with *verilator* and opening a remote connection to view the wave through *surver*:

```bash
make sim simulator=verilator wave_viewer=surver top_module=tb
```
If only top_module is provided, then simulation will be done with Vivado by default, but no wave form viewer is opened:
```bash
make sim top_module=tb #runs simulation through Vivado but does not open any wave form
```
If you wish to also use the Vivado wave form viewer (or any other supported ones like Surfer or GTKWave) you need to make sure that your testbench file generates a "dump.vcd" file such as in the provided counter example:
```verilog
module tb();
    //DUT instantiation
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);
        //rest of your testbench
    end
endmodule
```
After this you can specify explictly that you also want to open the generated wave form with Vivado as:
```bash
make sim top_module=tb wave_viewer=vivado #runs simulation through Vivado and also opens the dump.vcd file
```

## Implementation

Currently, only supported implementation flow is through Vivado.

The included scripts include the synthesis, design optimization, placing and routing commands, and also generating the `bitsream.bit` final file.

The scripts will automatically place all outputs and logs of the synthesis and implementation steps into the `./build/impl` folder. The commands also include reports for timing, utilization and critical paths.

Example for implemeting module *top_fpga* for the CMOD A7 FPGA part *xc7a35tcpg236*:

```bash
make impl top_module=top_fpga fpga_part=xc7a35tcpg236-1
```

## Programming the FPGA

AMD/Xilinx FPGAs can be programmed either through Vivado by default, or through OpenFPGALoader if present on the system.

If OpenFPGALoader is needed, then FPGA board name must be provided togheter with the `with_openfpga=1` flag (can also be yes/true).

Scripts expect that `bitstream.bit` file is present in `./build/impl`.

Example of programming an FPGA with Vivado:

```bash
make program
```

Example of programming an CMOD A7_35T FPGA with OpenFPGALoader:

```bash
make program with_openfpga=yes openfpga_board=cmoda7_35t
```