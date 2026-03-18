#!/usr/bin/env tclsh

if { $argc != 2 } {
	puts "The script requires two inputs for implementation of design: <top_module_name> <fpga_part>"
        puts "Please try again."
	exit
}

set outputDir ./build/impl
file mkdir $outputDir
cd $outputDir
file delete -force -- {*}[glob -nocomplain *]
puts "Current working directory: [pwd]"

exec vivado -mode batch -source ../../vivado-bitstream.tcl -tclargs {*}$::argv >@stdout