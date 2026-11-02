`timescale 1ns / 1ps
`default_nettype none

// Applied after the board-proven full ISP initialization. Use the widest
// centered 16:9 sensor window, then let the OV5640 scaler produce 1920x1080
// RGB565. The historical module name is retained so existing build scripts
// keep working; this variant deliberately disables JPEG compression.
// At the existing 84 MHz PCLK, HTS=2844 and VTS=1500 imply about 19.7 fps.
// This trades 1080p30 cadence for a wider field of view without changing the
// FPGA/network/JPEG payload interface. JPEG mode 3 emits variable HREF bytes.
module ov5640_jpeg_1080p_override (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    output reg         wr_start,
    output reg [15:0]  wr_addr,
    output reg [7:0]   wr_data,
    input  wire        wr_busy,
    input  wire        wr_done,
    input  wire        wr_error,
    output reg         init_done,
    output reg         init_error
);

    localparam integer INIT_LAST = 69;
    localparam [1:0] ST_WAIT = 2'd0;
    localparam [1:0] ST_WRITE = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [6:0] init_index;
    reg [1:0] state;
    (* rom_style = "distributed" *) reg [23:0] init_rom [0:INIT_LAST];

    initial begin
        // Stop streaming while the clock tree and crop window change.
        init_rom[0]  = 24'h300842;

        // 24 MHz XVCLK -> 84 MHz sensor/PCLK for 1080p30 JPEG:
        // 24/3*84/2(PLL R)/2(BIT_DIV)/2(SCLK_DIV) = 84 MHz.
        // 0x2a was measured on hardware as 42.03 MHz PCLK / 15 fps.
        init_rom[1]  = 24'h303418;
        init_rom[2]  = 24'h303510;
        init_rom[3]  = 24'h303654;
        init_rom[4]  = 24'h303713;
        init_rom[5]  = 24'h310801;

        init_rom[6]  = 24'h3c0707;
        init_rom[7]  = 24'h3c0800;
        init_rom[8]  = 24'h3c091c;
        init_rom[9]  = 24'h3c0a9c;
        init_rom[10] = 24'h3c0b40;

        // Centered 2624x1476 crop: full sensor width and 16:9 aspect.
        // X=[0,2623], Y=[238,1713]. The previous 1952x1088 crop lost
        // approximately 25.6% of the sensor's horizontal field of view.
        init_rom[11] = 24'h380000;
        init_rom[12] = 24'h380100;
        init_rom[13] = 24'h380200;
        init_rom[14] = 24'h3803ee;
        init_rom[15] = 24'h38040a;
        init_rom[16] = 24'h38053f;
        init_rom[17] = 24'h380606;
        init_rom[18] = 24'h3807b1;

        init_rom[19] = 24'h380807;
        init_rom[20] = 24'h380980;
        init_rom[21] = 24'h380a04;
        init_rom[22] = 24'h380b38;
        // Allow enough sensor line/frame time for the expanded input window.
        // 2844 * 1500 at 84 MHz => approximately 19.7 frames/s.
        init_rom[23] = 24'h380c0b;
        init_rom[24] = 24'h380d1c;
        init_rom[25] = 24'h380e05;
        init_rom[26] = 24'h380fdc;
        init_rom[27] = 24'h381000;
        init_rom[28] = 24'h381110;
        init_rom[29] = 24'h381200;
        init_rom[30] = 24'h381304;
        init_rom[31] = 24'h381411;
        init_rom[32] = 24'h381511;

        // Preserve the already verified CAM1 orientation and enable JPEG.
        init_rom[33] = 24'h382047;
        init_rom[34] = 24'h382121;

        init_rom[35] = 24'h361804;
        init_rom[36] = 24'h36122b;
        init_rom[37] = 24'h370864;
        init_rom[38] = 24'h370912;
        init_rom[39] = 24'h370c00;
        init_rom[40] = 24'h3a0205;
        init_rom[41] = 24'h3a03dc;
        init_rom[42] = 24'h3a0801;
        init_rom[43] = 24'h3a0950;
        init_rom[44] = 24'h3a0a01;
        init_rom[45] = 24'h3a0b18;
        init_rom[46] = 24'h3a0e03;
        init_rom[47] = 24'h3a0d04;
        init_rom[48] = 24'h3a1405;
        init_rom[49] = 24'h3a15dc;
        init_rom[50] = 24'h400102;
        init_rom[51] = 24'h400406;
        init_rom[52] = 24'h40051a;

        // Raw RGB565 source. 0x4300=0x61 and 0x501f=0x01 are the same
        // board-proven format settings used by the original 640x480 design.
        init_rom[53] = 24'h430061;
        init_rom[54] = 24'h501f01;
        init_rom[55] = 24'h5001a3;
        init_rom[56] = 24'h30021c;
        init_rom[57] = 24'h3006e3;
        init_rom[58] = 24'h460207;
        init_rom[59] = 24'h460380;
        init_rom[60] = 24'h460404;
        init_rom[61] = 24'h460538;
        init_rom[62] = 24'h460b35;
        // 1080p uses the /2 PCLK divider.
        init_rom[63] = 24'h382402;
        init_rom[64] = 24'h503d00;
        init_rom[65] = 24'h474020;

        // Keep the raw DVP path enabled, then stream.
        init_rom[66] = 24'h30021c;
        init_rom[67] = 24'h3006e3;

        // Disable AEC night-mode frame stretching so the sensor stays at
        // the programmed 30 fps timing, then leave software standby.
        init_rom[68] = 24'h3a0038;
        init_rom[69] = 24'h300802;
    end

    always @* begin
        {wr_addr, wr_data} = init_rom[init_index];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_WAIT;
            init_index <= 7'd0;
            wr_start <= 1'b0;
            init_done <= 1'b0;
            init_error <= 1'b0;
        end else begin
            wr_start <= 1'b0;
            case (state)
                ST_WAIT: begin
                    if (enable) begin
                        init_index <= 7'd0;
                        state <= ST_WRITE;
                    end
                end
                ST_WRITE: begin
                    if (!wr_busy && !wr_done)
                        wr_start <= 1'b1;
                    if (wr_done) begin
                        if (wr_error)
                            init_error <= 1'b1;
                        if (init_index == INIT_LAST) begin
                            init_done <= !wr_error && !init_error;
                            state <= ST_DONE;
                        end else begin
                            init_index <= init_index + 1'b1;
                        end
                    end
                end
                default: state <= ST_DONE;
            endcase
        end
    end

endmodule

`default_nettype wire
