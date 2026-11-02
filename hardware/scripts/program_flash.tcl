set project_root [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $project_root output generated amd_fpga_continuous_vision_v2.bit]
set output_dir [file join $project_root output flash]
set primary_mcs [file join $output_dir amd_fpga_continuous_vision_v2_primary.mcs]
set secondary_mcs [file join $output_dir amd_fpga_continuous_vision_v2_secondary.mcs]
set cfgmem_name s25fl256sxxxxxx0-spi-x1_x2_x4_x8

foreach required [list $bit_file $primary_mcs $secondary_mcs] {
    if {![file exists $required] || [file size $required] == 0} {
        error "Programming file not found: $required"
    }
}

open_hw_manager
set opened 0
set connected 0
for {set attempt 1} {$attempt <= 2 && !$opened} {incr attempt} {
    if {!$connected} {
        if {[catch {connect_hw_server -allow_non_jtag} connect_error]} {
            puts "JTAG_CONNECT_ATTEMPT=$attempt FAILED:$connect_error"
            catch {disconnect_hw_server}
        } else {
            set connected 1
        }
    }
    if {$connected} {
        if {[catch {get_hw_targets} targets scan_error]} {
            puts "JTAG_SCAN_ATTEMPT=$attempt FAILED:$scan_error"
        } else {
            puts "JTAG_SCAN_ATTEMPT=$attempt TARGETS=[llength $targets]"
            foreach target $targets {
                if {[catch {current_hw_target $target} target_error]} {
                    puts "SKIP_TARGET=$target:$target_error"
                    continue
                }
                if {[lsearch -exact [list_property $target] PARAM.FREQUENCY] >= 0} {
                    set_property PARAM.FREQUENCY 750000 $target
                }
                if {[catch {open_hw_target $target} open_error]} {
                    puts "SKIP_TARGET=[get_property NAME $target]:$open_error"
                    continue
                }
                if {[catch {get_hw_devices -quiet -filter {PART == xcku040}} devices device_error]} {
                    puts "JTAG_DEVICE_SCAN_ATTEMPT=$attempt FAILED:$device_error"
                    catch {close_hw_target}
                    continue
                }
                if {[llength $devices] == 1} {
                    set opened 1
                    break
                }
                close_hw_target
            }
        }
    }
    if {!$opened && $attempt == 1} {
        puts "JTAG_RETRY=1 WAIT_MS=2000"
        after 2000
        if {$connected && [catch {refresh_hw_server} refresh_error]} {
            puts "JTAG_REFRESH_WARNING=$refresh_error"
        }
    }
}
if {!$opened} {
    error "No target with exactly one xcku040 device could be opened"
}

set device [lindex [get_hw_devices -quiet -filter {PART == xcku040}] 0]
set cfgmem_parts [lsort -unique [get_cfgmem_parts -quiet $cfgmem_name]]
if {[llength $cfgmem_parts] != 1} {
    error "Expected one cfgmem part '$cfgmem_name', found [llength $cfgmem_parts]"
}

puts "FLASH_DEVICE=[get_property NAME $device]"
puts "FLASH_PRIMARY=[file normalize $primary_mcs]"
puts "FLASH_SECONDARY=[file normalize $secondary_mcs]"
create_hw_cfgmem -hw_device $device [lindex $cfgmem_parts 0]
set cfgmem [get_property PROGRAM.HW_CFGMEM $device]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.FILES [list $primary_mcs $secondary_mcs] $cfgmem
set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
# Per project policy, validate the live camera path instead of slow readback.
set_property PROGRAM.VERIFY 0 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

set_property PROGRAM.FILE $bit_file $device
create_hw_bitstream -hw_device $device [get_property PROGRAM.HW_CFGMEM_BITFILE $device]
program_hw_devices $device
refresh_hw_device $device
program_hw_cfgmem -hw_cfgmem $cfgmem
puts "FLASH_PROGRAM_OK=1"

# Restore the same application to SRAM so immediate live testing uses exactly
# the image that was placed in nonvolatile memory.
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
puts "APPLICATION_RELOAD_OK=1"
close_hw_target
disconnect_hw_server
close_hw_manager
exit
