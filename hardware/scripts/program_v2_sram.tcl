set root_dir [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $root_dir output generated amd_fpga_continuous_vision_v2.bit]

if {![file exists $bit_file]} {
    error "V2 bitstream not found: $bit_file"
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
puts "PROGRAM_TARGET=[get_property NAME [current_hw_target]]"
puts "PROGRAM_DEVICE=[get_property NAME $device] PART=[get_property PART $device]"
puts "PROGRAM_FILE=[file normalize $bit_file] SIZE=[file size $bit_file]"

set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

set done_prop "REGISTER.CONFIG_STATUS.BIT\[14\]_DONE_PIN"
set crc_prop "REGISTER.CONFIG_STATUS.BIT\[0\]_CRC_ERROR"
set idcode_prop "REGISTER.CONFIG_STATUS.BIT\[15\]_IDCODE_ERROR"
foreach prop [list $done_prop $crc_prop $idcode_prop] {
    if {[lsearch -exact [list_property $device] $prop] >= 0} {
        puts "POST_$prop=[get_property $prop $device]"
    }
}
if {[lsearch -exact [list_property $device] $done_prop] < 0 || [get_property $done_prop $device] ne "1"} {
    error "V2 programming completed but DONE is not asserted"
}
puts "V2_SRAM_PROGRAM_OK=[get_property NAME $device]"

close_hw_target
disconnect_hw_server
close_hw_manager
exit

