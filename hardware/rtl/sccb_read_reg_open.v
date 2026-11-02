`timescale 1ns / 1ps    // ����ʱ�䵥λ1ns������1ps

module sccb_read_reg_open
(
    input  wire        clk,          // 100MHzϵͳʱ��
    input  wire        rst_n,        // �ߵ�ƽ��������
    input  wire        start,        // ����һ�ζ�ȡ
    input  wire [15:0] reg_addr,     // 16λ�Ĵ�����ַ

    output reg  [7:0]  rd_data,      // ��ȡ����8λ����
    output reg         busy,         // SCCBģ��æ
    output reg         done,         // һ�ζ�ȡ���
    output reg         nack_error,   // NACK����

    input  wire        scl_in,       // shared SCCB SCL level
    input  wire        sda_in,       // shared SCCB SDA level

    output wire        scl_drive_low,
    output wire        sda_drive_low
);


//============================================================
// ��©���
//============================================================

reg scl_drive_low_r;                   // 1��ʾ��������SCL
reg sda_drive_low_r;                   // 1��ʾ��������SDA

assign scl_drive_low = scl_drive_low_r;
assign sda_drive_low = sda_drive_low_r;


//============================================================
// 400kHz tick
// 100MHz / 250 = 400kHz
//============================================================

reg [7:0] div_cnt;                   // 0~249����
reg       tick;                      // 2.5us����


always @(posedge clk)
begin
    if (rst_n == 1'b0)
    begin
        div_cnt <= 8'd0;             // ��Ƶ����������
        tick    <= 1'b0;             // tick����
    end

    else
    begin
        if (div_cnt == 8'd249)
        begin
            div_cnt <= 8'd0;         // ���¼���
            tick    <= 1'b1;         // ����һ��tick
        end

        else
        begin
            div_cnt <= div_cnt + 1'b1; // ��������
            tick    <= 1'b0;           // ����ʱ��tickΪ0
        end
    end
end


//============================================================
// ״̬����
//============================================================

localparam ST_IDLE     = 4'd0;       // ����
localparam ST_START0   = 4'd1;       // START�׶�0
localparam ST_START1   = 4'd2;       // START�׶�1
localparam ST_SEND     = 4'd3;       // ����һ���ֽ�
localparam ST_ACK      = 4'd4;       // ����ACK
localparam ST_RSTART0  = 4'd5;       // Repeat START�׶�0
localparam ST_RSTART1  = 4'd6;       // Repeat START�׶�1
localparam ST_RSTART2  = 4'd7;       // Repeat START�׶�2
localparam ST_READ     = 4'd8;       // ��ȡһ���ֽ�
localparam ST_NACK     = 4'd9;       // ��������NACK
localparam ST_STOP0    = 4'd10;      // STOP�׶�0
localparam ST_STOP1    = 4'd11;      // STOP�׶�1
localparam ST_STOP2    = 4'd12;      // STOP�׶�2

reg [3:0] state;                     // ��ǰ״̬

reg [1:0] phase;                     // һ��SCL���ڵ�4���׶�
reg [2:0] bit_cnt;                   // bit������
reg [7:0] tx_byte;                   // ��ǰ�����ֽ�
reg [1:0] byte_stage;                // ��ǰ���ͽ׶�

reg [15:0] reg_addr_latched;         // ����Ĵ�����ַ


//============================================================
// SCCB��ȡ״̬��
//============================================================

always @(posedge clk)
begin
    if (rst_n == 1'b0)
    begin
        state            <= ST_IDLE;      // �ص�����״̬
        phase            <= 2'd0;         // ��λ����
        bit_cnt          <= 3'd7;         // ��bit7��ʼ
        tx_byte          <= 8'd0;         // ������������
        byte_stage       <= 2'd0;         // �׶�����

        reg_addr_latched <= 16'd0;        // ��ַ����

        rd_data          <= 8'd0;         // ��ȡ��������
        busy             <= 1'b0;         // ����
        done             <= 1'b0;         // δ���
        nack_error       <= 1'b0;         // �������

        scl_drive_low_r <= 1'b0;         // �ͷ�SCL
        sda_drive_low_r <= 1'b0;         // �ͷ�SDA
    end

    else
    begin
        done <= 1'b0;                     // doneֻ����һ��clk����


        if (state == ST_IDLE)
        begin
            busy          <= 1'b0;        // ��ǰ����
            scl_drive_low_r <= 1'b0;        // SCL�ͷ�Ϊ��
            sda_drive_low_r <= 1'b0;        // SDA�ͷ�Ϊ��
            phase         <= 2'd0;        // ��λ����

            if (start == 1'b1)
            begin
                busy             <= 1'b1;      // ��ʼͨ��
                nack_error       <= 1'b0;      // �������
                rd_data          <= 8'd0;      // �����ȡ����
                reg_addr_latched <= reg_addr;  // ����Ĵ�����ַ
                state            <= ST_START0; // ����START
            end
        end


        else if (tick == 1'b1)
        begin
            case (state)

                ST_START0:
                begin
                    scl_drive_low_r <= 1'b0;      // SCL���ָ�
                    sda_drive_low_r <= 1'b1;      // SDA�ߵ��Ͳ���START
                    state         <= ST_START1; // ��һ�׶�
                end


                ST_START1:
                begin
                    scl_drive_low_r <= 1'b1;      // ����SCL

                    tx_byte       <= 8'h78;      // OV5640д��ַ
                    byte_stage    <= 2'd0;       // ��ǰ����������ַ
                    bit_cnt       <= 3'd7;       // ��bit7��ʼ
                    phase         <= 2'd0;       // ��λ����

                    sda_drive_low_r <= 1'b1;       // 0x78 bit7=0

                    state         <= ST_SEND;    // �����ֽ�
                end


                ST_SEND:
                begin
                    case (phase)

                        2'd0:
                        begin
                            scl_drive_low_r <= 1'b0; // SCL����
                            phase         <= 2'd1; // ��һ�׶�
                        end


                        2'd1:
                        begin
                            phase <= 2'd2;         // ����SCL��
                        end


                        2'd2:
                        begin
                            scl_drive_low_r <= 1'b1; // SCL����
                            phase         <= 2'd3; // ��һ�׶�
                        end


                        2'd3:
                        begin
                            if (bit_cnt != 3'd0)
                            begin
                                bit_cnt <= bit_cnt - 1'b1; // ��һbit

                                if (tx_byte[bit_cnt - 1'b1] == 1'b0)
                                    sda_drive_low_r <= 1'b1; // ����0����SDA
                                else
                                    sda_drive_low_r <= 1'b0; // ����1�ͷ�SDA

                                phase <= 2'd0;              // ��һ��bit
                            end

                            else
                            begin
                                sda_drive_low_r <= 1'b0;     // �ͷ�SDA�ȴ�ACK
                                phase         <= 2'd0;      // ACK��phase0��ʼ
                                state         <= ST_ACK;    // ����ACK
                            end
                        end

                    endcase
                end


                ST_ACK:
                begin
                    case (phase)

                        2'd0:
                        begin
                            scl_drive_low_r <= 1'b0; // SCL����
                            phase         <= 2'd1; // ��һ�׶�
                        end


                        2'd1:
                        begin
                            if (sda_in != 1'b0)
                                nack_error <= 1'b1; // SDA�߱�ʾû��ACK

                            phase <= 2'd2;          // ��һ�׶�
                        end


                        2'd2:
                        begin
                            scl_drive_low_r <= 1'b1; // ����SCL
                            phase         <= 2'd3; // ACK����
                        end


                        2'd3:
                        begin
                            phase <= 2'd0;         // ��һ�ֽ����¿�ʼ

                            if (nack_error == 1'b1)
                            begin
                                sda_drive_low_r <= 1'b1; // ΪSTOP׼��SDA��
                                state         <= ST_STOP0;
                            end

                            else
                            begin
                                case (byte_stage)

                                    2'd0:
                                    begin
                                        tx_byte    <= reg_addr_latched[15:8]; // �Ĵ�����ַ��8λ
                                        byte_stage <= 2'd1;                   // ��һ�׶�
                                        bit_cnt    <= 3'd7;                   // bit7��ʼ

                                        if (reg_addr_latched[15] == 1'b0)
                                            sda_drive_low_r <= 1'b1;            // bit7=0
                                        else
                                            sda_drive_low_r <= 1'b0;            // bit7=1

                                        state <= ST_SEND;                     // ���͸ߵ�ַ
                                    end


                                    2'd1:
                                    begin
                                        tx_byte    <= reg_addr_latched[7:0];  // �Ĵ�����ַ��8λ
                                        byte_stage <= 2'd2;                   // ��һ�׶�
                                        bit_cnt    <= 3'd7;                   // bit7��ʼ

                                        if (reg_addr_latched[7] == 1'b0)
                                            sda_drive_low_r <= 1'b1;            // bit7=0
                                        else
                                            sda_drive_low_r <= 1'b0;            // bit7=1

                                        state <= ST_SEND;                     // ���͵͵�ַ
                                    end


                                    2'd2:
                                    begin
                                        sda_drive_low_r <= 1'b0;               // �ͷ�SDA
                                        state         <= ST_RSTART0;          // Repeated START
                                    end


                                    2'd3:
                                    begin
                                        sda_drive_low_r <= 1'b0;               // �ͷ�SDA������ͷ
                                        bit_cnt       <= 3'd7;                // ��bit7��ȡ
                                        state         <= ST_READ;             // ��ʼ������
                                    end

                                endcase
                            end
                        end

                    endcase
                end


                ST_RSTART0:
                begin
                    sda_drive_low_r <= 1'b0;     // SDA�ͷ�Ϊ��
                    scl_drive_low_r <= 1'b0;     // SCL�ͷ�Ϊ��
                    state         <= ST_RSTART1;
                end


                ST_RSTART1:
                begin
                    sda_drive_low_r <= 1'b1;     // SCL��ʱ����SDA
                    state         <= ST_RSTART2;
                end


                ST_RSTART2:
                begin
                    scl_drive_low_r <= 1'b1;     // ����SCL

                    tx_byte       <= 8'h79;     // OV5640����ַ
                    byte_stage    <= 2'd3;      // ��ǰΪ����ַ�׶�
                    bit_cnt       <= 3'd7;      // bit7��ʼ
                    phase         <= 2'd0;      // ��λ����

                    sda_drive_low_r <= 1'b1;      // 0x79 bit7=0

                    state         <= ST_SEND;   // ���Ͷ���ַ
                end


                ST_READ:
                begin
                    case (phase)

                        2'd0:
                        begin
                            scl_drive_low_r <= 1'b0; // SCL����
                            phase         <= 2'd1; // ��һ�׶�
                        end


                        2'd1:
                        begin
                            rd_data[bit_cnt] <= sda_in; // ����SDA
                            phase            <= 2'd2;   // ��һ�׶�
                        end


                        2'd2:
                        begin
                            scl_drive_low_r <= 1'b1; // SCL����
                            phase         <= 2'd3; // ��һ�׶�
                        end


                        2'd3:
                        begin
                            if (bit_cnt != 3'd0)
                            begin
                                bit_cnt <= bit_cnt - 1'b1; // ��һbit
                                phase   <= 2'd0;            // ���¿�ʼ
                            end

                            else
                            begin
                                sda_drive_low_r <= 1'b0;     // ���ݶ�ȡ���ͷ�SDA
                                phase         <= 2'd0;      // NACK���ڿ�ʼ
                                state         <= ST_NACK;   // ������NACK
                            end
                        end

                    endcase
                end


                ST_NACK:
                begin
                    case (phase)

                        2'd0:
                        begin
                            sda_drive_low_r <= 1'b0; // SDA���ָ߱�ʾNACK
                            scl_drive_low_r <= 1'b0; // SCL����
                            phase         <= 2'd1;
                        end


                        2'd1:
                        begin
                            phase <= 2'd2;         // ����SCL��
                        end


                        2'd2:
                        begin
                            scl_drive_low_r <= 1'b1; // SCL����
                            phase         <= 2'd3;
                        end


                        2'd3:
                        begin
                            sda_drive_low_r <= 1'b1; // STOPǰ�Ȱ�SDA����
                            phase         <= 2'd0;
                            state         <= ST_STOP0;
                        end

                    endcase
                end


                ST_STOP0:
                begin
                    scl_drive_low_r <= 1'b0; // ���ͷ�SCLΪ��
                    state         <= ST_STOP1;
                end


                ST_STOP1:
                begin
                    sda_drive_low_r <= 1'b0; // SCL���ڼ��ͷ�SDA�γ�STOP
                    state         <= ST_STOP2;
                end


                ST_STOP2:
                begin
                    busy  <= 1'b0;         // ͨ�Ž���
                    done  <= 1'b1;         // ����������
                    state <= ST_IDLE;       // ���ؿ���
                end


                default:
                begin
                    state <= ST_IDLE;       // �쳣�ָ�
                end

            endcase
        end
    end
end


endmodule
