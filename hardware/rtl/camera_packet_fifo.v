`timescale 1ns / 1ps
`default_nettype none

// Eight-packet asynchronous FIFO between OV5640 PCLK and the 156.25 MHz MAC.
// Packet metadata is held stable until the network side advances its pointer.
module camera_packet_fifo #(
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
    output wire [2:0]  packet_bank,
    output wire [10:0] packet_len,
    output wire [31:0] packet_frame_id,
    input  wire        packet_take,
    input  wire        packet_done,

    input  wire [2:0]  read_bank,
    input  wire [9:0]  read_addr,
    output reg  [15:0] read_data
);
    localparam integer FRAME_COUNT_WIDTH = $clog2(FRAME_PIXELS + 1);
    (* ram_style = "block" *) reg [15:0] memory [0:8191];
    reg [10:0] metadata_len [0:7];
    reg [31:0] metadata_frame [0:7];

    reg [3:0] write_ptr_bin;
    reg [3:0] write_ptr_gray;
    reg [3:0] read_ptr_bin;
    reg [3:0] read_ptr_gray;
    (* ASYNC_REG = "TRUE" *) reg [3:0] read_gray_cam1;
    (* ASYNC_REG = "TRUE" *) reg [3:0] read_gray_cam2;
    (* ASYNC_REG = "TRUE" *) reg [3:0] write_gray_net1;
    (* ASYNC_REG = "TRUE" *) reg [3:0] write_gray_net2;

    reg [9:0] write_count;
    reg [FRAME_COUNT_WIDTH-1:0] frame_pixel_count;
    reg [31:0] frame_id;
    reg in_frame;
    reg drop_frame;

    wire [3:0] write_ptr_bin_next = write_ptr_bin + 1'b1;
    wire [3:0] write_ptr_gray_next =
        (write_ptr_bin_next >> 1) ^ write_ptr_bin_next;
    wire fifo_full = write_ptr_gray_next ==
        {~read_gray_cam2[3:2], read_gray_cam2[1:0]};
    wire fifo_empty = read_ptr_gray == write_gray_net2;
    wire [12:0] write_memory_addr = {write_ptr_bin[2:0], write_count};
    wire [12:0] read_memory_addr = {read_bank, read_addr};

    assign packet_req = !fifo_empty;
    assign packet_bank = read_ptr_bin[2:0];
    assign packet_len = metadata_len[read_ptr_bin[2:0]];
    assign packet_frame_id = metadata_frame[read_ptr_bin[2:0]];

    always @(posedge cam_clk) begin
        read_gray_cam1 <= read_ptr_gray;
        read_gray_cam2 <= read_gray_cam1;
        if (cam_rst) begin
            write_ptr_bin <= 4'd0;
            write_ptr_gray <= 4'd0;
            read_gray_cam1 <= 4'd0;
            read_gray_cam2 <= 4'd0;
            write_count <= 10'd0;
            frame_pixel_count <= {FRAME_COUNT_WIDTH{1'b0}};
            frame_id <= 32'd0;
            in_frame <= 1'b0;
            drop_frame <= 1'b0;
            overflow <= 1'b0;
        end else begin
            if (frame_sync) begin
                // End the preceding sensor frame with a short final packet.
                // The previous implementation discarded write_count here,
                // making all non-configured input dimensions look truncated.
                if (in_frame && !drop_frame && (write_count != 0)) begin
                    if (!fifo_full) begin
                        metadata_len[write_ptr_bin[2:0]] <= {write_count, 1'b0};
                        metadata_frame[write_ptr_bin[2:0]] <= frame_id;
                        write_ptr_bin <= write_ptr_bin_next;
                        write_ptr_gray <= write_ptr_gray_next;
                    end else begin
                        overflow <= 1'b1;
                    end
                end
                frame_id <= frame_id + 1'b1;
                frame_pixel_count <= {FRAME_COUNT_WIDTH{1'b0}};
                write_count <= 10'd0;
                in_frame <= !fifo_full;
                drop_frame <= fifo_full;
                if (fifo_full)
                    overflow <= 1'b1;
            end else if (pixel_valid && in_frame && !drop_frame) begin
                if (fifo_full) begin
                    drop_frame <= 1'b1;
                    overflow <= 1'b1;
                end else begin
                    memory[write_memory_addr] <= pixel_data;
                    frame_pixel_count <= frame_pixel_count + 1'b1;
                    if ((write_count == WORDS_PER_PACKET-1) ||
                        (frame_pixel_count == FRAME_PIXELS-1)) begin
                        metadata_len[write_ptr_bin[2:0]] <=
                            {write_count + 10'd1, 1'b0};
                        metadata_frame[write_ptr_bin[2:0]] <= frame_id;
                        write_ptr_bin <= write_ptr_bin_next;
                        write_ptr_gray <= write_ptr_gray_next;
                        write_count <= 10'd0;
                        if (frame_pixel_count == FRAME_PIXELS-1)
                            in_frame <= 1'b0;
                    end else begin
                        write_count <= write_count + 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge net_clk) begin
        write_gray_net1 <= write_ptr_gray;
        write_gray_net2 <= write_gray_net1;
        read_data <= memory[read_memory_addr];
        if (net_rst) begin
            read_ptr_bin <= 4'd0;
            read_ptr_gray <= 4'd0;
            write_gray_net1 <= 4'd0;
            write_gray_net2 <= 4'd0;
        // The packet source captures packet_bank/metadata in the same cycle
        // that it asserts packet_take.  Advance here so that its next visit
        // to IDLE cannot capture the just-consumed bank a second time.
        // The eight-bank ring keeps the captured bank reserved long enough
        // for the source to finish reading its payload.
        end else if (packet_take && !fifo_empty) begin
            read_ptr_bin <= read_ptr_bin + 1'b1;
            read_ptr_gray <= ((read_ptr_bin + 1'b1) >> 1) ^
                             (read_ptr_bin + 1'b1);
        end
    end

    wire _unused_packet_done = packet_done;
endmodule

`default_nettype wire
