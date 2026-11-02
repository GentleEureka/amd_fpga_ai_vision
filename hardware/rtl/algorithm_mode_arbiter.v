`timescale 1ns / 1ps
`default_nettype none

// Combines the four debounced board push-buttons with host commands.
// Each button directly selects one mode. Host and button requests share one
// toggle/sequence interface, so the proven RGB565 processor sees one source.
module algorithm_mode_arbiter #(
    parameter integer DEBOUNCE_CYCLES = 1_562_500
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  buttons,
    input  wire [1:0]  host_mode,
    input  wire [7:0]  host_threshold,
    input  wire [7:0]  host_sequence,
    input  wire        host_toggle,
    output reg  [1:0]  requested_mode,
    output reg  [7:0]  requested_threshold,
    output reg  [7:0]  requested_sequence,
    output reg         update_toggle
);
    (* ASYNC_REG = "TRUE" *) reg [3:0] button_sync1, button_sync2;
    reg [3:0] button_stable;
    reg [3:0] button_previous;
    reg [20:0] debounce_count [0:3];
    reg host_toggle_seen;
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            button_sync1 <= 4'd0;
            button_sync2 <= 4'd0;
            button_stable <= 4'd0;
            button_previous <= 4'd0;
            host_toggle_seen <= 1'b0;
            requested_mode <= 2'd0;
            requested_threshold <= 8'd128;
            requested_sequence <= 8'd0;
            update_toggle <= 1'b0;
            for (i = 0; i < 4; i = i + 1)
                debounce_count[i] <= 21'd0;
        end else begin
            button_sync1 <= buttons;
            button_sync2 <= button_sync1;

            for (i = 0; i < 4; i = i + 1) begin
                if (button_sync2[i] == button_stable[i]) begin
                    debounce_count[i] <= 21'd0;
                end else if (debounce_count[i] == DEBOUNCE_CYCLES-1) begin
                    button_stable[i] <= button_sync2[i];
                    debounce_count[i] <= 21'd0;
                end else begin
                    debounce_count[i] <= debounce_count[i] + 1'b1;
                end
            end
            button_previous <= button_stable;

            // A valid host command wins only in the cycle it arrives.
            if (host_toggle != host_toggle_seen) begin
                host_toggle_seen <= host_toggle;
                requested_mode <= host_mode;
                requested_threshold <= host_threshold;
                requested_sequence <= host_sequence;
                update_toggle <= ~update_toggle;
            end else if (button_stable[0] && !button_previous[0]) begin
                requested_mode <= 2'd0;
                requested_threshold <= 8'd128;
                requested_sequence <= requested_sequence + 1'b1;
                update_toggle <= ~update_toggle;
            end else if (button_stable[1] && !button_previous[1]) begin
                requested_mode <= 2'd1;
                requested_threshold <= 8'd128;
                requested_sequence <= requested_sequence + 1'b1;
                update_toggle <= ~update_toggle;
            end else if (button_stable[2] && !button_previous[2]) begin
                requested_mode <= 2'd2;
                requested_threshold <= host_threshold;
                requested_sequence <= requested_sequence + 1'b1;
                update_toggle <= ~update_toggle;
            end else if (button_stable[3] && !button_previous[3]) begin
                requested_mode <= 2'd3;
                requested_threshold <= 8'd128;
                requested_sequence <= requested_sequence + 1'b1;
                update_toggle <= ~update_toggle;
            end
        end
    end
endmodule

`default_nettype wire
