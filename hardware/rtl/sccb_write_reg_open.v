`timescale 1ns / 1ps    // ����ʱ�䵥λ1ns������1ps

module sccb_write_reg_open
(
    input  wire        clk,          // 100MHz����ʱ��
    input  wire        rst_n,        // �ߵ�ƽ��������
    input  wire        start,        // ����һ��д����
    input  wire [15:0] reg_addr,     // OV5640 16λ�Ĵ�����ַ
    input  wire [7:0]  wr_data,      // Ҫд�������

    output reg         busy,         // SCCBģ��æ
    output reg         done,         // һ��д�������
    output reg         nack_error,   // NACK����

    input  wire        scl_in,       // shared SCCB SCL level
    input  wire        sda_in,       // shared SCCB SDA level

    output wire        scl_drive_low,
    output wire        sda_drive_low
);


//============================================================
// ��©���
//============================================================

reg scl_drive_low_r;                   // SCL�������Ϳ���
reg sda_drive_low_r;                   // SDA�������Ϳ���

assign scl_drive_low = scl_drive_low_r;
assign sda_drive_low = sda_drive_low_r;


//============================================================
// 400kHz tick
//============================================================

reg [7:0] div_cnt;                   // 0~249����
reg       tick;                      // 2.5us����


always @(posedge clk)
begin
    if (rst_n == 1'b0)
    begin
        div_cnt <= 8'd0;             // ��Ƶ��������
        tick    <= 1'b0;             // tick����
    end

    else
    begin
        if (div_cnt == 8'd249)
        begin
            div_cnt <= 8'd0;         // ���¼���
            tick    <= 1'b1;         // ����tick
        end

        else
        begin
            div_cnt <= div_cnt + 1'b1; // ��������
            tick    <= 1'b0;           // ����ʱ��Ϊ0
        end
    end
end


//============================================================
// ״̬��
//============================================================

localparam ST_IDLE   = 4'd0;         // ����
localparam ST_START0 = 4'd1;         // START�׶�0
localparam ST_START1 = 4'd2;         // START�׶�1
localparam ST_SEND   = 4'd3;         // ����8λ
localparam ST_ACK    = 4'd4;         // �ȴ�ACK
localparam ST_STOP0  = 4'd5;         // STOP�׶�0
localparam ST_STOP1  = 4'd6;         // STOP�׶�1
localparam ST_STOP2  = 4'd7;         // STOP�׶�2

reg [3:0] state;                     // ��ǰ״̬

reg [1:0] phase;                     // ÿbit��4��ʱ��
reg [2:0] bit_cnt;                   // bit����
reg [7:0] tx_byte;                   // ��ǰ�����ֽ�
reg [2:0] byte_stage;                // ��ǰ���ͽ׶�

reg [15:0] reg_addr_latched;         // ����Ĵ�����ַ
reg [7:0]  wr_data_latched;          // ����д������


always @(posedge clk)
begin
    if (rst_n == 1'b0)
    begin
        state            <= ST_IDLE; // �ص�����
        phase            <= 2'd0;    // ��λ����
        bit_cnt          <= 3'd7;    // ��bit7��ʼ

        tx_byte          <= 8'd0;    // ������������
        byte_stage       <= 3'd0;    // �׶�����

        reg_addr_latched <= 16'd0;   // ��ַ����
        wr_data_latched  <= 8'd0;    // ��������

        busy             <= 1'b0;    // ����
        done             <= 1'b0;    // δ���
        nack_error       <= 1'b0;    // �޴���

        scl_drive_low_r <= 1'b0;    // �ͷ�SCL
        sda_drive_low_r <= 1'b0;    // �ͷ�SDA
    end

    else
    begin
        done <= 1'b0;                // doneĬ��ֻ����һ��clk


        if (state == ST_IDLE)
        begin
            busy          <= 1'b0;   // ����
            scl_drive_low_r <= 1'b0;   // SCL��
            sda_drive_low_r <= 1'b0;   // SDA��
            phase         <= 2'd0;   // ��λ����

            if (start == 1'b1)
            begin
                busy             <= 1'b1;       // ��ʼͨ��
                nack_error       <= 1'b0;       // �������

                reg_addr_latched <= reg_addr;   // �����ַ
                wr_data_latched  <= wr_data;    // ��������

                state            <= ST_START0;  // ����START
            end
        end


        else if (tick == 1'b1)
        begin
            case (state)

                ST_START0:
                begin
                    scl_drive_low_r <= 1'b0;      // SCL���ָ�
                    sda_drive_low_r <= 1'b1;      // SDA�ߵ����γ�START
                    state         <= ST_START1; // ��һ�׶�
                end


                ST_START1:
                begin
                    scl_drive_low_r <= 1'b1;      // ����SCL

                    tx_byte       <= 8'h78;      // OV5640д��ַ
                    byte_stage    <= 3'd0;       // ������ַ�׶�
                    bit_cnt       <= 3'd7;       // ��bit7��ʼ
                    phase         <= 2'd0;       // ��λ����

                    sda_drive_low_r <= 1'b1;       // 0x78 bit7=0

                    state         <= ST_SEND;    // ��ʼ����
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
                            scl_drive_low_r <= 1'b1; // ����SCL
                            phase         <= 2'd3; // ��һ�׶�
                        end


                        2'd3:
                        begin
                            if (bit_cnt != 3'd0)
                            begin
                                bit_cnt <= bit_cnt - 1'b1; // ��һbit

                                if (tx_byte[bit_cnt - 1'b1] == 1'b0)
                                    sda_drive_low_r <= 1'b1; // bit=0
                                else
                                    sda_drive_low_r <= 1'b0; // bit=1

                                phase <= 2'd0;              // ���¿�ʼ
                            end

                            else
                            begin
                                sda_drive_low_r <= 1'b0;     // �ͷ�SDA
                                phase         <= 2'd0;      // ACK��ʼ
                                state         <= ST_ACK;    // �ȴ�ACK
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
                            phase         <= 2'd1; // ׼������ACK
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
                            phase <= 2'd0;         // ��һ�׶����¿�ʼ

                            if (nack_error == 1'b1)
                            begin
                                sda_drive_low_r <= 1'b1; // STOPǰ����SDA
                                state         <= ST_STOP0;
                            end

                            else
                            begin
                                case (byte_stage)

                                    3'd0:
                                    begin
                                        tx_byte    <= reg_addr_latched[15:8]; // ��ַ��8λ
                                        byte_stage <= 3'd1;                   // ��һ�׶�
                                        bit_cnt    <= 3'd7;                   // bit7��ʼ

                                        if (reg_addr_latched[15] == 1'b0)
                                            sda_drive_low_r <= 1'b1;            // bit7=0
                                        else
                                            sda_drive_low_r <= 1'b0;            // bit7=1

                                        state <= ST_SEND;                     // ���͵�ַ���ֽ�
                                    end


                                    3'd1:
                                    begin
                                        tx_byte    <= reg_addr_latched[7:0]; // ��ַ��8λ
                                        byte_stage <= 3'd2;                  // ��һ�׶�
                                        bit_cnt    <= 3'd7;                  // bit7��ʼ

                                        if (reg_addr_latched[7] == 1'b0)
                                            sda_drive_low_r <= 1'b1;           // bit7=0
                                        else
                                            sda_drive_low_r <= 1'b0;           // bit7=1

                                        state <= ST_SEND;                    // ���͵͵�ַ
                                    end


                                    3'd2:
                                    begin
                                        tx_byte    <= wr_data_latched;       // ����д������
                                        byte_stage <= 3'd3;                  // ���׶�
                                        bit_cnt    <= 3'd7;                  // bit7��ʼ

                                        if (wr_data_latched[7] == 1'b0)
                                            sda_drive_low_r <= 1'b1;           // bit7=0
                                        else
                                            sda_drive_low_r <= 1'b0;           // bit7=1

                                        state <= ST_SEND;                    // ��������
                                    end


                                    3'd3:
                                    begin
                                        sda_drive_low_r <= 1'b1;              // STOPǰ����SDA
                                        state         <= ST_STOP0;           // ����ͨ��
                                    end


                                    default:
                                    begin
                                        sda_drive_low_r <= 1'b1;              // �쳣ʱ׼��STOP
                                        state         <= ST_STOP0;           // ����ͨ��
                                    end

                                endcase
                            end
                        end

                    endcase
                end


                ST_STOP0:
                begin
                    sda_drive_low_r <= 1'b1; // SDA���ֵ�
                    scl_drive_low_r <= 1'b0; // SCL������
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
                    done  <= 1'b1;         // д�����
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
