set root_dir [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $root_dir reports generated]
set output_dir [file join $root_dir output generated]
file mkdir $report_dir
file mkdir $output_dir

source [file join $root_dir scripts create_project.tcl]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis did not complete: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing_summary.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation did not complete: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -max_paths 20 -file [file join $report_dir post_route_timing_summary.rpt]
report_clock_utilization -file [file join $report_dir post_route_clock_utilization.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]

set bit_files [glob -nocomplain [file join $root_dir project ${project_name}.runs impl_1 *.bit]]
if {[llength $bit_files] != 1} {
    error "Expected one generated bitstream, found [llength $bit_files]"
}
file copy -force [lindex $bit_files 0] [file join $output_dir ${project_name}.bit]
puts "BITSTREAM=[file join $output_dir ${project_name}.bit]"

