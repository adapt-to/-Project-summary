`timescale 1ns / 1ps
`define		clock_period  20
////////////////////////////////////////////////////////////////////////////////// 
//随机4值电压触发 (这是顶层文件还是testbench文件？？？)还是顶层文件和testbench合在一起的
////////////////////////////////////////////////////////////////////////////////// 
module random_v(
     input clk,            //fpga clock 
	  //input rst_n,           // 复位信号
	  //input sel,
	  //reg [1:0] sel, //随机选择信号
     
	  output da1_clk,             //DA1 时钟信号
     output da1_wrt,             //DA1 数据写信号
     output [13:0] da1_data,       //DA1 data
     output da2_clk,             //DA2 时钟信号
     output da2_wrt,            //DA2 数据写信号
     output [13:0] da2_data       //DA2 data 
    ); 
 


reg [9:0] rom_addr; 
wire [13:0] rom_data; 
wire clk_50; 
wire clk_125; 
wire [7:0] sel; // 我只用两位
 
assign da1_clk=clk_125; 
assign da1_wrt=clk_125;
assign da1_data=rom_data; 
 
assign da2_clk=clk_125; 
assign da2_wrt=clk_125; 
assign da2_data=rom_data; 
 
//DA output sin waveform 
always @(posedge clk_125) // or negedge rst_n
begin
      //if(!rst_n) begin
		   // rom_addr <= 10'd0;
		//end
		//else begin
		
			if(sel[4:3] == 2'b00) begin
				if(10'd0 <= rom_addr <= 10'd255) begin
				  rom_addr <= rom_addr + 1'b1 ;       //rom_addr <= rom_addr + 1'b1 ;  //一个周期采样点为 1024,输出正选波频率 125/1024=122Khz    
				end
				else begin
				 rom_addr <= 10'd0;
				end 
			end
			
			else if(sel[4:3] == 2'b01) begin
			   if(10'd256 <= rom_addr <= 10'd511) begin
				  rom_addr <= rom_addr + 1'b1; //rom_addr <= rom_addr + 4 ;  //一个周期采样点为 256,输出正选波频率 125/256=488Khz    
				end
				else begin
				 rom_addr <= 10'd256;
				end 
			end
			
			else if(sel[4:3] ==2'b01) begin
			   if(10'd512 <= rom_addr <= 10'd767) begin
				  rom_addr <= rom_addr + 1'b1;  //rom_addr <= rom_addr + 128 ; //一个周期采样点为 8,输出正选波频率 125/1024=15.6Mhz
				end
				else begin
				 rom_addr <= 10'd512;
				end 
			end
			
			else begin
			   if(10'd768 <= rom_addr <= 10'd1023) begin
				  rom_addr <= rom_addr + 1'b1;
				end
				else begin
				 rom_addr <= 10'd768;
				end 
			end
			
		//end            
end


wire div_out;
div_f	div_f_inst(
		.clk(clk),
		//.rst_n(rst_n),
		.div_out(div_out)
		);

wire qq;
sample sample_inst(
			.d(clk_125),
			.clk(div_out),
			//.rst_n(rst_n),
			.qq(qq)
					);
					
RanGen RanGen_inst(
   .clk (clk),
	.seed(qq),
	.rand_num (sel)
	
);
 
ROM ROM_inst (
  .clock   (clk_125), // input clka 
  .address (rom_addr), // input [8 : 0] addra   
  .q       (rom_data) // output [7 : 0] douta 
); 
 
pll pll_inst( 
  .areset  (1'b0),
  .inclk0  (clk),
  .c0      (clk_50), 
  .c1      (clk_125),
  .locked  ()  
); 
 
 
initial begin  
//rst_n = 1'b0;
//#(`clock_period*200);
//rst_n = 1'b1;
#(`clock_period*3000);
$stop;
	end
 
 endmodule