`timescale 1ns / 1ps
`default_nettype none

// Ethernet/IPv4/UDP transmitter for OVJ2 variable-length JPEG chunks.
// The 22-byte application header ends at byte 63, so JPEG data starts on an
// AXI64 beat boundary.  Partial final beats use tkeep to preserve odd JPEG
// lengths without adding bytes to the UDP datagram.
module udp_jpeg_axis_source #(
    parameter [47:0] LOCAL_MAC = 48'h02_00_00_00_00_25,
    parameter [47:0] HOST_MAC  = 48'hFF_FF_FF_FF_FF_FF,
    parameter [31:0] LOCAL_IP  = 32'hA9_FE_1A_5F,
    parameter [31:0] HOST_IP   = 32'hA9_FE_1A_5E,
    parameter [15:0] UDP_PORT  = 16'd5002,
    parameter [15:0] WIDTH     = 16'd1920,
    parameter [15:0] HEIGHT    = 16'd1080
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        packet_req,
    input  wire        packet_bank,
    input  wire [10:0] packet_len,
    input  wire [31:0] packet_frame_id,
    input  wire [15:0] packet_sequence,
    input  wire [1:0]  packet_flags,
    input  wire [1:0]  algorithm_mode,
    input  wire [7:0]  algorithm_sequence,
    input  wire [2:0]  command_accepted_count,
    input  wire [2:0]  command_rejected_count,
    output reg         packet_take,
    output reg         packet_done,
    output wire        read_bank,
    output wire [9:0]  read_addr,
    input  wire [15:0] read_data,
    output reg  [63:0] tx_axis_tdata,
    output reg  [7:0]  tx_axis_tkeep,
    output reg         tx_axis_tvalid,
    output reg         tx_axis_tlast,
    input  wire        tx_axis_tready
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_HEADER = 2'd1;
    localparam [1:0] ST_PAYLOAD_READ = 2'd2;
    localparam [1:0] ST_PAYLOAD_SEND = 2'd3;

    reg [1:0] state;
    reg [2:0] header_beat, read_phase;
    reg [9:0] payload_word_base;
    reg [15:0] payload_word0, payload_word1, payload_word2;
    reg [63:0] payload_beat;
    reg active_bank;
    reg [10:0] active_len;
    reg [31:0] active_frame_id;
    reg [15:0] active_sequence;
    reg [1:0] active_flags;
    reg [1:0] active_algorithm_mode;
    reg [7:0] active_algorithm_sequence;
    reg [15:0] packet_id, active_packet_id;
    reg [15:0] active_ip_total_len, active_udp_total_len;
    reg [15:0] active_ip_checksum;

    assign read_bank = active_bank;
    assign read_addr = payload_word_base +
                       ((read_phase < 3'd4) ? read_phase[1:0] : 2'd3);

    function [7:0] mac_byte;
        input [47:0] mac;
        input [2:0] index;
        begin
            case (index)
                0: mac_byte = mac[47:40]; 1: mac_byte = mac[39:32];
                2: mac_byte = mac[31:24]; 3: mac_byte = mac[23:16];
                4: mac_byte = mac[15:8]; default: mac_byte = mac[7:0];
            endcase
        end
    endfunction

    function [15:0] ipv4_checksum;
        input [15:0] total_len;
        input [15:0] identification;
        reg [31:0] sum;
        reg [16:0] fold;
        begin
            sum = 32'h00004500 + total_len + identification +
                  32'h00004000 + 32'h00004011 +
                  {16'd0, LOCAL_IP[31:16]} + {16'd0, LOCAL_IP[15:0]} +
                  {16'd0, HOST_IP[31:16]} + {16'd0, HOST_IP[15:0]};
            fold = sum[15:0] + sum[31:16];
            fold = fold[15:0] + fold[16];
            ipv4_checksum = ~fold[15:0];
        end
    endfunction

    function [7:0] header_byte;
        input [6:0] index;
        begin
            header_byte = 8'h00;
            if (index < 7'd6)
                header_byte = mac_byte(HOST_MAC, index[2:0]);
            else if (index < 7'd12)
                header_byte = mac_byte(LOCAL_MAC, index[2:0] - 3'd6);
            else case (index)
                12: header_byte=8'h08; 13: header_byte=8'h00;
                14: header_byte=8'h45; 15: header_byte=8'h00;
                16: header_byte=active_ip_total_len[15:8];
                17: header_byte=active_ip_total_len[7:0];
                18: header_byte=active_packet_id[15:8];
                19: header_byte=active_packet_id[7:0];
                20: header_byte=8'h40; 21: header_byte=8'h00;
                22: header_byte=8'h40; 23: header_byte=8'h11;
                24: header_byte=active_ip_checksum[15:8];
                25: header_byte=active_ip_checksum[7:0];
                26: header_byte=LOCAL_IP[31:24]; 27: header_byte=LOCAL_IP[23:16];
                28: header_byte=LOCAL_IP[15:8]; 29: header_byte=LOCAL_IP[7:0];
                30: header_byte=HOST_IP[31:24]; 31: header_byte=HOST_IP[23:16];
                32: header_byte=HOST_IP[15:8]; 33: header_byte=HOST_IP[7:0];
                34: header_byte=UDP_PORT[15:8]; 35: header_byte=UDP_PORT[7:0];
                36: header_byte=UDP_PORT[15:8]; 37: header_byte=UDP_PORT[7:0];
                38: header_byte=active_udp_total_len[15:8];
                39: header_byte=active_udp_total_len[7:0];
                40,41: header_byte=8'h00;
                42: header_byte="O"; 43: header_byte="V";
                44: header_byte="J"; 45: header_byte="2";
                46: header_byte=WIDTH[15:8]; 47: header_byte=WIDTH[7:0];
                48: header_byte=HEIGHT[15:8]; 49: header_byte=HEIGHT[7:0];
                50: header_byte=8'd1;
                51: header_byte=8'd2;
                52: header_byte={5'b0,active_len[10:8]};
                53: header_byte=active_len[7:0];
                54: header_byte=active_frame_id[31:24];
                55: header_byte=active_frame_id[23:16];
                56: header_byte=active_frame_id[15:8];
                57: header_byte=active_frame_id[7:0];
                58: header_byte=active_sequence[15:8];
                59: header_byte=active_sequence[7:0];
                60: header_byte={6'b0,active_flags};
                // Reserved OVJ2 bytes carry the SCCB-applied sensor ISP mode.
                // Preserve the applied mode in bits 1:0 while returning small
                // rolling RX parser counters for control-path diagnosis.
                61: header_byte={command_rejected_count,
                                  command_accepted_count,
                                  active_algorithm_mode};
                62: header_byte=active_algorithm_sequence;
                63: header_byte=8'hA5;
                default: header_byte=8'h00;
            endcase
        end
    endfunction

    function [63:0] header_word;
        input [2:0] beat;
        integer lane;
        reg [6:0] byte_index;
        begin
            header_word = 64'd0;
            for (lane=0; lane<8; lane=lane+1) begin
                byte_index = {beat,3'b000} + lane;
                header_word[lane*8 +: 8] = header_byte(byte_index);
            end
        end
    endfunction

    function [7:0] final_keep;
        input [3:0] valid_bytes;
        begin
            case (valid_bytes)
                1: final_keep=8'h01; 2: final_keep=8'h03;
                3: final_keep=8'h07; 4: final_keep=8'h0f;
                5: final_keep=8'h1f; 6: final_keep=8'h3f;
                7: final_keep=8'h7f; default: final_keep=8'hff;
            endcase
        end
    endfunction

    wire [11:0] payload_byte_base = {payload_word_base,1'b0};
    wire last_payload_beat = (payload_byte_base + 12'd8 >= active_len);
    wire [3:0] remaining_bytes = active_len - payload_byte_base;

    always @* begin
        tx_axis_tdata = 64'd0;
        tx_axis_tkeep = 8'h00;
        tx_axis_tvalid = 1'b0;
        tx_axis_tlast = 1'b0;
        if (state == ST_HEADER) begin
            tx_axis_tdata = header_word(header_beat);
            tx_axis_tkeep = 8'hff;
            tx_axis_tvalid = 1'b1;
        end else if (state == ST_PAYLOAD_SEND) begin
            tx_axis_tdata = payload_beat;
            tx_axis_tkeep = last_payload_beat ? final_keep(remaining_bytes) : 8'hff;
            tx_axis_tvalid = 1'b1;
            tx_axis_tlast = last_payload_beat;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state<=ST_IDLE; header_beat<=0; read_phase<=0;
            payload_word_base<=0; payload_word0<=0; payload_word1<=0;
            payload_word2<=0; payload_beat<=0; active_bank<=0;
            active_len<=0; active_frame_id<=0; active_sequence<=0;
            active_flags<=0; packet_id<=0; active_packet_id<=0;
            active_algorithm_mode<=0; active_algorithm_sequence<=0;
            active_ip_total_len<=0; active_udp_total_len<=0;
            active_ip_checksum<=0; packet_take<=0; packet_done<=0;
        end else begin
            packet_take <= 1'b0;
            packet_done <= 1'b0;
            case (state)
                ST_IDLE: if (packet_req) begin
                    active_bank <= packet_bank;
                    active_len <= packet_len;
                    active_frame_id <= packet_frame_id;
                    active_sequence <= packet_sequence;
                    active_flags <= packet_flags;
                    active_algorithm_mode <= algorithm_mode;
                    active_algorithm_sequence <= algorithm_sequence;
                    packet_id <= packet_id + 1'b1;
                    active_packet_id <= packet_id + 1'b1;
                    active_ip_total_len <= 16'd50 + packet_len;
                    active_udp_total_len <= 16'd30 + packet_len;
                    active_ip_checksum <= ipv4_checksum(16'd50+packet_len,
                                                        packet_id+1'b1);
                    header_beat <= 0;
                    packet_take <= 1'b1;
                    state <= ST_HEADER;
                end
                ST_HEADER: if (tx_axis_tready) begin
                    if (header_beat == 7) begin
                        payload_word_base <= 0;
                        read_phase <= 0;
                        state <= ST_PAYLOAD_READ;
                    end else header_beat <= header_beat + 1'b1;
                end
                ST_PAYLOAD_READ: case (read_phase)
                    0: read_phase <= 1;
                    1: begin payload_word0<={read_data[7:0],read_data[15:8]}; read_phase<=2; end
                    2: begin payload_word1<={read_data[7:0],read_data[15:8]}; read_phase<=3; end
                    3: begin payload_word2<={read_data[7:0],read_data[15:8]}; read_phase<=4; end
                    default: begin
                        payload_beat <= {{read_data[7:0],read_data[15:8]},
                                         payload_word2,payload_word1,payload_word0};
                        state <= ST_PAYLOAD_SEND;
                    end
                endcase
                ST_PAYLOAD_SEND: if (tx_axis_tready) begin
                    if (last_payload_beat) begin
                        packet_done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        payload_word_base <= payload_word_base + 4;
                        read_phase <= 0;
                        state <= ST_PAYLOAD_READ;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
