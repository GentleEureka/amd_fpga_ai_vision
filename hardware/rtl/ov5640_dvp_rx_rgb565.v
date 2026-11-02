`timescale 1ns / 1ps    // ����ʱ�䵥λ1ns������1ps

module ov5640_dvp_rx_rgb565
(
    input  wire        cam_pclk,          // OV5640����ʱ��
    input  wire        rst_n,             // ����ģ�鸴λ
    input  wire        cam_vsync,         // ֡ͬ��
    input  wire        cam_href,          // ����Ч
    input  wire [7:0]  cam_data,          // 8λDVP����

    output reg  [15:0] pixel_data,        // RGB565 16λ����
    output reg         pixel_valid,       // ������Ч����
    output reg         frame_sync,        // ֡ͬ������

    output reg  [15:0] line_pixel_count,  // ÿ����������
    output reg  [15:0] frame_line_count   // ÿ֡��Ч������
);


//============================================================
// RGB565ƴ��
//============================================================

reg       byte_phase;                    // 0����1�ֽڣ�1����2�ֽ�
reg [7:0] byte_high;                     // �ݴ�RGB565��8λ


//============================================================
// ͬ���źű��ؼ��
//============================================================

reg href_d;                              // HREF�ӳ�һ��
reg vsync_d;                             // VSYNC�ӳ�һ��


//============================================================
// ͳ��
//============================================================

reg [15:0] pixel_count_work;             // ��ǰ�����ؼ���
reg [15:0] line_count_work;              // ��ǰ֡��Ч�м���


always @(posedge cam_pclk)
begin
    if (rst_n == 1'b0)
    begin
        byte_phase       <= 1'b0;        // �ֽ���λ����
        byte_high        <= 8'd0;        // ���ֽڻ�������

        href_d           <= 1'b0;        // HREF�ӳټĴ�������
        vsync_d          <= 1'b0;        // VSYNC�ӳټĴ�������

        pixel_data       <= 16'd0;       // ������������
        pixel_valid      <= 1'b0;        // ������Ч
        frame_sync       <= 1'b0;        // ֡ͬ������

        pixel_count_work <= 16'd0;       // �����ؼ�������
        line_count_work  <= 16'd0;       // ֡������������

        line_pixel_count <= 16'd0;       // ��һ������������
        frame_line_count <= 16'd0;       // ��һ֡��������
    end

    else
    begin
        href_d  <= cam_href;             // ������һ��HREF
        vsync_d <= cam_vsync;            // ������һ��VSYNC

        pixel_valid <= 1'b0;             // Ĭ��û����������
        frame_sync  <= 1'b0;             // Ĭ��û��֡ͬ��


        //====================================================
        // VSYNC������
        //====================================================

        if ((cam_vsync == 1'b1) && (vsync_d == 1'b0))
        begin
            frame_sync <= 1'b1;          // ���֡ͬ������

            frame_line_count <=
                line_count_work;         // ������һ֡��Ч������

            line_count_work <= 16'd0;    // ��һ֡����ͳ������

            pixel_count_work <= 16'd0;   // �����ؼ�������

            byte_phase <= 1'b0;          // RGB565�����ֽڶ���
        end


        //====================================================
        // HREF�½���
        //====================================================

        else if ((cam_href == 1'b0) && (href_d == 1'b1))
        begin
            // HREF may deassert on the PCLK falling edge while the final
            // RGB565 low byte is still present for this rising-edge sample.
            // Finish that pixel before closing the line instead of dropping
            // one pixel from every row.
            if (byte_phase == 1'b1)
            begin
                pixel_data <= {byte_high, cam_data};
                pixel_valid <= 1'b1;
                line_pixel_count <= pixel_count_work + 1'b1;
            end
            else
            begin
                line_pixel_count <= pixel_count_work;
            end

            pixel_count_work <= 16'd0;   // ��һ�����¼���

            line_count_work <=
                line_count_work + 1'b1;  // ��ǰ֡��Ч����+1

            byte_phase <= 1'b0;          // ��һ�����½���RGB565�ֽڶ���
        end


        //====================================================
        // HREF��Чʱ����DVP����
        //====================================================

        else if (cam_href == 1'b1)
        begin
            if (byte_phase == 1'b0)
            begin
                byte_high <= cam_data;    // ��һ��8bit��ΪRGB565���ֽ�

                byte_phase <= 1'b1;       // ��һPCLK���յ��ֽ�
            end

            else
            begin
                pixel_data <=
                    {byte_high, cam_data}; // ����8bitƴ��16bit RGB565

                pixel_valid <= 1'b1;      // ��ǰ����һ����������

                pixel_count_work <=
                    pixel_count_work + 1'b1; // ��ǰ��������+1

                byte_phase <= 1'b0;       // ��һ���شӸ��ֽ����¿�ʼ
            end
        end


        else
        begin
            byte_phase <= 1'b0;           // ����Ч�������ֽڶ���
        end
    end
end


endmodule
