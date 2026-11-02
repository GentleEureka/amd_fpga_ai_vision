set root_dir [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $root_dir project]
set project_name amd_fpga_continuous_vision_v2
file mkdir $project_dir

create_project $project_name $project_dir -force -part xcku040-ffva1156-2-e
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

set custom_rtl [lsort [glob -nocomplain [file join $root_dir rtl *.v]]]
if {[llength $custom_rtl] == 0} {
    error "No project-authored Verilog files found under rtl/"
}
read_verilog $custom_rtl

set vendor_support_verilog [lsort [concat \
    [glob -nocomplain [file join $root_dir ip legacy_10g support pcs_pma *.v]] \
    [glob -nocomplain [file join $root_dir ip legacy_10g support xge_mac *.v]]]]
set vendor_support_vhdl [lsort [concat \
    [glob -nocomplain [file join $root_dir ip legacy_10g support pcs_pma *.vhd]] \
    [glob -nocomplain [file join $root_dir ip legacy_10g support xge_mac *.vhd]]]]
read_verilog $vendor_support_verilog
read_vhdl $vendor_support_vhdl

foreach xci_path [list \
    [file join $root_dir ip clkgen_300m_to_100m clkgen_300m_to_100m.xci] \
    [file join $root_dir ip legacy_10g ten_gig_eth_mac_0 ten_gig_eth_mac_0.xci] \
    [file join $root_dir ip legacy_10g ten_gig_eth_pcs_pma_0 ten_gig_eth_pcs_pma_0.xci]] {
    if {![file exists $xci_path]} {
        error "Missing generated IP: $xci_path"
    }
    read_ip $xci_path
}

set board_xdc [file join $root_dir constraints mc02_sfp1_10g_camera.xdc]
set impl_xdc [file join $root_dir constraints mc02_sfp1_10g_camera_impl.xdc]
read_xdc $board_xdc
read_xdc $impl_xdc
set_property USED_IN_SYNTHESIS false [get_files $impl_xdc]
set_property PROCESSING_ORDER LATE [get_files $impl_xdc]

set_property top mc02_sfp1_10g_camera_top [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PROJECT_FILE=[file join $project_dir ${project_name}.xpr]"

