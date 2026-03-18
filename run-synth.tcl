#!/usr/bin/env tclsh

if { $argc != 2 } {
	puts "The script requires two inputs for implementation of design: <top_module_name> <fpga_part>"
        puts "Please try again."
	exit
}

set outputDir ./build/synth
file mkdir $outputDir
cd $outputDir
file delete -force -- {*}[glob -nocomplain *]
puts "Current working directory: [pwd]"

exec vivado -mode batch -source ../../vivado-synth.tcl -tclargs {*}$::argv >@stdout