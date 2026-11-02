`timescale 1ns / 1ps
`default_nettype none

// Recoverable OV5640 bring-up followed by a 1920x1080@30 JPEG override.
// The full, board-proven RGB565 table first initializes the analogue/ISP
// blocks; the short override then changes only timing and JPEG/DVP controls.
module ov5640_jpeg_frontend (
    input  wire        clk_100m,
    input  wire        rst,
    output wire        cam_rst_n,
    output wire        cam_pwdn,
    inout  wire        cam_sda,
    inout  wire        cam_scl,
    input  wire        cam_pclk,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_data,
    output wire [15:0] camera_id,
    output wire        sccb_nack_error,
    output wire        cam_init_done,
    output wire        cam_init_error,
    output reg  [7:0]  byte_data,
    output reg         byte_valid,
    output reg         frame_sync,
    output reg  [15:0] href_byte_count,
    output reg  [15:0] frame_href_count,
    input  wire [1:0]  algorithm_mode_request,
    input  wire [7:0]  algorithm_sequence_request,
    input  wire        algorithm_update_toggle,
    output reg  [1:0]  algorithm_mode_applied,
    output reg  [7:0]  algorithm_sequence_applied
);

    // Hold the sensor in a deterministic power-down/reset sequence long
    // enough for both cold power-up and FPGA-only reconfiguration.  The
    // previous 10/30/70 ms sequence could leave an already-powered OV5640
    // responsive on SCCB but not producing DVP frames after a Flash boot.
    localparam [26:0] PWDN_RELEASE_COUNT = 27'd10_000_000;
    localparam [26:0] RESET_RELEASE_COUNT = 27'd30_000_000;
    localparam [26:0] SCCB_START_COUNT    = 27'd70_000_000;

    reg [26:0] power_count;
    reg retry_request;
    wire power_ready = (power_count >= SCCB_START_COUNT);

    assign cam_pwdn  = (power_count < PWDN_RELEASE_COUNT);
    assign cam_rst_n = (power_count >= RESET_RELEASE_COUNT);

    always @(posedge clk_100m) begin
        if (rst || retry_request)
            power_count <= 27'd0;
        else if (!power_ready)
            power_count <= power_count + 1'b1;
    end

    wire sccb_scl_in = cam_scl;
    wire sccb_sda_in = cam_sda;
    wire read_scl_low, read_sda_low;
    wire write_scl_low, write_sda_low;
    assign cam_scl = (read_scl_low | write_scl_low) ? 1'b0 : 1'bz;
    assign cam_sda = (read_sda_low | write_sda_low) ? 1'b0 : 1'bz;

    reg sccb_start;
    reg [15:0] sccb_reg_addr;
    wire [7:0] sccb_read_data;
    wire sccb_busy, sccb_done, sccb_nack;

    sccb_read_reg_open sccb_read_i (
        .clk(clk_100m), .rst_n(power_ready), .start(sccb_start),
        .reg_addr(sccb_reg_addr), .rd_data(sccb_read_data),
        .busy(sccb_busy), .done(sccb_done), .nack_error(sccb_nack),
        .scl_in(sccb_scl_in), .sda_in(sccb_sda_in),
        .scl_drive_low(read_scl_low), .sda_drive_low(read_sda_low)
    );

    localparam [2:0] VERIFY_WAIT   = 3'd0;
    localparam [2:0] VERIFY_READ_H = 3'd1;
    localparam [2:0] VERIFY_WAIT_H = 3'd2;
    localparam [2:0] VERIFY_READ_L = 3'd3;
    localparam [2:0] VERIFY_WAIT_L = 3'd4;
    localparam [2:0] VERIFY_DONE   = 3'd5;
    reg [2:0] verify_state;
    reg [7:0] id_high, id_low;
    reg communication_error, verify_done, last_attempt_failed;
    assign camera_id = {id_high, id_low};

    wire base_start, base_busy, base_done, base_error, base_init_done;
    wire base_init_error;
    wire [15:0] base_addr;
    wire [7:0] base_data;
    wire jpeg_start, jpeg_busy, jpeg_done, jpeg_error, jpeg_init_done;
    wire jpeg_init_error;
    wire [15:0] jpeg_addr;
    wire [7:0] jpeg_data;
    wire writer_start, writer_busy, writer_done, writer_error;
    wire [15:0] writer_addr;
    wire [7:0] writer_data;

    reg [1:0] algorithm_mode_sync1, algorithm_mode_sync2;
    reg [7:0] algorithm_sequence_sync1, algorithm_sequence_sync2;
    reg algorithm_toggle_sync1, algorithm_toggle_sync2, algorithm_toggle_seen;
    reg camera_vsync_sync1, camera_vsync_sync2, camera_vsync_previous;
    reg [1:0] pending_algorithm_mode;
    reg [7:0] pending_algorithm_sequence;
    reg algorithm_request_pending;
    reg [1:0] active_algorithm_mode;
    reg [7:0] active_algorithm_sequence;
    reg [1:0] effect_state;
    reg [1:0] effect_register_index;
    reg effect_writer_start;
    reg [15:0] effect_writer_addr;
    reg [7:0] effect_writer_data;

    localparam [1:0] EFFECT_IDLE = 2'd0;
    localparam [1:0] EFFECT_WAIT_FRAME = 2'd1;
    localparam [1:0] EFFECT_START = 2'd2;
    localparam [1:0] EFFECT_WAIT_DONE = 2'd3;
    wire camera_frame_boundary = camera_vsync_sync2 && !camera_vsync_previous;

    assign base_busy  = writer_busy;
    assign base_done  = writer_done;
    assign base_error = writer_error;
    assign jpeg_busy  = writer_busy;
    assign jpeg_done  = writer_done;
    assign jpeg_error = writer_error;
    assign writer_start = !base_init_done ? base_start :
                          !jpeg_init_done ? jpeg_start : effect_writer_start;
    assign writer_addr  = !base_init_done ? base_addr :
                          !jpeg_init_done ? jpeg_addr : effect_writer_addr;
    assign writer_data  = !base_init_done ? base_data :
                          !jpeg_init_done ? jpeg_data : effect_writer_data;
    assign cam_init_error = base_init_error | jpeg_init_error;

    always @(posedge clk_100m) begin
        if (rst) begin
            verify_state <= VERIFY_WAIT;
            sccb_start <= 1'b0;
            sccb_reg_addr <= 16'd0;
            id_high <= 8'd0;
            id_low <= 8'd0;
            communication_error <= 1'b0;
            verify_done <= 1'b0;
            retry_request <= 1'b0;
            last_attempt_failed <= 1'b0;
        end else if (!power_ready || retry_request) begin
            verify_state <= VERIFY_WAIT;
            sccb_start <= 1'b0;
            sccb_reg_addr <= 16'd0;
            id_high <= 8'd0;
            id_low <= 8'd0;
            communication_error <= 1'b0;
            verify_done <= 1'b0;
            retry_request <= 1'b0;
        end else begin
            sccb_start <= 1'b0;
            retry_request <= 1'b0;
            if (verify_done && (base_init_error || jpeg_init_error)) begin
                verify_state <= VERIFY_WAIT;
                verify_done <= 1'b0;
                retry_request <= 1'b1;
                last_attempt_failed <= 1'b1;
            end else begin
                case (verify_state)
                    VERIFY_WAIT: verify_state <= VERIFY_READ_H;
                    VERIFY_READ_H: if (!sccb_busy) begin
                        sccb_reg_addr <= 16'h300a;
                        sccb_start <= 1'b1;
                        verify_state <= VERIFY_WAIT_H;
                    end
                    VERIFY_WAIT_H: if (sccb_done) begin
                        id_high <= sccb_read_data;
                        communication_error <= communication_error | sccb_nack;
                        verify_state <= VERIFY_READ_L;
                    end
                    VERIFY_READ_L: if (!sccb_busy) begin
                        sccb_reg_addr <= 16'h300b;
                        sccb_start <= 1'b1;
                        verify_state <= VERIFY_WAIT_L;
                    end
                    VERIFY_WAIT_L: if (sccb_done) begin
                        id_low <= sccb_read_data;
                        if (sccb_nack || communication_error ||
                            ({id_high, sccb_read_data} != 16'h5640)) begin
                            communication_error <= 1'b1;
                            verify_done <= 1'b0;
                            retry_request <= 1'b1;
                            last_attempt_failed <= 1'b1;
                            verify_state <= VERIFY_WAIT;
                        end else begin
                            communication_error <= 1'b0;
                            verify_done <= 1'b1;
                            last_attempt_failed <= 1'b0;
                            verify_state <= VERIFY_DONE;
                        end
                    end
                    default: verify_state <= VERIFY_DONE;
                endcase
            end
        end
    end

    wire camera_ok = verify_done && (camera_id == 16'h5640) &&
                     !communication_error;

    ov5640_init_rgb565 base_init_i (
        .clk(clk_100m), .rst_n(power_ready), .enable(camera_ok),
        .wr_start(base_start), .wr_addr(base_addr), .wr_data(base_data),
        .wr_busy(base_busy), .wr_done(base_done), .wr_error(base_error),
        .init_done(base_init_done), .init_error(base_init_error)
    );

    ov5640_jpeg_1080p_override jpeg_init_i (
        .clk(clk_100m), .rst_n(power_ready), .enable(base_init_done),
        .wr_start(jpeg_start), .wr_addr(jpeg_addr), .wr_data(jpeg_data),
        .wr_busy(jpeg_busy), .wr_done(jpeg_done), .wr_error(jpeg_error),
        .init_done(jpeg_init_done), .init_error(jpeg_init_error)
    );

    sccb_write_reg_open sccb_write_i (
        .clk(clk_100m), .rst_n(power_ready), .start(writer_start),
        .reg_addr(writer_addr), .wr_data(writer_data),
        .busy(writer_busy), .done(writer_done), .nack_error(writer_error),
        .scl_in(sccb_scl_in), .sda_in(sccb_sda_in),
        .scl_drive_low(write_scl_low), .sda_drive_low(write_sda_low)
    );

    // The OV5640 ISP processes the JPEG before it reaches the FPGA. The FPGA
    // accepts host mode commands and applies them over SCCB at a frame edge.
    // 0=color, 1=grayscale, 2=OV5640 black/white effect, 3=negative.
    always @* begin
        case (effect_register_index)
            2'd0: begin
                effect_writer_addr = 16'h5580;
                case (active_algorithm_mode)
                    2'd1: effect_writer_data = 8'h20;
                    2'd2: effect_writer_data = 8'h1e;
                    2'd3: effect_writer_data = 8'h40;
                    default: effect_writer_data = 8'h06;
                endcase
            end
            2'd1: begin
                effect_writer_addr = 16'h5583;
                effect_writer_data = (active_algorithm_mode == 2'd2) ? 8'h80 : 8'h40;
            end
            2'd2: begin
                effect_writer_addr = 16'h5584;
                effect_writer_data = (active_algorithm_mode == 2'd2) ? 8'h80 : 8'h10;
            end
            default: begin
                effect_writer_addr = 16'h5003;
                effect_writer_data = 8'h08;
            end
        endcase
    end

    always @(posedge clk_100m) begin
        if (rst || !power_ready) begin
            algorithm_mode_sync1 <= 2'd0;
            algorithm_mode_sync2 <= 2'd0;
            algorithm_sequence_sync1 <= 8'd0;
            algorithm_sequence_sync2 <= 8'd0;
            algorithm_toggle_sync1 <= 1'b0;
            algorithm_toggle_sync2 <= 1'b0;
            algorithm_toggle_seen <= 1'b0;
            camera_vsync_sync1 <= 1'b0;
            camera_vsync_sync2 <= 1'b0;
            camera_vsync_previous <= 1'b0;
            pending_algorithm_mode <= 2'd0;
            pending_algorithm_sequence <= 8'd0;
            algorithm_request_pending <= 1'b0;
            active_algorithm_mode <= 2'd0;
            active_algorithm_sequence <= 8'd0;
            algorithm_mode_applied <= 2'd0;
            algorithm_sequence_applied <= 8'd0;
            effect_state <= EFFECT_IDLE;
            effect_register_index <= 2'd0;
            effect_writer_start <= 1'b0;
        end else begin
            algorithm_mode_sync1 <= algorithm_mode_request;
            algorithm_mode_sync2 <= algorithm_mode_sync1;
            algorithm_sequence_sync1 <= algorithm_sequence_request;
            algorithm_sequence_sync2 <= algorithm_sequence_sync1;
            algorithm_toggle_sync1 <= algorithm_update_toggle;
            algorithm_toggle_sync2 <= algorithm_toggle_sync1;
            camera_vsync_sync1 <= cam_vsync;
            camera_vsync_sync2 <= camera_vsync_sync1;
            camera_vsync_previous <= camera_vsync_sync2;
            effect_writer_start <= 1'b0;

            if (algorithm_toggle_sync2 != algorithm_toggle_seen) begin
                algorithm_toggle_seen <= algorithm_toggle_sync2;
                pending_algorithm_mode <= algorithm_mode_sync2;
                pending_algorithm_sequence <= algorithm_sequence_sync2;
                algorithm_request_pending <= 1'b1;
            end

            case (effect_state)
                EFFECT_IDLE: begin
                    if (jpeg_init_done && algorithm_request_pending)
                        effect_state <= EFFECT_WAIT_FRAME;
                end
                EFFECT_WAIT_FRAME: begin
                    if (camera_frame_boundary && algorithm_request_pending) begin
                        active_algorithm_mode <= pending_algorithm_mode;
                        active_algorithm_sequence <= pending_algorithm_sequence;
                        algorithm_request_pending <= 1'b0;
                        effect_register_index <= 2'd0;
                        effect_state <= EFFECT_START;
                    end
                end
                EFFECT_START: begin
                    if (!writer_busy && !writer_done) begin
                        effect_writer_start <= 1'b1;
                        effect_state <= EFFECT_WAIT_DONE;
                    end
                end
                EFFECT_WAIT_DONE: begin
                    if (writer_done) begin
                        if (writer_error) begin
                            effect_state <= EFFECT_IDLE;
                        end else if (effect_register_index == 2'd3) begin
                            algorithm_mode_applied <= active_algorithm_mode;
                            algorithm_sequence_applied <= active_algorithm_sequence;
                            effect_state <= algorithm_request_pending ?
                                            EFFECT_WAIT_FRAME : EFFECT_IDLE;
                        end else begin
                            effect_register_index <= effect_register_index + 1'b1;
                            effect_state <= EFFECT_START;
                        end
                    end
                end
                default: effect_state <= EFFECT_IDLE;
            endcase
        end
    end

    assign sccb_nack_error = last_attempt_failed | communication_error |
                             sccb_nack | writer_error;

    (* ASYNC_REG = "TRUE" *) reg init_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg init_sync2 = 1'b0;
    reg href_d = 1'b0, vsync_d = 1'b0;
    reg [15:0] href_count_work = 16'd0;
    reg [15:0] frame_href_work = 16'd0;
    assign cam_init_done = init_sync2;
    always @(posedge cam_pclk) begin
        init_sync1 <= jpeg_init_done;
        init_sync2 <= init_sync1;
        if (!init_sync2) begin
            href_d <= 1'b0;
            vsync_d <= 1'b0;
            byte_data <= 8'd0;
            byte_valid <= 1'b0;
            frame_sync <= 1'b0;
            href_count_work <= 16'd0;
            frame_href_work <= 16'd0;
            href_byte_count <= 16'd0;
            frame_href_count <= 16'd0;
        end else begin
            href_d <= cam_href;
            vsync_d <= cam_vsync;
            byte_valid <= 1'b0;
            frame_sync <= 1'b0;
            if (cam_vsync && !vsync_d) begin
                frame_sync <= 1'b1;
                frame_href_count <= frame_href_work;
                frame_href_work <= 16'd0;
                href_count_work <= 16'd0;
            end else if (!cam_href && href_d) begin
                href_byte_count <= href_count_work;
                href_count_work <= 16'd0;
                frame_href_work <= frame_href_work + 1'b1;
            end else if (cam_href) begin
                byte_data <= cam_data;
                byte_valid <= 1'b1;
                href_count_work <= href_count_work + 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
