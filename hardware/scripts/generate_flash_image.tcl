set project_root [file normalize [file join [file dirname [info script]] ..]]
set bit_file [file join $project_root output generated amd_fpga_continuous_vision_v2.bit]
set output_dir [file join $project_root output flash]
set mcs_base [file join $output_dir amd_fpga_continuous_vision_v2.mcs]

if {![file exists $bit_file] || [file size $bit_file] == 0} {
    error "Verified V2 bitstream not found: $bit_file"
}
file mkdir $output_dir

# MC02 uses two S25FL256S devices as one SPIx8, 64 MiB configuration memory.
# Vivado emits the _primary/_secondary MCS and PRM pairs from this base name.
write_cfgmem -force -format mcs -interface SPIx8 -size 64 \
    -loadbit "up 0x0 $bit_file" -file $mcs_base

foreach suffix {primary.mcs secondary.mcs primary.prm secondary.prm} {
    set generated [file join $output_dir amd_fpga_continuous_vision_v2_$suffix]
    if {![file exists $generated] || [file size $generated] == 0} {
        error "SPIx8 image generation failed: $generated"
    }
    puts "FLASH_IMAGE=[file normalize $generated] SIZE=[file size $generated]"
}
puts "FLASH_IMAGE_OK=1"
exit
