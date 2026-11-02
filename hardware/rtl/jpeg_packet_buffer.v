`timescale 1ns / 1ps
`default_nettype none

// Two packet-sized dual-clock buffers for a variable-length OV5640 JPEG.
// Only complete packets are exposed to the network clock domain.  SOI/EOI
// markers delimit frames and per-packet sequence/flags let the host reject
// any incomplete frame rather than displaying corrupted imagery.
module jpeg_packet_buffer #(
    parameter integer PACKET_BYTES = 1392,
    parameter integer WORDS_PER_PACKET = PACKET_BYTES / 2
) (
    input  wire        cam_clk,
    input  wire        cam_rst,
    input  wire        frame_sync,
    input  wire [7:0]  byte_data,
    input  wire        byte_valid,
    output reg         overflow,

    input  wire        net_clk,
    input  wire        net_rst,
    output wire        packet_req,
    output wire        packet_bank,
    output wire [10:0] packet_len,
    output wire [31:0] packet_frame_id,
    output wire [15:0] packet_sequence,
    output wire [1:0]  packet_flags,
    input  wire        packet_take,
    input  wire        packet_done,

    input  wire        read_bank,
    input  wire [9:0]  read_addr,
    output reg  [15:0] read_data
);
    (* ram_style = "block" *) reg [15:0] memory [0:(2*WORDS_PER_PACKET)-1];

    reg [10:0] meta_len [0:1];
    reg [31:0] meta_frame [0:1];
    reg [15:0] meta_sequence [0:1];
    reg [1:0] meta_flags [0:1];

    reg [1:0] ready_toggle;
    // Each toggle crosses independently through a conventional two-flop
    // synchronizer.  Mark both stages so implementation preserves adjacency
    // and report_cdc recognizes the intended control crossing.
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_cam_sync1, ack_cam_sync2;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ready_net_sync1, ready_net_sync2;
    reg [1:0] ack_toggle;

    reg write_bank;
    reg capturing;
    reg dropping;
    reg soi_ff;
    reg [7:0] previous_byte;
    reg [7:0] pending_byte;
    reg [10:0] byte_count;
    reg [31:0] frame_counter;
    reg [31:0] active_frame_id;
    reg [15:0] active_sequence;
    reg active_sof;

    reg active_net_bank;
    reg expected_net_bank;
    reg packet_active;
    reg packet_inflight;

    wire write_bank_free =
        (ready_toggle[write_bank] == ack_cam_sync2[write_bank]);
    wire other_bank_free =
        (ready_toggle[~write_bank] == ack_cam_sync2[~write_bank]);
    reg mem_write_enable;
    reg [10:0] mem_write_addr;
    reg [15:0] mem_write_data;
    wire [10:0] read_linear_addr = read_bank ?
        (WORDS_PER_PACKET + read_addr) : read_addr;

    assign packet_req = packet_active && !packet_inflight;
    assign packet_bank = active_net_bank;
    assign packet_len = meta_len[active_net_bank];
    assign packet_frame_id = meta_frame[active_net_bank];
    assign packet_sequence = meta_sequence[active_net_bank];
    assign packet_flags = meta_flags[active_net_bank];

    task commit_packet;
        input [10:0] commit_len;
        input commit_eof;
        begin
            meta_len[write_bank] <= commit_len;
            meta_frame[write_bank] <= active_frame_id;
            meta_sequence[write_bank] <= active_sequence;
            meta_flags[write_bank] <= {commit_eof, active_sof};
            ready_toggle[write_bank] <= ~ready_toggle[write_bank];
        end
    endtask

    // Standard simple-dual-port RAM inference: one camera-clock write port
    // and one network-clock read port.  A single linear array avoids a
    // dynamic mux across two memories, which prevents BRAM inference.
    always @* begin
        mem_write_enable = 1'b0;
        mem_write_addr = 11'd0;
        mem_write_data = 16'd0;
        if (!cam_rst && !frame_sync && byte_valid) begin
            if (!capturing && !dropping && soi_ff && byte_data == 8'hd8 &&
                write_bank_free) begin
                mem_write_enable = 1'b1;
                mem_write_addr = write_bank ? WORDS_PER_PACKET : 0;
                mem_write_data = 16'hffd8;
            end else if (capturing) begin
                if (byte_count[0]) begin
                    mem_write_enable = 1'b1;
                    mem_write_addr = (write_bank ? WORDS_PER_PACKET : 0) +
                                     byte_count[10:1];
                    mem_write_data = {pending_byte, byte_data};
                end else if ((previous_byte == 8'hff) &&
                             (byte_data == 8'hd9)) begin
                    mem_write_enable = 1'b1;
                    mem_write_addr = (write_bank ? WORDS_PER_PACKET : 0) +
                                     byte_count[10:1];
                    mem_write_data = {byte_data, 8'h00};
                end
            end
        end
    end

    always @(posedge cam_clk)
        if (mem_write_enable)
            memory[mem_write_addr] <= mem_write_data;

    always @(posedge cam_clk) begin
        ack_cam_sync1 <= ack_toggle;
        ack_cam_sync2 <= ack_cam_sync1;
        if (cam_rst) begin
            ready_toggle <= 2'b00;
            ack_cam_sync1 <= 2'b00;
            ack_cam_sync2 <= 2'b00;
            write_bank <= 1'b0;
            capturing <= 1'b0;
            dropping <= 1'b0;
            soi_ff <= 1'b0;
            previous_byte <= 8'd0;
            pending_byte <= 8'd0;
            byte_count <= 11'd0;
            frame_counter <= 32'd0;
            active_frame_id <= 32'd0;
            active_sequence <= 16'd0;
            active_sof <= 1'b0;
            overflow <= 1'b0;
        end else begin
            if (frame_sync) begin
                if (capturing)
                    overflow <= 1'b1;
                capturing <= 1'b0;
                dropping <= 1'b0;
                soi_ff <= 1'b0;
                byte_count <= 11'd0;
            end else if (byte_valid) begin
                if (!capturing && !dropping) begin
                    if (soi_ff && byte_data == 8'hd8) begin
                        if (write_bank_free) begin
                            frame_counter <= frame_counter + 1'b1;
                            active_frame_id <= frame_counter + 1'b1;
                            active_sequence <= 16'd0;
                            active_sof <= 1'b1;
                            byte_count <= 11'd2;
                            previous_byte <= 8'hd8;
                            capturing <= 1'b1;
                            overflow <= 1'b0;
                        end else begin
                            dropping <= 1'b1;
                            overflow <= 1'b1;
                        end
                        soi_ff <= 1'b0;
                    end else begin
                        soi_ff <= (byte_data == 8'hff);
                    end
                end else if (capturing) begin
                    previous_byte <= byte_data;
                    if (!byte_count[0]) begin
                        pending_byte <= byte_data;
                    end

                    if ((previous_byte == 8'hff) && (byte_data == 8'hd9)) begin
                        commit_packet(byte_count + 1'b1, 1'b1);
                        capturing <= 1'b0;
                        byte_count <= 11'd0;
                        write_bank <= ~write_bank;
                    end else if (byte_count == PACKET_BYTES-1) begin
                        commit_packet(PACKET_BYTES, 1'b0);
                        byte_count <= 11'd0;
                        active_sequence <= active_sequence + 1'b1;
                        active_sof <= 1'b0;
                        write_bank <= ~write_bank;
                        if (!other_bank_free) begin
                            capturing <= 1'b0;
                            dropping <= 1'b1;
                            overflow <= 1'b1;
                        end
                    end else begin
                        byte_count <= byte_count + 1'b1;
                    end
                end else if (dropping) begin
                    if ((previous_byte == 8'hff) && (byte_data == 8'hd9)) begin
                        dropping <= 1'b0;
                        soi_ff <= 1'b0;
                    end
                    previous_byte <= byte_data;
                end
            end
        end
    end

    always @(posedge net_clk) begin
        ready_net_sync1 <= ready_toggle;
        ready_net_sync2 <= ready_net_sync1;
        if (net_rst) begin
            ready_net_sync1 <= 2'b00;
            ready_net_sync2 <= 2'b00;
            ack_toggle <= 2'b00;
            active_net_bank <= 1'b0;
            expected_net_bank <= 1'b0;
            packet_active <= 1'b0;
            packet_inflight <= 1'b0;
        end else begin
            if (!packet_active &&
                (ready_net_sync2[expected_net_bank] !=
                 ack_toggle[expected_net_bank])) begin
                active_net_bank <= expected_net_bank;
                packet_active <= 1'b1;
                packet_inflight <= 1'b0;
            end
            if (packet_take && packet_active && !packet_inflight)
                packet_inflight <= 1'b1;
            if (packet_done && packet_active && packet_inflight) begin
                ack_toggle[active_net_bank] <= ready_net_sync2[active_net_bank];
                expected_net_bank <= ~active_net_bank;
                packet_active <= 1'b0;
                packet_inflight <= 1'b0;
            end
        end
    end

    always @(posedge net_clk)
        read_data <= memory[read_linear_addr];
endmodule

`default_nettype wire
