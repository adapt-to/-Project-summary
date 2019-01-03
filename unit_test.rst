==================
关于联合测试的资料整理
==================

由于之前实现PC与FPGA的通信是借助了示例中提供的工具，虽然能够实现通信，但是那样带来的弊端是十分缺乏稳定性和保密性，故基于此缺点，我决定绕过
这个中间工具，自己独立开发一套适用于与FPGA通信的代码。

为此我决定比较不同的通信模式的优劣势以及实现上的性价比

1. UART通信
==============

.. note::

    UART是一种异步收发传输器，骑其在数据发送时将并行数据转换为串行数据来传输，
    在数据接收时将接收到的串行数据转换成并行数据，可以实现全双工传输和接收。
    在FPGA开发板设计中，UART用来与PC进行通信，包括数据通信，命令和控制信息的传输。

1.1 Uart的通信协议和传输时序
--------------

 UART通信过程： 
  
  1. UART首先将接收到的并行数据转换成串行数据来传输。消息帧从一个低位起始位开始，后面是7个或8个数据位，然后是一个可用的奇偶位和一个或几个高位停止位
  #. 接收器发现开始位时它就知道数据准备发送，并尝试与发送器时钟频率同步
  #. 如果选择了奇偶校验，UART就在数据位后面加上奇偶位。奇偶位可用来帮助错误校验
  #. 在接收过程中，UART从消息帧中去掉起始位和结束位，对进来的字节进行奇偶校验，并将数据字节从串行转换成并行

传输时序图如图所示：

.. image:: ./uart.png

2. 硬件介绍
=============

AX530开发板上含有UART串口用于开发板与PC间的串口通信。串口原理图如下图所示：

.. image:: ./uart_usb.png

其中 UART_RXD为PC-->FPGA的串行数据，UART_TXD为PFGA-->PC的串行数据

.. warning::

  USB转UART需要安装相应的驱动，这些驱动程序 允许CP2102 USB-UART桥接设备在通信应用软件显示为一个COM端
  驱动是否安装成功，可以在设备管理器下查看

3. 程序模块设计
============

针对本项目，并且基于示例程序，我设计了适合本项目的用于通信的UART程序模块，共分为3个部分：

    1. **时钟产生程序** ：用于产生发送数据的时钟频率，需要针对相应的波特率做修改
    2. **uart串口发送程序** ：通过串口在时钟到来时将数据发送出去
    3. **uart串口发送测试程序** ：用于测试串口发送的数据是否正确

3.1 时钟产生程序
----------------
时钟产生程序verilog代码::

    //////////////////////////////////////////////////////////////////////////////////
    // Module Name:    clkdiv  
    ////////////////////////////////////////////////////////////////////////////////// 
    module clkdiv(clk50, rst_n, clkout); 
    input clk50;              //系统时钟 50MHz
    input rst_n;              //收入复位信号 
    output clkout;            //采样时钟输出 
    reg clkout; 
    reg [15:0] cnt; 
 
    /////分频进程, 50Mhz的时钟28分频//////////
    /////50Mhz÷(16*波特率)=分频数/////////////
    /////50M÷(16*115200)=27.1267≈28/////////
    /////波特率：每秒传输的数据个数/////////////
    always @(posedge clk50 or negedge rst_n)
        begin
        if (!rst_n) begin // 初始化+给初值
                clkout <=1'b0;
                cnt<=0;   
            end
            else if(cnt == 16'd13) begin
                clkout <= 1'b1;     
                cnt <= cnt + 16'd1;   
            end
            else if(cnt == 16'd27) begin // 因为是从0开始计数，所以此处为27
                clkout <= 1'b0;
                cnt <= 16'd0;
            end
            else begin
                cnt <= cnt + 16'd1;
            end
        end
    endmodule

对于程序中提到的波特率，可由下图确定：

.. imange:: ./bote.png

右图可看出，波特率从4800bps/s开始，之后的波特率都是4800的倍数，以此类推。

串口通讯，主从双方波特率必须一致才能有效传递数据，9600是使用最多的一个波特率，所以默认状态下一般都是设置成9600。
对于串口通讯而言，波特率越高，有效传输距离越小，而9600这个波特率，兼顾了传输速度和常用传输距离，一般为10米左右，最大不超过20米。
如果为115200，一般距离不超过5米。常用2~3米左右。
上述采用波特率为115200进行传输，在保证了传输距离的情况下尽可能增加传输速度

3.2 uart串口发送程序
----------------

串口发送程序::

    ////////////////////////////////////////////////////////////////////////////////// 
    // Module Name: uarttx  
    // 说明：16个clock上升沿发送一个bit(即8位二进制数据)
    //      16个clock时钟中的操作：一个起始位 + 8个数据位 + 一个奇偶校验位 + 一个停止位 + 剩余的空缺位
    ////////////////////////////////////////////////////////////////////////////////// 
    
    module uarttx(clk, rst_n, datain, wrsig, idle, tx); 
    
    input clk;                //UART时钟，由时钟产生模块给出 
    input rst_n;              //系统复位
    input [7:0] datain;       //需要发送的数据 
    input wrsig;              //发送命令，上升沿有效 
    output idle;              //线路状态指示，高为线路忙，低为线路空闲 
    output tx;                //发送数据信号 
    
    reg idle, tx; 
    reg send; 
    reg wrsigbuf, wrsigrise; 
    reg presult; 
    reg[7:0] cnt;             //计数器 
    parameter paritymode = 1'b0; 
    
    //////////////////////////////////////////////////////////////// 
    //检测发送命令wrsig的上升沿 
    //////////////////////////////////////////////////////////////// 
    
    always @(posedge clk) 
    begin
        wrsigbuf <= wrsig;
        wrsigrise <= (~wrsigbuf) & wrsig;
    end 
    
    //////////////////////////////////////////////////////////////// 
    //启动串口发送程序 
    //////////////////////////////////////////////////////////////// 
    
    always @(posedge clk) 
    begin
    if (wrsigrise && (~idle))  //当发送命令有效且线路为空闲时，启动新的数据发送进程
        begin
            send <= 1'b1;   
        end   
        else if(cnt == 8'd168)      //一帧数据发送结束
        begin
            send <= 1'b0;
        end 
    end 
    
    //////////////////////////////////////////////////////////////// 
    //串口发送程序, 16个时钟发送一个bit 
    //////////////////////////////////////////////////////////////// 
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            tx <= 1'b0;          
            idle <= 1'b0;
            cnt <= 8'd0;    
            presult <= 1'b0;   
        end    
        
        else if(send == 1'b1)  
        begin
            case(cnt)                 //产生起始位
                8'd0: 
                    begin
                        tx <= 1'b0;  //给入低位触发，即将传输数据     
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd16:
                    begin          
                        tx <= datain[0];    //发送数据0位          
                        presult <= datain[0]^paritymode;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;
                    end     
                8'd32:
                    begin 
                        tx <= datain[1];    //发送数据1位          
                        presult <= datain[1]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd48:
                    begin          
                        tx <= datain[2];    //发送数据2位          
                        presult <= datain[2]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd64: 
                    begin          
                        tx <= datain[3];    //发送数据3位          
                        presult <= datain[3]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd80: 
                    begin           
                        tx <= datain[4];    //发送数据4位          
                        presult <= datain[4]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd96: 
                    begin
                        tx <= datain[5];    //发送数据5位          
                        presult <= datain[5]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd112: 
                    begin
                        tx <= datain[6];    //发送数据6位          
                        presult <= datain[6]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd128: 
                    begin           
                        tx <= datain[7];    //发送数据7位          
                        presult <= datain[7]^presult;          
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd144: 
                    begin          
                        tx <= presult;      //发送奇偶校验位          
                        presult <= datain[0]^paritymode;          
                        idle <= 1'b1;
                        cnt <= cnt + 8'd1;     
                    end     
                8'd160: 
                    begin 
                        tx <= 1'b1;         //发送停止位                      
                        idle <= 1'b1;          
                        cnt <= cnt + 8'd1;     
                    end     
                8'd168: 
                    begin  
                        tx <= 1'b1;                       
                        idle <= 1'b0;       //一帧数据发送结束          
                        cnt <= cnt + 8'd1;     
                    end     
                default:
                    begin          
                        cnt <= cnt + 8'd1;  //cnt只要不等于16的倍数就自加1，即是16个时钟上升沿对应发送一位数据    
                    end    
            endcase   
        end   
        else  
        begin     
            tx <= 1'b1;  // 一帧数据传完，置高位  
            cnt <= 8'd0; // 一帧传完又重置cnt
            idle <= 1'b0; // 线路状态指示为低，表示线路空闲
        end 
    end 
endmodule 


3.3 uart串口发送测试程序
----------------
