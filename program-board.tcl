#!/usr/bin/env tclsh
set files [glob -nocomplain ./build/impl/bitstream.bit]
set len [llength $files]
if {$len > 0} {
    if { $argc == 2 && [lindex $argv 0] == "openfpga" } {
        exec openFPGALoader -b [lindex $argv 1] ./build/impl/bitstream.bit
    } elseif { $argc == 0 || ($argc == 1 && [lindex $argv 0] == "vivado") }  {
        exec vivado -mode batch -source vivado-fpga.tcl >@stdout
    } else {
        puts "Usage: ./program-board.tcl \[openfpga|vivado\] \[openfpga_board\]"
    }
} else {
    puts "ERROR: no bitstream.bit file found under directory ./build/impl"
}