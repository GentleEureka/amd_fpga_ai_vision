set cfgmem_name s25fl256sxxxxxx0-spi-x1_x2_x4_x8
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
    error "Expected one cfgmem part '$cfgmem_name'"
}
create_hw_cfgmem -hw_device $device [lindex $cfgmem_parts 0]
boot_hw_device $device
after 5000
refresh_hw_device $device
puts "FLASH_BOOT_SENT=1"
puts "FLASH_BOOT_DONE=[get_property REGISTER.CONFIG_STATUS.BIT\[14\]_DONE_PIN $device]"
close_hw_target
disconnect_hw_server
close_hw_manager
exit
