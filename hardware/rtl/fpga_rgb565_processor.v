`timescale 1ns / 1ps
`default_nettype none

// Runtime-selectable RGB565 processing. Commands cross from the 156.25 MHz
// network clock and are committed only on a camera frame boundary.
module fpga_rgb565_processor (
    input  wire        control_clk,
    input  wire        control_rst,
    input  wire [1:0]  requested_mode,
    input  wire [7:0]  requested_threshold,
    input  wire [7:0]  requested_sequence,
    input  wire        update_toggle,

    input  wire        pixel_clk,
    input  wire        pixel_rst,
    input  wire [15:0] pixel_in,
    input  wire        pixel_valid_in,
    input  wire        frame_sync_in,
    output wire [15:0] pixel_out,
    output wire        pixel_valid_out,
    output wire        frame_sync_out,

    output reg  [1:0]  applied_mode_control,
    output reg  [7:0]  applied_threshold_control,
    output reg  [7:0]  applied_sequence_control
);
    (* ASYNC_REG = "TRUE" *) reg update_sync1;
    (* ASYNC_REG = "TRUE" *) reg update_sync2;
    reg update_seen;
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_sync1;
    (* ASYNC_REG = "TRUE" *) reg [1:0] mode_sync2;
    (* ASYNC_REG = "TRUE" *) reg [7:0] threshold_sync1;
    (* ASYNC_REG = "TRUE" *) reg [7:0] threshold_sync2;
    (* ASYNC_REG = "TRUE" *) reg [7:0] sequence_sync1;
    (* ASYNC_REG = "TRUE" *) reg [7:0] sequence_sync2;

    reg [1:0] pending_mode;
    reg [7:0] pending_threshold;
    reg [7:0] pending_sequence;
    reg pending_valid;
    reg [1:0] applied_mode_pixel;
    reg [7:0] applied_threshold_pixel;
    reg [7:0] applied_sequence_pixel;

    (* ASYNC_REG = "TRUE" *) reg [1:0] applied_mode_sync1;
    (* ASYNC_REG = "TRUE" *) reg [7:0] applied_threshold_sync1;
    (* ASYNC_REG = "TRUE" *) reg [7:0] applied_sequence_sync1;

    wire [7:0] red8 = {pixel_in[15:11], pixel_in[15:13]};
    wire [7:0] green8 = {pixel_in[10:5], pixel_in[10:9]};
    wire [7:0] blue8 = {pixel_in[4:0], pixel_in[4:2]};
    wire [15:0] luminance_sum = red8 * 8'd77 + green8 * 8'd150 + blue8 * 8'd29;
    wire [7:0] gray8 = luminance_sum[15:8];
    wire [15:0] gray565 = {gray8[7:3], gray8[7:2], gray8[7:3]};
    wire [15:0] binary565 = (gray8 >= applied_threshold_pixel) ? 16'hFFFF : 16'h0000;

    assign pixel_out = (applied_mode_pixel == 2'd1) ? gray565 :
                       (applied_mode_pixel == 2'd2) ? binary565 :
                       (applied_mode_pixel == 2'd3) ? ~pixel_in : pixel_in;
    assign pixel_valid_out = pixel_valid_in;
    assign frame_sync_out = frame_sync_in;

    always @(posedge pixel_clk) begin
        if (pixel_rst) begin
            update_sync1 <= 1'b0;
            update_sync2 <= 1'b0;
            update_seen <= 1'b0;
            mode_sync1 <= 2'd0;
            mode_sync2 <= 2'd0;
            threshold_sync1 <= 8'd128;
            threshold_sync2 <= 8'd128;
            sequence_sync1 <= 8'd0;
            sequence_sync2 <= 8'd0;
            pending_mode <= 2'd0;
            pending_threshold <= 8'd128;
            pending_sequence <= 8'd0;
            pending_valid <= 1'b0;
            applied_mode_pixel <= 2'd0;
            applied_threshold_pixel <= 8'd128;
            applied_sequence_pixel <= 8'd0;
        end else begin
            update_sync1 <= update_toggle;
            update_sync2 <= update_sync1;
            mode_sync1 <= requested_mode;
            mode_sync2 <= mode_sync1;
            threshold_sync1 <= requested_threshold;
            threshold_sync2 <= threshold_sync1;
            sequence_sync1 <= requested_sequence;
            sequence_sync2 <= sequence_sync1;

            if (update_sync2 != update_seen) begin
                update_seen <= update_sync2;
                pending_mode <= mode_sync2;
                pending_threshold <= threshold_sync2;
                pending_sequence <= sequence_sync2;
                pending_valid <= 1'b1;
            end
            if (frame_sync_in && pending_valid) begin
                applied_mode_pixel <= pending_mode;
                applied_threshold_pixel <= pending_threshold;
                applied_sequence_pixel <= pending_sequence;
                pending_valid <= 1'b0;
            end
        end
    end

    always @(posedge control_clk) begin
        if (control_rst) begin
            applied_mode_sync1 <= 2'd0;
            applied_threshold_sync1 <= 8'd128;
            applied_sequence_sync1 <= 8'd0;
            applied_mode_control <= 2'd0;
            applied_threshold_control <= 8'd128;
            applied_sequence_control <= 8'd0;
        end else begin
            applied_mode_sync1 <= applied_mode_pixel;
            applied_threshold_sync1 <= applied_threshold_pixel;
            applied_sequence_sync1 <= applied_sequence_pixel;
            applied_mode_control <= applied_mode_sync1;
            applied_threshold_control <= applied_threshold_sync1;
            applied_sequence_control <= applied_sequence_sync1;
        end
    end
endmodule

`default_nettype wire
