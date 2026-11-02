`timescale 1ns / 1ps

module ov5640_init_rgb565 (
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

    localparam [8:0] INIT_LAST = 9'd348;
    localparam [1:0] ST_WAIT = 2'd0;
    localparam [1:0] ST_WRITE = 2'd1;
    localparam [1:0] ST_DONE = 2'd2;

    reg [8:0] init_index;
    reg [1:0] state;

    // Full OV5640 RGB565 ISP setup followed by CAM1 DVP values verified on this board.
    (* rom_style = "distributed" *) reg [23:0] init_rom [0:347];
    initial begin
        init_rom[  0 ] = 24'h300842;
        init_rom[  1 ] = 24'h310303;
        init_rom[  2 ] = 24'h3017ff;
        init_rom[  3 ] = 24'h3018ff;
        init_rom[  4 ] = 24'h303713;
        init_rom[  5 ] = 24'h310801;
        init_rom[  6 ] = 24'h363036;
        init_rom[  7 ] = 24'h36310e;
        init_rom[  8 ] = 24'h3632e2;
        init_rom[  9 ] = 24'h363312;
        init_rom[ 10 ] = 24'h3621e0;
        init_rom[ 11 ] = 24'h3704a0;
        init_rom[ 12 ] = 24'h37035a;
        init_rom[ 13 ] = 24'h371578;
        init_rom[ 14 ] = 24'h371701;
        init_rom[ 15 ] = 24'h370b60;
        init_rom[ 16 ] = 24'h37051a;
        init_rom[ 17 ] = 24'h390502;
        init_rom[ 18 ] = 24'h390610;
        init_rom[ 19 ] = 24'h39010a;
        init_rom[ 20 ] = 24'h373112;
        init_rom[ 21 ] = 24'h360008;
        init_rom[ 22 ] = 24'h360133;
        init_rom[ 23 ] = 24'h302d60;
        init_rom[ 24 ] = 24'h362052;
        init_rom[ 25 ] = 24'h371b20;
        init_rom[ 26 ] = 24'h471c50;
        init_rom[ 27 ] = 24'h3a1343;
        init_rom[ 28 ] = 24'h3a1800;
        init_rom[ 29 ] = 24'h3a19f8;
        init_rom[ 30 ] = 24'h363513;
        init_rom[ 31 ] = 24'h363603;
        init_rom[ 32 ] = 24'h363440;
        init_rom[ 33 ] = 24'h362201;
        init_rom[ 34 ] = 24'h3c0134;
        init_rom[ 35 ] = 24'h3c0428;
        init_rom[ 36 ] = 24'h3c0598;
        init_rom[ 37 ] = 24'h3c0600;
        init_rom[ 38 ] = 24'h3c0708;
        init_rom[ 39 ] = 24'h3c0800;
        init_rom[ 40 ] = 24'h3c091c;
        init_rom[ 41 ] = 24'h3c0a9c;
        init_rom[ 42 ] = 24'h3c0b40;
        init_rom[ 43 ] = 24'h381000;
        init_rom[ 44 ] = 24'h381110;
        init_rom[ 45 ] = 24'h381200;
        init_rom[ 46 ] = 24'h370864;
        init_rom[ 47 ] = 24'h400102;
        init_rom[ 48 ] = 24'h40051a;
        init_rom[ 49 ] = 24'h300000;
        init_rom[ 50 ] = 24'h3004ff;
        init_rom[ 51 ] = 24'h43006f;
        init_rom[ 52 ] = 24'h501f01;
        init_rom[ 53 ] = 24'h440e00;
        init_rom[ 54 ] = 24'h5000a7;
        init_rom[ 55 ] = 24'h3a0f78;
        init_rom[ 56 ] = 24'h3a1068;
        init_rom[ 57 ] = 24'h3a1b78;
        init_rom[ 58 ] = 24'h3a1e68;
        init_rom[ 59 ] = 24'h3a1160;
        init_rom[ 60 ] = 24'h3a1f14;
        init_rom[ 61 ] = 24'h580023;
        init_rom[ 62 ] = 24'h580114;
        init_rom[ 63 ] = 24'h58020f;
        init_rom[ 64 ] = 24'h58030f;
        init_rom[ 65 ] = 24'h580412;
        init_rom[ 66 ] = 24'h580526;
        init_rom[ 67 ] = 24'h58060c;
        init_rom[ 68 ] = 24'h580708;
        init_rom[ 69 ] = 24'h580805;
        init_rom[ 70 ] = 24'h580905;
        init_rom[ 71 ] = 24'h580a08;
        init_rom[ 72 ] = 24'h580b0d;
        init_rom[ 73 ] = 24'h580c08;
        init_rom[ 74 ] = 24'h580d03;
        init_rom[ 75 ] = 24'h580e00;
        init_rom[ 76 ] = 24'h580f00;
        init_rom[ 77 ] = 24'h581003;
        init_rom[ 78 ] = 24'h581109;
        init_rom[ 79 ] = 24'h581207;
        init_rom[ 80 ] = 24'h581303;
        init_rom[ 81 ] = 24'h581400;
        init_rom[ 82 ] = 24'h581501;
        init_rom[ 83 ] = 24'h581603;
        init_rom[ 84 ] = 24'h581708;
        init_rom[ 85 ] = 24'h58180d;
        init_rom[ 86 ] = 24'h581908;
        init_rom[ 87 ] = 24'h581a05;
        init_rom[ 88 ] = 24'h581b06;
        init_rom[ 89 ] = 24'h581c08;
        init_rom[ 90 ] = 24'h581d0e;
        init_rom[ 91 ] = 24'h581e29;
        init_rom[ 92 ] = 24'h581f17;
        init_rom[ 93 ] = 24'h582011;
        init_rom[ 94 ] = 24'h582111;
        init_rom[ 95 ] = 24'h582215;
        init_rom[ 96 ] = 24'h582328;
        init_rom[ 97 ] = 24'h582446;
        init_rom[ 98 ] = 24'h582526;
        init_rom[ 99 ] = 24'h582608;
        init_rom[100 ] = 24'h582726;
        init_rom[101 ] = 24'h582864;
        init_rom[102 ] = 24'h582926;
        init_rom[103 ] = 24'h582a24;
        init_rom[104 ] = 24'h582b22;
        init_rom[105 ] = 24'h582c24;
        init_rom[106 ] = 24'h582d24;
        init_rom[107 ] = 24'h582e06;
        init_rom[108 ] = 24'h582f22;
        init_rom[109 ] = 24'h583040;
        init_rom[110 ] = 24'h583142;
        init_rom[111 ] = 24'h583224;
        init_rom[112 ] = 24'h583326;
        init_rom[113 ] = 24'h583424;
        init_rom[114 ] = 24'h583522;
        init_rom[115 ] = 24'h583622;
        init_rom[116 ] = 24'h583726;
        init_rom[117 ] = 24'h583844;
        init_rom[118 ] = 24'h583924;
        init_rom[119 ] = 24'h583a26;
        init_rom[120 ] = 24'h583b28;
        init_rom[121 ] = 24'h583c42;
        init_rom[122 ] = 24'h583dce;
        init_rom[123 ] = 24'h5180ff;
        init_rom[124 ] = 24'h5181f2;
        init_rom[125 ] = 24'h518200;
        init_rom[126 ] = 24'h518314;
        init_rom[127 ] = 24'h518425;
        init_rom[128 ] = 24'h518524;
        init_rom[129 ] = 24'h518609;
        init_rom[130 ] = 24'h518709;
        init_rom[131 ] = 24'h518809;
        init_rom[132 ] = 24'h518975;
        init_rom[133 ] = 24'h518a54;
        init_rom[134 ] = 24'h518be0;
        init_rom[135 ] = 24'h518cb2;
        init_rom[136 ] = 24'h518d42;
        init_rom[137 ] = 24'h518e3d;
        init_rom[138 ] = 24'h518f56;
        init_rom[139 ] = 24'h519046;
        init_rom[140 ] = 24'h5191f8;
        init_rom[141 ] = 24'h519204;
        init_rom[142 ] = 24'h519370;
        init_rom[143 ] = 24'h5194f0;
        init_rom[144 ] = 24'h5195f0;
        init_rom[145 ] = 24'h519603;
        init_rom[146 ] = 24'h519701;
        init_rom[147 ] = 24'h519804;
        init_rom[148 ] = 24'h519912;
        init_rom[149 ] = 24'h519a04;
        init_rom[150 ] = 24'h519b00;
        init_rom[151 ] = 24'h519c06;
        init_rom[152 ] = 24'h519d82;
        init_rom[153 ] = 24'h519e38;
        init_rom[154 ] = 24'h548001;
        init_rom[155 ] = 24'h548108;
        init_rom[156 ] = 24'h548214;
        init_rom[157 ] = 24'h548328;
        init_rom[158 ] = 24'h548451;
        init_rom[159 ] = 24'h548565;
        init_rom[160 ] = 24'h548671;
        init_rom[161 ] = 24'h54877d;
        init_rom[162 ] = 24'h548887;
        init_rom[163 ] = 24'h548991;
        init_rom[164 ] = 24'h548a9a;
        init_rom[165 ] = 24'h548baa;
        init_rom[166 ] = 24'h548cb8;
        init_rom[167 ] = 24'h548dcd;
        init_rom[168 ] = 24'h548edd;
        init_rom[169 ] = 24'h548fea;
        init_rom[170 ] = 24'h54901d;
        init_rom[171 ] = 24'h53811e;
        init_rom[172 ] = 24'h53825b;
        init_rom[173 ] = 24'h538308;
        init_rom[174 ] = 24'h53840a;
        init_rom[175 ] = 24'h53857e;
        init_rom[176 ] = 24'h538688;
        init_rom[177 ] = 24'h53877c;
        init_rom[178 ] = 24'h53886c;
        init_rom[179 ] = 24'h538910;
        init_rom[180 ] = 24'h538a01;
        init_rom[181 ] = 24'h538b98;
        init_rom[182 ] = 24'h558006;
        init_rom[183 ] = 24'h558340;
        init_rom[184 ] = 24'h558410;
        init_rom[185 ] = 24'h558910;
        init_rom[186 ] = 24'h558a00;
        init_rom[187 ] = 24'h558bf8;
        init_rom[188 ] = 24'h501d40;
        init_rom[189 ] = 24'h530008;
        init_rom[190 ] = 24'h530130;
        init_rom[191 ] = 24'h530210;
        init_rom[192 ] = 24'h530300;
        init_rom[193 ] = 24'h530408;
        init_rom[194 ] = 24'h530530;
        init_rom[195 ] = 24'h530608;
        init_rom[196 ] = 24'h530716;
        init_rom[197 ] = 24'h530908;
        init_rom[198 ] = 24'h530a30;
        init_rom[199 ] = 24'h530b04;
        init_rom[200 ] = 24'h530c06;
        init_rom[201 ] = 24'h502500;
        init_rom[202 ] = 24'h303511;
        init_rom[203 ] = 24'h30363c;
        init_rom[204 ] = 24'h3c0708;
        init_rom[205 ] = 24'h382041;
        init_rom[206 ] = 24'h382101;
        init_rom[207 ] = 24'h381431;
        init_rom[208 ] = 24'h381531;
        init_rom[209 ] = 24'h380000;
        init_rom[210 ] = 24'h380100;
        init_rom[211 ] = 24'h380200;
        init_rom[212 ] = 24'h380304;
        init_rom[213 ] = 24'h38040a;
        init_rom[214 ] = 24'h38053f;
        init_rom[215 ] = 24'h380607;
        init_rom[216 ] = 24'h38079b;
        init_rom[217 ] = 24'h381306;
        init_rom[218 ] = 24'h361800;
        init_rom[219 ] = 24'h361229;
        init_rom[220 ] = 24'h370952;
        init_rom[221 ] = 24'h370c03;
        init_rom[222 ] = 24'h3a0217;
        init_rom[223 ] = 24'h3a0310;
        init_rom[224 ] = 24'h3a1417;
        init_rom[225 ] = 24'h3a1510;
        init_rom[226 ] = 24'h400402;
        init_rom[227 ] = 24'h471303;
        init_rom[228 ] = 24'h440704;
        init_rom[229 ] = 24'h460c22;
        init_rom[230 ] = 24'h483722;
        init_rom[231 ] = 24'h382402;
        init_rom[232 ] = 24'h5001a3;
        init_rom[233 ] = 24'h3b070a;
        init_rom[234 ] = 24'h503d00;
        init_rom[235 ] = 24'h301602;
        init_rom[236 ] = 24'h301c02;
        init_rom[237 ] = 24'h301902;
        init_rom[238 ] = 24'h301900;
        init_rom[239 ] = 24'h300e58;
        init_rom[240 ] = 24'h300010;
        init_rom[241 ] = 24'h300108;
        init_rom[242 ] = 24'h30021c;
        init_rom[243 ] = 24'h3004ef;
        init_rom[244 ] = 24'h3005f7;
        init_rom[245 ] = 24'h3006e3;
        init_rom[246 ] = 24'h3007e7;
        init_rom[247 ] = 24'h3017ff;
        init_rom[248 ] = 24'h3018ff;
        init_rom[249 ] = 24'h474020;
        init_rom[250 ] = 24'h473000;
        init_rom[251 ] = 24'h382047;
        init_rom[252 ] = 24'h382101;
        init_rom[253 ] = 24'h381431;
        init_rom[254 ] = 24'h381531;
        init_rom[255 ] = 24'h380802;
        init_rom[256 ] = 24'h380980;
        init_rom[257 ] = 24'h380a01;
        init_rom[258 ] = 24'h380be0;
        init_rom[259 ] = 24'h380c07;
        init_rom[260 ] = 24'h380d68;
        init_rom[261 ] = 24'h380e04;
        init_rom[262 ] = 24'h380f38;
        init_rom[263 ] = 24'h460b35;
        init_rom[264 ] = 24'h460c20;
        init_rom[265 ] = 24'h483722;
        init_rom[266 ] = 24'h382402;
        init_rom[267 ] = 24'h43006f;
        init_rom[268 ] = 24'h501f01;
        init_rom[269 ] = 24'h5000a7;
        init_rom[270 ] = 24'h5001a3;
        init_rom[271 ] = 24'h503d00;
        init_rom[272 ] = 24'h420200;
        // Keep the inherited VGA profile in standby; the following 1080p
        // block is the only one allowed to start sensor streaming.
        init_rom[273 ] = 24'h300842;

        // 1920x1080 RGB565 output for the FPGA pixel-processing path.
        // Reuse the board-validated full-width 16:9 sensor window and timing.
        // Stable full-view 1920x1080 RGB565 timing: 84 MHz, HTS=2844 and
        // VTS=1500. Manual /1 PCLK avoids the automatic divider that limited
        // the stream to about 2.4 fps. Shorter 1120-line VTS stopped DVP output.
        init_rom[274 ] = 24'h300842;
        init_rom[275 ] = 24'h303418;
        init_rom[276 ] = 24'h303510;
        init_rom[277 ] = 24'h303654;
        init_rom[278 ] = 24'h303713;
        init_rom[279 ] = 24'h310801;
        init_rom[280 ] = 24'h3c0707;
        init_rom[281 ] = 24'h3c0800;
        init_rom[282 ] = 24'h3c091c;
        init_rom[283 ] = 24'h3c0a9c;
        init_rom[284 ] = 24'h3c0b40;
        init_rom[285 ] = 24'h380000;
        init_rom[286 ] = 24'h380100;
        init_rom[287 ] = 24'h380200;
        init_rom[288 ] = 24'h3803ee;
        init_rom[289 ] = 24'h38040a;
        init_rom[290 ] = 24'h38053f;
        init_rom[291 ] = 24'h380606;
        init_rom[292 ] = 24'h3807b1;
        init_rom[293 ] = 24'h380807;
        init_rom[294 ] = 24'h380980;
        init_rom[295 ] = 24'h380a04;
        init_rom[296 ] = 24'h380b38;
        init_rom[297 ] = 24'h380c0b;
        init_rom[298 ] = 24'h380d1c;
        init_rom[299 ] = 24'h380e05;
        init_rom[300 ] = 24'h380fdc;
        init_rom[301 ] = 24'h381000;
        init_rom[302 ] = 24'h381110;
        init_rom[303 ] = 24'h381200;
        init_rom[304 ] = 24'h381304;
        init_rom[305 ] = 24'h381411;
        init_rom[306 ] = 24'h381511;
        init_rom[307 ] = 24'h382047;
        init_rom[308 ] = 24'h382121;
        init_rom[309 ] = 24'h361804;
        init_rom[310 ] = 24'h36122b;
        init_rom[311 ] = 24'h370864;
        init_rom[312 ] = 24'h370912;
        init_rom[313 ] = 24'h370c00;
        init_rom[314 ] = 24'h3a0205;
        init_rom[315 ] = 24'h3a03dc;
        init_rom[316 ] = 24'h3a0801;
        init_rom[317 ] = 24'h3a0950;
        init_rom[318 ] = 24'h3a0a01;
        init_rom[319 ] = 24'h3a0b18;
        init_rom[320 ] = 24'h3a0e03;
        init_rom[321 ] = 24'h3a0d04;
        init_rom[322 ] = 24'h3a1405;
        init_rom[323 ] = 24'h3a15dc;
        init_rom[324 ] = 24'h400102;
        init_rom[325 ] = 24'h400406;
        init_rom[326 ] = 24'h40051a;
        init_rom[327 ] = 24'h43006f;
        init_rom[328 ] = 24'h501f01;
        init_rom[329 ] = 24'h5001a3;
        init_rom[330 ] = 24'h30021c;
        init_rom[331 ] = 24'h3006e3;
        init_rom[332 ] = 24'h460207;
        init_rom[333 ] = 24'h460380;
        init_rom[334 ] = 24'h460404;
        init_rom[335 ] = 24'h460538;
        init_rom[336 ] = 24'h460b35;
        // Disable OV5640 automatic DVP pixel-clock division. In automatic
        // mode the sensor selected a very large divider on this full-frame
        // RGB565 path, reducing the observed stream to about 2.4 fps.
        // Force the manual /1 divider while retaining the validated 84 MHz
        // PLL and full-width 1080p timing.
        init_rom[337 ] = 24'h460c22;
        init_rom[338 ] = 24'h382401;
        init_rom[339 ] = 24'h503d00;
        init_rom[340 ] = 24'h474020;
        // Release the FIFO/S2P datapath reset and enable the S2P clock before
        // starting raw DVP output. The inherited 0x1c/0xe3 values leave the
        // sensor's DVP output path held in reset / clock-gated.
        init_rom[341 ] = 24'h300200;
        init_rom[342 ] = 24'h3006eb;
        // The inherited profile left 0x3821[5] compression enabled and
        // selected JPEG mode 3. Clear both before streaming raw RGB565.
        init_rom[343 ] = 24'h382101;
        init_rom[344 ] = 24'h471300;
        // Keep OV5640 AE/AGC and AWB automatic, and enable the sensor's
        // 50/60 Hz banding control before starting the DVP stream.
        init_rom[345 ] = 24'h3a0078;
        init_rom[346 ] = 24'h350300;
        init_rom[347 ] = 24'h340600;
        init_rom[348 ] = 24'h300802;
    end

    always @(*) begin
        {wr_addr, wr_data} = init_rom[init_index];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_WAIT;
            init_index <= 9'd0;
            wr_start <= 1'b0;
            init_done <= 1'b0;
            init_error <= 1'b0;
        end else begin
            wr_start <= 1'b0;
            case (state)
                ST_WAIT: begin
                    if (enable) begin
                        init_index <= 9'd0;
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
                            init_done <= 1'b1;
                            state <= ST_DONE;
                        end else begin
                            init_index <= init_index + 1'b1;
                        end
                    end
                end
                ST_DONE: init_done <= 1'b1;
                default: state <= ST_WAIT;
            endcase
        end
    end

endmodule
