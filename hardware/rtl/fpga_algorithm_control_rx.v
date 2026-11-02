`timescale 1ns / 1ps
`default_nettype none

// Receives a compact raw-Ethernet command on the 10G MAC RX AXI stream.
// Wire format (absolute Ethernet byte offsets):
//   12..13  EtherType 88B5
//   14..17  ASCII "FALG"
//   18      protocol version (1)
//   19      command sequence
//   20      FPGA pixel mode: 0=color, 1=gray, 2=binary threshold, 3=invert
//   21      luminance threshold used by mode 2
//   22      A5 xor sequence xor algorithm xor threshold
// The update output is a toggle so no command pulse is lost across the
// independent camera pixel clock domain.
module fpga_algorithm_control_rx (
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] rx_axis_tdata,
    input  wire [7:0]  rx_axis_tkeep,
    input  wire        rx_axis_tvalid,
    input  wire        rx_axis_tlast,
    output reg  [1:0]  requested_mode,
    output reg  [7:0]  requested_threshold,
    output reg  [7:0]  requested_sequence,
    output reg         update_toggle,
    output reg  [31:0] accepted_count,
    output reg  [31:0] rejected_count
);
    reg [7:0] beat_index;
    reg       command_prefix;

    always @(posedge clk) begin
        if (rst) begin
            beat_index <= 8'd0;
            command_prefix <= 1'b0;
            requested_mode <= 2'd0;
            requested_threshold <= 8'd128;
            requested_sequence <= 8'd0;
            update_toggle <= 1'b0;
            accepted_count <= 32'd0;
            rejected_count <= 32'd0;
        end else if (rx_axis_tvalid) begin
            // The Xilinx MAC presents the first Ethernet byte in lane 0.
            // Npcap emits a minimum 60-byte frame, so the command header is
            // always in the first three complete AXI beats.
            if (beat_index == 8'd1 && rx_axis_tkeep == 8'hFF) begin
                command_prefix <=
                    rx_axis_tdata[39:32] == 8'h88 &&
                    rx_axis_tdata[47:40] == 8'hB5 &&
                    rx_axis_tdata[55:48] == "F" &&
                    rx_axis_tdata[63:56] == "A";
            end
            if (beat_index == 8'd2 && command_prefix &&
                rx_axis_tkeep[6:0] == 7'h7F) begin
                if (rx_axis_tdata[7:0] == "L" &&
                    rx_axis_tdata[15:8] == "G" &&
                    rx_axis_tdata[23:16] == 8'd1 &&
                    rx_axis_tdata[39:32] <= 8'd3 &&
                    rx_axis_tdata[55:48] ==
                        (8'hA5 ^ rx_axis_tdata[31:24] ^
                         rx_axis_tdata[39:32] ^ rx_axis_tdata[47:40])) begin
                    requested_sequence <= rx_axis_tdata[31:24];
                    requested_mode <= rx_axis_tdata[33:32];
                    requested_threshold <= rx_axis_tdata[47:40];
                    update_toggle <= ~update_toggle;
                    accepted_count <= accepted_count + 1'b1;
                end else begin
                    rejected_count <= rejected_count + 1'b1;
                end
            end
            if (rx_axis_tlast) begin
                beat_index <= 8'd0;
                command_prefix <= 1'b0;
            end else begin
                beat_index <= beat_index + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
