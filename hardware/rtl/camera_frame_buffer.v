`timescale 1ns / 1ps
`default_nettype none

// Complete-frame dual-clock store.
//
// CAM1 writes one full RGB565 frame before the network side exposes any
// packet.  The network then walks the frozen frame in 696-word chunks.  The
// ready/ack toggle handshake guarantees that a new camera frame cannot
// overwrite memory until every packet of the previous frame has completed.
module camera_frame_buffer #(
    parameter integer FRAME_PIXELS = 307200,
    parameter integer WORDS_PER_PACKET = 696
) (
    input  wire        cam_clk,
    input  wire        cam_rst,
    input  wire        frame_sync,
    input  wire [15:0] pixel_data,
    input  wire        pixel_valid,
    output reg         overflow,

    input  wire        net_clk,
    input  wire        net_rst,
    output wire        packet_req,
    output wire        packet_bank,
    output wire [10:0] packet_len,
    output wire [31:0] packet_frame_id,
    input  wire        packet_take,
    input  wire        packet_done,

    input  wire        read_bank,
    input  wire [9:0]  read_addr,
    output reg  [15:0] read_data
);

    localparam integer FRAME_ADDR_WIDTH = $clog2(FRAME_PIXELS);
    localparam integer PACKETS_PER_FRAME =
        (FRAME_PIXELS + WORDS_PER_PACKET - 1) / WORDS_PER_PACKET;
    localparam integer PACKET_INDEX_WIDTH = $clog2(PACKETS_PER_FRAME);
    localparam integer LAST_PACKET_WORDS =
        FRAME_PIXELS - ((PACKETS_PER_FRAME - 1) * WORDS_PER_PACKET);
    localparam [10:0] FULL_PACKET_BYTES = WORDS_PER_PACKET * 2;
    localparam [10:0] LAST_PACKET_BYTES = LAST_PACKET_WORDS * 2;

    (* ram_style = "block" *) reg [15:0] memory [0:FRAME_PIXELS-1];

    reg [FRAME_ADDR_WIDTH-1:0] write_addr;
    reg                        capturing;
    reg [31:0]                 camera_frame_id;
    reg [31:0]                 completed_frame_id;
    reg                        ready_toggle;
    reg                        ack_cam_sync1;
    reg                        ack_cam_sync2;

    reg                        ready_net_sync1;
    reg                        ready_net_sync2;
    reg                        ack_toggle;
    reg                        frame_active;
    reg                        packet_inflight;
    reg [PACKET_INDEX_WIDTH-1:0] packet_index;
    reg [31:0]                 active_frame_id;

    wire buffer_free = (ready_toggle == ack_cam_sync2);
    wire last_packet = (packet_index == PACKETS_PER_FRAME-1);
    wire [FRAME_ADDR_WIDTH-1:0] absolute_read_addr =
        (packet_index * WORDS_PER_PACKET) + read_addr;

    assign packet_req = frame_active && !packet_inflight;
    assign packet_bank = 1'b0;
    assign packet_len = last_packet ? LAST_PACKET_BYTES : FULL_PACKET_BYTES;
    assign packet_frame_id = active_frame_id;

    // read_bank remains in the interface so the existing packetizer can be
    // reused unchanged; a complete-frame store needs only one RAM bank.
    wire unused_read_bank = read_bank;

    always @(posedge cam_clk) begin
        ack_cam_sync1 <= ack_toggle;
        ack_cam_sync2 <= ack_cam_sync1;

        if (cam_rst) begin
            write_addr         <= {FRAME_ADDR_WIDTH{1'b0}};
            capturing          <= 1'b0;
            camera_frame_id    <= 32'd0;
            completed_frame_id <= 32'd0;
            ready_toggle       <= 1'b0;
            ack_cam_sync1      <= 1'b0;
            ack_cam_sync2      <= 1'b0;
            overflow           <= 1'b0;
        end else begin
            if (frame_sync) begin
                camera_frame_id <= camera_frame_id + 1'b1;
                write_addr <= {FRAME_ADDR_WIDTH{1'b0}};
                if (buffer_free) begin
                    capturing <= 1'b1;
                    overflow <= 1'b0;
                end else begin
                    capturing <= 1'b0;
                    overflow <= 1'b1;
                end
            end else if (pixel_valid && capturing) begin
                memory[write_addr] <= pixel_data;
                if (write_addr == FRAME_PIXELS-1) begin
                    completed_frame_id <= camera_frame_id;
                    ready_toggle <= ~ready_toggle;
                    write_addr <= {FRAME_ADDR_WIDTH{1'b0}};
                    capturing <= 1'b0;
                end else begin
                    write_addr <= write_addr + 1'b1;
                end
            end
        end
    end

    always @(posedge net_clk) begin
        ready_net_sync1 <= ready_toggle;
        ready_net_sync2 <= ready_net_sync1;

        if (net_rst) begin
            ready_net_sync1 <= 1'b0;
            ready_net_sync2 <= 1'b0;
            ack_toggle <= 1'b0;
            frame_active <= 1'b0;
            packet_inflight <= 1'b0;
            packet_index <= {PACKET_INDEX_WIDTH{1'b0}};
            active_frame_id <= 32'd0;
        end else begin
            if (!frame_active && (ready_net_sync2 != ack_toggle)) begin
                frame_active <= 1'b1;
                packet_inflight <= 1'b0;
                packet_index <= {PACKET_INDEX_WIDTH{1'b0}};
                active_frame_id <= completed_frame_id;
            end

            if (packet_take && frame_active && !packet_inflight)
                packet_inflight <= 1'b1;

            if (packet_done && frame_active && packet_inflight) begin
                packet_inflight <= 1'b0;
                if (last_packet) begin
                    ack_toggle <= ready_net_sync2;
                    frame_active <= 1'b0;
                    packet_index <= {PACKET_INDEX_WIDTH{1'b0}};
                end else begin
                    packet_index <= packet_index + 1'b1;
                end
            end
        end
    end

    always @(posedge net_clk)
        read_data <= memory[absolute_read_addr];

endmodule

`default_nettype wire
