#!/usr/bin/env tclsh

proc lshift listVar {
        upvar 1 $listVar L
        set r [lindex $L 0]
        set L [lreplace $L [set L 0] 0]
        return $r
}

proc arg_parser { args } {

        #-------------------------------------------------------
        # Process command line arguments
        #-------------------------------------------------------
        set tb_top ""
        set simulator "xsim"
        set waverviewer "xsim"
        set help 0
        set error 0

        if {[llength $args] == 0} { incr help };
        while {[llength $args]} {
                set flag [lshift args]
                switch -exact -- $flag {
                        -m -
                        -module {
                                set tb_top [lshift args]
                        }
                        -s -
                        -simulator {
                                set simulator [lshift args]
                                if { $simulator ne "vivado" && $simulator ne "verilator" && $simulator ne "iverilog"} {
                                        puts " ERROR - option $simulator is not a valid option."
                                        incr help
                                        incr error
                                }
                        }
                        -w -
                        -waveviewer {
                                set waverviewer [lshift args]
                                if { $waverviewer ne "vivado" && $waverviewer ne "surfer" && $waverviewer ne "surver" && $waverviewer ne "gtkwave" && $waverviewer ne "manual"} {
                                        puts " ERROR - option $waveviewer is not a valid option."
                                        incr help
                                        incr error
                                } 
                        }
                        -h -
                        -help {
                                incr help
                        }
                        default {
                                puts " ERROR - option '$flag' is not a valid option."
                                incr error
                        }
                }
        }

        if {$tb_top eq ""} {
                puts "ERROR - missing required parameter module."
                incr error
                incr help
        }

        if {$help} {
                set callerflag [lindex [info level [expr [info level] -1]] 0]
                # <-- HELP
                puts [format {
                Usage: vivado -mode batch -source sim.tcl -tclargs
                [-module|-m module name set as top for simulation (required)]
                [-simulator|-s optional simulator used: xsim|verilator (default: xsim)]
                [-waveviewer|-w optional wave viewer used: xsim|surfer(local)|surver(remote)|gtkwave|manual (default: xsim)]
                [-help|-h]
                } $callerflag $callerflag ]
                # HELP -->
                return -code error {}
        }

        # Check validity of arguments. Increment $error to generate an error

        if {$error} {
                return -code error {Oops, something is not correct}
        }

        set r "$tb_top $simulator $waverviewer" 
        return $r
}

lassign [arg_parser {*}$::argv] tb_top simulator waverviewer
puts "###############################"
puts "Top testbench module: $tb_top"
puts "Simulator: $simulator"
puts "Waveviewer: $waverviewer"
puts "###############################"
puts "\n###Creating sim_build dir###"
set outputDir ./build/sim
file mkdir $outputDir
cd $outputDir
set _cleanup [glob -nocomplain *]
if {[llength $_cleanup]} { file delete -force -- {*}$_cleanup }
unset _cleanup
puts "Current working directory: [pwd]"

if {[string match "vivado" $simulator]} {
        puts "\n###Compiling design and simulation sources###"
        set files [glob -nocomplain ../../src/design/*.sv]
        set len [llength $files]
        if {$len > 0} {
                exec sh -c "xvlog --sv  [ glob -nocomplain ../../src/design/*.sv ]" >@stdout
        }
        set files [glob -nocomplain ../../src/design/includes/*.svh]
        set len [llength $files]
        if {$len > 0} {
                exec sh -c "xvlog --sv  [ glob -nocomplain ../../src/design/includes/*.svh ]" >@stdout
        }
        set files [glob -nocomplain ../../src/design/*.v]
        set len [llength $files]
        if {$len > 0} {
                exec sh -c "xvlog [ glob -nocomplain ../../src/design/*.v ]" >@stdout
        }
        set files [glob -nocomplain ../../src/sim/*.sv]
        set len [llength $files]
        if {$len > 0} {
                exec sh -c "xvlog --sv [ glob -nocomplain ../../src/sim/*.sv ]" >@stdout
        }
        set files [glob -nocomplain ../../src/sim/*.v]
        set len [llength $files]
        if {$len > 0} {
                exec sh -c "xvlog [ glob -nocomplain ../../src/sim/*.v ]" >@stdout
        }

        puts "\n###Elaborating provided top testbench module $tb_top###"
        exec xelab -debug all -top $tb_top -snapshot tb_snapshot -timescale 1ns/1ps -override_timeunit -override_timeprecision >@stdout

        puts "\n###Starting simulation###"

        if {[string match "vivado" $waverviewer]} {
                puts "###Opening wave viewer###" 
                exec xsim -runall tb_snapshot -gui >@stdout
                return -code ok {}
        } else {
                exec xsim -runall tb_snapshot >@stdout
        }
} elseif {[string match "verilator" $simulator]} { 
        puts "\n###Compiling design and simulation sources using Verilator###"
        set verilator_flags "--binary --cc --build -j 0 -x-assign fast --Wno-fatal -Wno-HIERPARAM --trace --assert --timing -prefix Vtop -top $tb_top -Dverilatorsim -I../../src/design/includes -I../../src/sim/includes"
        set verilator_input ""
        set verilator_input [concat $verilator_input [glob -nocomplain ../../src/design/*.sv]]
        set verilator_input [concat $verilator_input [glob -nocomplain ../../src/design/*.v]]
        set verilator_input [concat $verilator_input [glob -nocomplain ../../src/sim/*.sv]]
        set verilator_input [concat $verilator_input [glob -nocomplain ../../src/sim/*.v]]
        
        if { [catch {exec sh -c "verilator $verilator_flags $verilator_input" 2> verilator.log} result] } {
                puts "$::errorInfo"
        }
        puts [read [open verilator.log r]]
        set files [glob -nocomplain ./obj_dir/Vtop]
        set len [llength $files]
        if {$len > 0} {
                puts "\n###Starting simulation###"
                exec sh -c "./obj_dir/Vtop" >@stdout
        } else {
                puts "ERROR encountered during Verilator compile step"
                return
        }
} elseif {[string match "iverilog" $simulator]} {
        set iverilog_input ""
        set iverilog_input [concat $iverilog_input [glob -nocomplain ../../src/sim/*.sv]]
        set iverilog_input [concat $iverilog_input [glob -nocomplain ../../src/sim/*.v]] 
        
        if { [catch {exec sh -c "iverilog -g2012 -I../../src/design/includes -Y.sv -Y.v -y../../src/sim -y../../src/design -s $tb_top -o top.out $iverilog_input" 2> iverilog.log} result] } {
                puts "$::errorInfo"
        }
        puts [read [open iverilog.log r]] 
        set files [glob -nocomplain ./top.out]
        set len [llength $files]
        if {$len > 0} {
                puts "\n###Starting simulation###"
                exec sh -c "./top.out" >@stdout
        } else {
                puts "ERROR encountered during Verilator compile step"
                return
        }
}

if {[string match "surver" $waverviewer]} { 
        puts "###Opening wave viewer###"
        exec surfer server --file dump.vcd >@stdout
} elseif {[string match "surfer" $waverviewer]} { 
        puts "###Opening wave viewer###"
        exec surfer dump.vcd >@stdout
}  elseif {[string match "gtkwave" $waverviewer]} {
        puts "###Opening wave viewer###"
        exec gtkwave dump.vcd >@stdout
}  elseif {[string match "manual" $waverviewer]} {
        puts "Wave file dump.vcd created in ./sim_build directory"
} 
