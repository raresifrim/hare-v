#------------------------------------------------------------------------
# reportCriticalPaths
#------------------------------------------------------------------------
# This function generates a CSV file that provides a summary of the first
# 50 violations for both Setup and Hold analysis. So a maximum number of 
# 100 paths are reported.
#------------------------------------------------------------------------
proc reportCriticalPaths { fileName } {
  # Open the specified output file in write mode
  set FH [open $fileName w]
  # Write the current date and CSV format to a file header
  puts $FH "#\n# File created on [clock format [clock seconds]]\n#\n"
  puts $FH "Startpoint,Endpoint,DelayType,Slack,#Levels,#LUTs"
  # Iterate through both Min and Max delay types
  foreach delayType {max min} {
    # Collect details from the 50 worst timing paths for the current analysis 
    # (max = setup/recovery, min = hold/removal) 
    # The $path variable contains a Timing Path object.
    foreach path [get_timing_paths -delay_type $delayType -max_paths 50 -nworst 1] {
      # Get the LUT cells of the timing paths
      set luts [get_cells -filter {REF_NAME =~ LUT*} -of_object $path]
      # Get the startpoint of the Timing Path object
      set startpoint [get_property STARTPOINT_PIN $path]
      # Get the endpoint of the Timing Path object
      set endpoint [get_property ENDPOINT_PIN $path]
      # Get the slack on the Timing Path object
      set slack [get_property SLACK $path]
      # Get the number of logic levels between startpoint and endpoint
      set levels [get_property LOGIC_LEVELS $path]
      # Save the collected path details to the CSV file
      puts $FH "$startpoint,$endpoint,$delayType,$slack,$levels,[llength $luts]"
    }
  }
  # Close the output file
  close $FH
  puts "CSV file $fileName has been created.\n"
  return 0
}; # End PROC

set files [glob -nocomplain ../../src/design/*.sv]
set len [llength $files]
if {$len > 0} {
	read_verilog [ glob -nocomplain ../../src/design/*.sv ]
}
set files [glob -nocomplain ../../src/design/*.v]
set len [llength $files]
if {$len > 0} {
	read_verilog [ glob -nocomplain ../../src/design/*.v ]
}
set files [glob -nocomplain ../../src/constr/*.xdc]
set len [llength $files]
if {$len > 0} {
	read_xdc [ glob -nocomplain ../../src/constr/*.xdc ]
}

#
# STEP#1: run synthesis, write design checkpoint, report timing,
# and utilization estimates
#
synth_design -top [lindex $argv 0] -part [lindex $argv 1]
write_checkpoint -force post_synth.dcp
report_timing_summary -file post_synth_timing_summary.rpt
report_utilization -file post_synth_util.rpt
#
# Run custom script to report critical timing paths
reportCriticalPaths post_synth_critpath_report.csv