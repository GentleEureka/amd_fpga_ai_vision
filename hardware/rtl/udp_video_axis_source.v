`timescale 1ns / 1ps
`default_nettype none

// Packs one camera-buffer chunk into an Ethernet/IPv4/UDP frame for the
// Xilinx 10G MAC AXI64 client interface.  The 64-byte protocol header and
// both camera payload sizes (1392/528 bytes) are naturally eight-byte aligned.
module udp_video_axis_source #(
    parameter [47:0] LOCAL_MAC = 48'h02_00_00_00_00_25,
    parameter [47:0] HOST_MAC  = 48'hFF_FF_FF_FF_FF_FF,
    parameter [31:0] LOCAL_IP  = 32'hA9_FE_1A_5F,
    parameter [31:0] HOST_IP   = 32'hA9_FE_1A_5E,
    parameter [15:0] UDP_PORT  = 16'd5002,
    parameter [15:0] WIDTH     = 16'd640,
    parameter [15:0] HEIGHT    = 16'd480
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        packet_req,
    input  wire [2:0]  packet_bank,
    input  wire [10:0] packet_len,
    input  wire [31:0] packet_frame_id,
    input  wire [15:0] frame_width,
    input  wire [15:0] frame_height,
    input  wire [15:0] sensor_diag_value,
    input  wire [5:0]  sensor_diag_tag,
    input  wire        sensor_height_valid,
    input  wire        camera_fifo_overflow,
    input  wire [1:0]  algorithm_mode,
    input  wire [7:0]  algorithm_threshold,
    input  wire [7:0]  algorithm_sequence,
    output reg         packet_take,
    output reg         packet_done,

    output wire [2:0]  read_bank,
    output wire [9:0]  read_addr,
    input  wire [15:0] read_data,

    output reg  [63:0] tx_axis_tdata,
    output reg  [7:0]  tx_axis_tkeep,
    output reg         tx_axis_tvalid,
    output reg         tx_axis_tlast,
    input  wire        tx_axis_tready
);

    localparam [1:0] ST_IDLE         = 2'd0;
    localparam [1:0] ST_HEADER       = 2'd1;
    localparam [1:0] ST_PAYLOAD_READ = 2'd2;
    localparam [1:0] ST_PAYLOAD_SEND = 2'd3;

    reg [1:0] state;
    reg [2:0] header_beat;
    reg [2:0] read_phase;
    reg [9:0] payload_word_base;
    reg [15:0] payload_word0;
    reg [15:0] payload_word1;
    reg [15:0] payload_word2;
    reg [63:0] payload_beat;

    reg [2:0]  active_bank;
    reg [10:0] active_len;
    reg [31:0] active_frame_id;
    reg [15:0] active_width;
    reg [15:0] active_height;
    reg [15:0] active_sensor_diag_value;
    reg [5:0] active_sensor_diag_tag;
    reg active_sensor_height_valid;
    reg active_camera_fifo_overflow;
    reg [15:0] packet_id;
    reg [15:0] active_packet_id;
    reg [15:0] active_ip_total_len;
    reg [15:0] active_udp_total_len;
    reg [15:0] active_ip_checksum;
    reg [1:0]  active_algorithm_mode;
    reg [7:0]  active_algorithm_threshold;
    reg [7:0]  active_algorithm_sequence;

    assign read_bank = active_bank;
    assign read_addr = payload_word_base +
                       ((read_phase < 3'd4) ? read_phase[1:0] : 2'd3);

    function [7:0] mac_byte;
        input [47:0] mac;
        input [2:0] index;
        begin
            case (index)
                3'd0: mac_byte = mac[47:40];
                3'd1: mac_byte = mac[39:32];
                3'd2: mac_byte = mac[31:24];
                3'd3: mac_byte = mac[23:16];
                3'd4: mac_byte = mac[15:8];
                default: mac_byte = mac[7:0];
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
            else begin
                case (index)
                    7'd12: header_byte = 8'h08;
                    7'd13: header_byte = 8'h00;
                    7'd14: header_byte = 8'h45;
                    7'd15: header_byte = 8'h00;
                    7'd16: header_byte = active_ip_total_len[15:8];
                    7'd17: header_byte = active_ip_total_len[7:0];
                    7'd18: header_byte = active_packet_id[15:8];
                    7'd19: header_byte = active_packet_id[7:0];
                    7'd20: header_byte = 8'h40;
                    7'd21: header_byte = 8'h00;
                    7'd22: header_byte = 8'h40;
                    7'd23: header_byte = 8'h11;
                    7'd24: header_byte = active_ip_checksum[15:8];
                    7'd25: header_byte = active_ip_checksum[7:0];
                    7'd26: header_byte = LOCAL_IP[31:24];
                    7'd27: header_byte = LOCAL_IP[23:16];
                    7'd28: header_byte = LOCAL_IP[15:8];
                    7'd29: header_byte = LOCAL_IP[7:0];
                    7'd30: header_byte = HOST_IP[31:24];
                    7'd31: header_byte = HOST_IP[23:16];
                    7'd32: header_byte = HOST_IP[15:8];
                    7'd33: header_byte = HOST_IP[7:0];
                    7'd34: header_byte = UDP_PORT[15:8];
                    7'd35: header_byte = UDP_PORT[7:0];
                    7'd36: header_byte = UDP_PORT[15:8];
                    7'd37: header_byte = UDP_PORT[7:0];
                    7'd38: header_byte = active_udp_total_len[15:8];
                    7'd39: header_byte = active_udp_total_len[7:0];
                    7'd40, 7'd41: header_byte = 8'h00;
                    7'd42: header_byte = "O";
                    7'd43: header_byte = "V";
                    7'd44: header_byte = "5";
                    7'd45: header_byte = "6";
                    7'd46: header_byte = active_width[15:8];
                    7'd47: header_byte = active_width[7:0];
                    7'd48: header_byte = active_height[15:8];
                    7'd49: header_byte = active_height[7:0];
                    7'd50: header_byte = 8'd2;
                    7'd51: header_byte = 8'd1;
                    7'd52: header_byte = {5'b00000, active_len[10:8]};
                    7'd53: header_byte = active_len[7:0];
                    7'd54: header_byte = active_frame_id[31:24];
                    7'd55: header_byte = active_frame_id[23:16];
                    7'd56: header_byte = active_frame_id[15:8];
                    7'd57: header_byte = active_frame_id[7:0];
                    7'd58: header_byte = {6'd0, active_algorithm_mode};
                    7'd59: header_byte = active_algorithm_threshold;
                    7'd60: header_byte = active_algorithm_sequence;
                    7'd61: header_byte = active_sensor_diag_value[15:8];
                    7'd62: header_byte = active_sensor_diag_value[7:0];
                    7'd63: header_byte = {active_camera_fifo_overflow,
                                           active_sensor_diag_tag,
                                           active_sensor_height_valid};
                    default: header_byte = 8'h00;
                endcase
            end
        end
    endfunction

    function [63:0] header_word;
        input [2:0] beat;
        integer lane;
        reg [6:0] byte_index;
        begin
            header_word = 64'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                byte_index = {beat, 3'b000} + lane;
                header_word[lane*8 +: 8] = header_byte(byte_index);
            end
        end
    endfunction

    always @* begin
        tx_axis_tdata = 64'd0;
        tx_axis_tkeep = 8'h00;
        tx_axis_tvalid = 1'b0;
        tx_axis_tlast = 1'b0;

        if (state == ST_HEADER) begin
            tx_axis_tdata = header_word(header_beat);
            tx_axis_tkeep = 8'hFF;
            tx_axis_tvalid = 1'b1;
        end else if (state == ST_PAYLOAD_SEND) begin
            tx_axis_tdata = payload_beat;
            tx_axis_tkeep = 8'hFF;
            tx_axis_tvalid = 1'b1;
            tx_axis_tlast = ({payload_word_base, 1'b0} + 11'd8 >= active_len);
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            header_beat <= 3'd0;
            read_phase <= 3'd0;
            payload_word_base <= 10'd0;
            payload_word0 <= 16'd0;
            payload_word1 <= 16'd0;
            payload_word2 <= 16'd0;
            payload_beat <= 64'd0;
            active_bank <= 3'd0;
            active_len <= 11'd0;
            active_frame_id <= 32'd0;
            active_width <= WIDTH;
            active_height <= HEIGHT;
            active_sensor_diag_value <= 16'd0;
            active_sensor_diag_tag <= 6'd0;
            active_sensor_height_valid <= 1'b0;
            active_camera_fifo_overflow <= 1'b0;
            packet_id <= 16'd0;
            active_packet_id <= 16'd0;
            active_ip_total_len <= 16'd0;
            active_udp_total_len <= 16'd0;
            active_ip_checksum <= 16'd0;
            active_algorithm_mode <= 2'd0;
            active_algorithm_threshold <= 8'd128;
            active_algorithm_sequence <= 8'd0;
            packet_take <= 1'b0;
            packet_done <= 1'b0;
        end else begin
            packet_take <= 1'b0;
            packet_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (packet_req) begin
                        active_bank <= packet_bank;
                        active_len <= packet_len;
                        active_frame_id <= packet_frame_id;
                        // The stream is configured for a fixed sensor output
                        // size.  Use those configured dimensions in every
                        // packet header instead of the unreliable line meter.
                        active_width <= WIDTH;
                        active_height <= HEIGHT;
                        active_sensor_diag_value <= sensor_diag_value;
                        active_sensor_diag_tag <= sensor_diag_tag;
                        active_sensor_height_valid <= sensor_height_valid;
                        active_camera_fifo_overflow <= camera_fifo_overflow;
                        active_algorithm_mode <= algorithm_mode;
                        active_algorithm_threshold <= algorithm_threshold;
                        active_algorithm_sequence <= algorithm_sequence;
                        packet_id <= packet_id + 1'b1;
                        active_packet_id <= packet_id + 1'b1;
                        active_ip_total_len <= 16'd50 + packet_len;
                        active_udp_total_len <= 16'd30 + packet_len;
                        active_ip_checksum <= ipv4_checksum(
                            16'd50 + packet_len,
                            packet_id + 1'b1
                        );
                        header_beat <= 3'd0;
                        packet_take <= 1'b1;
                        state <= ST_HEADER;
                    end
                end

                ST_HEADER: begin
                    if (tx_axis_tready) begin
                        if (header_beat == 3'd7) begin
                            payload_word_base <= 10'd0;
                            read_phase <= 3'd0;
                            state <= ST_PAYLOAD_READ;
                        end else begin
                            header_beat <= header_beat + 1'b1;
                        end
                    end
                end

                ST_PAYLOAD_READ: begin
                    case (read_phase)
                        3'd0: read_phase <= 3'd1;
                        3'd1: begin
                            payload_word0 <= {read_data[7:0], read_data[15:8]};
                            read_phase <= 3'd2;
                        end
                        3'd2: begin
                            payload_word1 <= {read_data[7:0], read_data[15:8]};
                            read_phase <= 3'd3;
                        end
                        3'd3: begin
                            payload_word2 <= {read_data[7:0], read_data[15:8]};
                            read_phase <= 3'd4;
                        end
                        default: begin
                            payload_beat <= {
                                {read_data[7:0], read_data[15:8]},
                                payload_word2,
                                payload_word1,
                                payload_word0
                            };
                            state <= ST_PAYLOAD_SEND;
                        end
                    endcase
                end

                ST_PAYLOAD_SEND: begin
                    if (tx_axis_tready) begin
                        if ({payload_word_base, 1'b0} + 11'd8 >= active_len) begin
                            packet_done <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            payload_word_base <= payload_word_base + 3'd4;
                            read_phase <= 3'd0;
                            state <= ST_PAYLOAD_READ;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
