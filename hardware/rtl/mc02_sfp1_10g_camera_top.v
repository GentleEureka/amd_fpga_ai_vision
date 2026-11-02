`timescale 1ns / 1ps
`default_nettype none

// 1080p OV5640 RGB565 capture with runtime FPGA color, grayscale, binary and inversion.
module mc02_sfp1_10g_camera_top (
    input  wire       sys_clk_p,
    input  wire       sys_clk_n,
    input  wire       gtrefclk_p,
    input  wire       gtrefclk_n,
    output wire       sfp1_txp,
    output wire       sfp1_txn,
    input  wire       sfp1_rxp,
    input  wire       sfp1_rxn,
    output wire       sfp1_tx_disable,
    input  wire [7:0] cam_d,
    input  wire       cam_pclk,
    input  wire       cam_href,
    input  wire       cam_vsync,
    inout  wire       cam_sda,
    inout  wire       cam_scl,
    output wire       cam_rst_n,
    output wire       cam_pwdn,
    input  wire [3:0] algorithm_button,
    output reg  [2:0] algorithm_led
);

    wire clk_ctrl;
    wire clk_ctrl_locked;
    wire clk156;
    wire reset_net;
    wire link_up;
    wire [2:0] mac_status;
    wire xgmii_data_active;

    reg [7:0] reset_count = 8'h00;
    wire reset_power_on = !clk_ctrl_locked || (reset_count != 8'hFF);

    always @(posedge clk_ctrl) begin
        if (!clk_ctrl_locked)
            reset_count <= 8'h00;
        else if (reset_count != 8'hFF)
            reset_count <= reset_count + 1'b1;
    end

    assign sfp1_tx_disable = 1'b0;

    clkgen_300m_to_100m clock_gen_i (
        .clk_out1(clk_ctrl),
        .reset(1'b0),
        .locked(clk_ctrl_locked),
        .clk_in1_p(sys_clk_p),
        .clk_in1_n(sys_clk_n)
    );

    wire [63:0] rx_axis_tdata;
    wire [7:0]  rx_axis_tkeep;
    wire        rx_axis_tvalid;
    wire        rx_axis_tlast;
    wire [63:0] tx_axis_tdata;
    wire [7:0]  tx_axis_tkeep;
    wire        tx_axis_tvalid;
    wire        tx_axis_tlast;
    wire        tx_axis_tready;

    ten_gig_eth_endpoint ten_gig_i (
        .reset(reset_power_on),
        .dclk(clk_ctrl),
        .gtrefclk_p(gtrefclk_p),
        .gtrefclk_n(gtrefclk_n),
        .net_clk(clk156),
        .net_reset(reset_net),
        .link_up(link_up),
        .mac_status(mac_status),
        .xgmii_data_active(xgmii_data_active),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tlast(rx_axis_tlast),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tkeep(tx_axis_tkeep),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tready(tx_axis_tready),
        .txp(sfp1_txp),
        .txn(sfp1_txn),
        .rxp(sfp1_rxp),
        .rxn(sfp1_rxn)
    );

    wire [1:0] host_algorithm_mode;
    wire [7:0] host_algorithm_threshold;
    wire [7:0] host_algorithm_sequence;
    wire host_algorithm_toggle;
    wire [1:0] algorithm_mode_request;
    wire [7:0] algorithm_threshold_request;
    wire [7:0] algorithm_sequence_request;
    wire algorithm_update_toggle;
    wire [31:0] algorithm_command_accepted_count;
    wire [31:0] algorithm_command_rejected_count;
    wire [1:0] algorithm_mode_applied;
    wire [7:0] algorithm_threshold_applied;
    wire [7:0] algorithm_sequence_applied;

    fpga_algorithm_control_rx algorithm_command_rx_i (
        .clk(clk156),
        .rst(reset_net),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(rx_axis_tkeep),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tlast(rx_axis_tlast),
        .requested_mode(host_algorithm_mode),
        .requested_threshold(host_algorithm_threshold),
        .requested_sequence(host_algorithm_sequence),
        .update_toggle(host_algorithm_toggle),
        .accepted_count(algorithm_command_accepted_count),
        .rejected_count(algorithm_command_rejected_count)
    );

    algorithm_mode_arbiter algorithm_mode_arbiter_i (
        .clk(clk156),
        .rst(reset_net),
        .buttons(algorithm_button),
        .host_mode(host_algorithm_mode),
        .host_threshold(host_algorithm_threshold),
        .host_sequence(host_algorithm_sequence),
        .host_toggle(host_algorithm_toggle),
        .requested_mode(algorithm_mode_request),
        .requested_threshold(algorithm_threshold_request),
        .requested_sequence(algorithm_sequence_request),
        .update_toggle(algorithm_update_toggle)
    );

    // MC02 exposes three independent user LEDs for four modes.  Use one-hot
    // indication for the first three modes and all LEDs for inversion.
    always @* begin
        case (algorithm_mode_applied)
            2'd0: algorithm_led = 3'b001; // color: LED0
            2'd1: algorithm_led = 3'b010; // gray: LED1
            2'd2: algorithm_led = 3'b100; // binary: LED2
            default: algorithm_led = 3'b111; // invert: LED0+LED1+LED2
        endcase
    end

    wire [15:0] camera_id;
    wire camera_nack_error;
    wire camera_init_done;
    wire camera_init_error;
    wire [15:0] camera_pixel_data;
    wire camera_pixel_valid;
    wire camera_frame_sync;
    wire [15:0] camera_line_pixels;
    wire [15:0] camera_frame_lines;
    wire [15:0] sensor_diag_value;
    wire [5:0] sensor_diag_tag;
    wire camera_fifo_overflow;
    reg [5:0] sensor_diag_tag_ctrl_d;
    reg sensor_diag_toggle_ctrl;
    (* ASYNC_REG = "TRUE" *) reg sensor_diag_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg sensor_diag_toggle_net;
    reg sensor_diag_toggle_net_d;
    reg [15:0] sensor_diag_value_net;
    reg [5:0] sensor_diag_tag_net;

    // Bundled-data CDC: SCCB readback changes only once per register pair.
    // Transfer it with a toggle so the 156 MHz packetizer never combines
    // high/low bytes or a value/tag from different camera-clock cycles.
    always @(posedge clk_ctrl) begin
        if (reset_power_on) begin
            sensor_diag_tag_ctrl_d <= 6'd0;
            sensor_diag_toggle_ctrl <= 1'b0;
        end else if (sensor_diag_tag != sensor_diag_tag_ctrl_d) begin
            sensor_diag_tag_ctrl_d <= sensor_diag_tag;
            sensor_diag_toggle_ctrl <= ~sensor_diag_toggle_ctrl;
        end
    end

    always @(posedge clk156) begin
        if (reset_net) begin
            sensor_diag_toggle_meta <= 1'b0;
            sensor_diag_toggle_net <= 1'b0;
            sensor_diag_toggle_net_d <= 1'b0;
            sensor_diag_value_net <= 16'd0;
            sensor_diag_tag_net <= 6'd0;
        end else begin
            sensor_diag_toggle_meta <= sensor_diag_toggle_ctrl;
            sensor_diag_toggle_net <= sensor_diag_toggle_meta;
            sensor_diag_toggle_net_d <= sensor_diag_toggle_net;
            if (sensor_diag_toggle_net != sensor_diag_toggle_net_d) begin
                sensor_diag_value_net <= sensor_diag_value;
                sensor_diag_tag_net <= sensor_diag_tag;
            end
        end
    end
    // Transfer frame-stable active dimensions with a bundled-data toggle.
    // Directly sampling these camera-clock counters at 156 MHz can combine
    // bits from adjacent counts and produce invalid width/height metadata.
    reg [15:0] camera_frame_width_hold;
    reg [15:0] camera_frame_height_hold;
    reg camera_frame_metrics_toggle_cam;
    (* ASYNC_REG = "TRUE" *) reg camera_frame_metrics_toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg camera_frame_metrics_toggle_net;
    reg camera_frame_metrics_toggle_net_d;
    reg [15:0] camera_frame_width_net;
    reg [15:0] camera_frame_height_net;

    always @(posedge cam_pclk) begin
        if (camera_buffer_reset) begin
            camera_frame_width_hold <= 16'd0;
            camera_frame_height_hold <= 16'd0;
            camera_frame_metrics_toggle_cam <= 1'b0;
        end else if (camera_frame_sync) begin
            camera_frame_width_hold <= camera_line_pixels;
            camera_frame_height_hold <= camera_frame_lines;
            camera_frame_metrics_toggle_cam <= ~camera_frame_metrics_toggle_cam;
        end
    end

    always @(posedge clk156) begin
        if (reset_net) begin
            camera_frame_metrics_toggle_meta <= 1'b0;
            camera_frame_metrics_toggle_net <= 1'b0;
            camera_frame_metrics_toggle_net_d <= 1'b0;
            camera_frame_width_net <= 16'd0;
            camera_frame_height_net <= 16'd0;
        end else begin
            camera_frame_metrics_toggle_meta <= camera_frame_metrics_toggle_cam;
            camera_frame_metrics_toggle_net <= camera_frame_metrics_toggle_meta;
            camera_frame_metrics_toggle_net_d <= camera_frame_metrics_toggle_net;
            if (camera_frame_metrics_toggle_net != camera_frame_metrics_toggle_net_d) begin
                camera_frame_width_net <= camera_frame_width_hold;
                camera_frame_height_net <= camera_frame_height_hold;
            end
        end
    end

    // Use the board-proven raw RGB565 receiver.  No JPEG/effect emulation is
    // present in this path: all four modes are implemented in FPGA logic.
    ov5640_recoverable_frontend camera_frontend_i (
        .clk_100m(clk_ctrl),
        .rst(reset_power_on),
        .cam_rst_n(cam_rst_n),
        .cam_pwdn(cam_pwdn),
        .cam_sda(cam_sda),
        .cam_scl(cam_scl),
        .cam_pclk(cam_pclk),
        .cam_vsync(cam_vsync),
        .cam_href(cam_href),
        .cam_data(cam_d),
        .camera_id(camera_id),
        .sccb_nack_error(camera_nack_error),
        .cam_init_done(camera_init_done),
        .cam_init_error(camera_init_error),
        .pixel_data(camera_pixel_data),
        .pixel_valid(camera_pixel_valid),
        .frame_sync(camera_frame_sync),
        .line_pixel_count(camera_line_pixels),
        .frame_line_count(camera_frame_lines),
        .sensor_diag_value(sensor_diag_value),
        .sensor_diag_tag(sensor_diag_tag)
    );

    wire camera_buffer_reset = !camera_init_done;

    wire [15:0] processed_pixel_data;
    wire processed_pixel_valid;
    wire processed_frame_sync;
    fpga_rgb565_processor pixel_processor_i (
        .control_clk(clk156), .control_rst(reset_net),
        .requested_mode(algorithm_mode_request),
        .requested_threshold(algorithm_threshold_request),
        .requested_sequence(algorithm_sequence_request),
        .update_toggle(algorithm_update_toggle),
        .pixel_clk(cam_pclk), .pixel_rst(camera_buffer_reset),
        .pixel_in(camera_pixel_data),
        .pixel_valid_in(camera_pixel_valid),
        .frame_sync_in(camera_frame_sync),
        .pixel_out(processed_pixel_data),
        .pixel_valid_out(processed_pixel_valid),
        .frame_sync_out(processed_frame_sync),
        .applied_mode_control(algorithm_mode_applied),
        .applied_threshold_control(algorithm_threshold_applied),
        .applied_sequence_control(algorithm_sequence_applied)
    );

    wire video_packet_req;
    wire [2:0] video_packet_bank;
    wire [10:0] video_packet_len;
    wire [31:0] video_packet_frame_id;
    wire video_packet_take;
    wire video_packet_done;
    wire [2:0] video_read_bank;
    wire [9:0] video_read_addr;
    wire [15:0] video_read_data;

    camera_packet_fifo #(
        .FRAME_PIXELS(1920*1080),
        .WORDS_PER_PACKET(696)
    ) camera_buffer_i (
        .cam_clk(cam_pclk),
        .cam_rst(camera_buffer_reset),
        .frame_sync(processed_frame_sync),
        .pixel_data(processed_pixel_data),
        .pixel_valid(processed_pixel_valid),
        .overflow(camera_fifo_overflow),
        .net_clk(clk156),
        .net_rst(reset_net),
        .packet_req(video_packet_req),
        .packet_bank(video_packet_bank),
        .packet_len(video_packet_len),
        .packet_frame_id(video_packet_frame_id),
        .packet_take(video_packet_take),
        .packet_done(video_packet_done),
        .read_bank(video_read_bank),
        .read_addr(video_read_addr),
        .read_data(video_read_data)
    );

    udp_video_axis_source #(
        .LOCAL_MAC(48'h02_00_00_00_00_25),
        .HOST_MAC(48'hFF_FF_FF_FF_FF_FF),
        .LOCAL_IP(32'hA9_FE_1A_5F),
        .HOST_IP(32'hA9_FE_1A_5E),
        .UDP_PORT(16'd5002),
        .WIDTH(16'd1920),
        .HEIGHT(16'd1080)
    ) packetizer_i (
        .clk(clk156),
        .rst(reset_net),
        .packet_req(video_packet_req),
        .packet_bank(video_packet_bank),
        .packet_len(video_packet_len),
        .packet_frame_id(video_packet_frame_id),
        .frame_width(camera_frame_width_net),
        .frame_height(camera_frame_height_net),
        .sensor_diag_value(sensor_diag_value_net),
        .sensor_diag_tag(sensor_diag_tag_net),
        .sensor_height_valid(camera_init_done),
        .camera_fifo_overflow(camera_fifo_overflow),
        .algorithm_mode(algorithm_mode_applied),
        .algorithm_threshold(algorithm_threshold_applied),
        .algorithm_sequence(algorithm_sequence_applied),
        .packet_take(video_packet_take),
        .packet_done(video_packet_done),
        .read_bank(video_read_bank),
        .read_addr(video_read_addr),
        .read_data(video_read_data),
        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tkeep(tx_axis_tkeep),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tready(tx_axis_tready)
    );

`ifdef INCLUDE_V2_ILA
    ila_camera_v2 camera_diag_i (
        .clk(clk_ctrl),
        .probe0(camera_id),
        .probe1(camera_init_done),
        .probe2(camera_init_error | camera_nack_error),
        .probe3({link_up, reset_net, tx_axis_tready, tx_axis_tvalid,
                 video_packet_req, video_packet_take,
                 xgmii_data_active, camera_pixel_valid}),
        .probe4(mac_status[0]),
        .probe5(mac_status[1]),
        .probe6(mac_status[2]),
        .probe7(tx_axis_tvalid)
    );
`endif

    wire _unused_status = ^{camera_line_pixels, camera_frame_lines,
                            algorithm_command_accepted_count,
                            algorithm_command_rejected_count};

endmodule

`default_nettype wire
