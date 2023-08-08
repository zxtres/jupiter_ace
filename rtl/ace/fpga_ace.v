`timescale 1ns / 1ps
`default_nettype none

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    20:06:40 03/19/2011 
// Design Name: 
// Module Name:    jace_en_fpga 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

module jupiter_ace (
  input wire clkram,
	input wire clk65,
	input wire reset_n,
	input wire ear,
	output wire [7:0] filas,
	input wire [4:0] columnas,
	output wire r,
	output wire g,
	output wire b,
	output wire hsync,
	output wire vsync,
  output wire mic,
  output wire spk,
  output wire [7:0] ay_a,
  output wire [7:0] ay_b,
  output wire [7:0] ay_c,
  //----------------------
  output wire [20:0] ext_sram_addr,
  output wire [7:0] data_to_sram,
  input wire [7:0] data_from_sram,
  output wire sram_we_n,
  output wire sram_oe_n
	);
	
	// Los buses del Z80
	wire [7:0] DinZ80;
	wire [7:0] DoutZ80;
	wire [15:0] AZ80;
	
  // Señales de control, direccion y datos de parte de todas las memorias
	wire iorq_n, mreq_n, int_n, rd_n, wr_n, wait_n;
  wire rom_enable, sram_enable, cram_enable, uram_enable, xram_enable, eram_enable, data_from_jace_oe, oe_n_ay;
  wire [7:0] dout_rom, dout_sram, dout_cram, dout_uram, dout_xram, dout_eram, data_from_jace, dout_ay;
  wire [7:0] sram_data, cram_data, attrram_data;
  wire [9:0] sram_addr, cram_addr;
    
  // Señales para la implementaciï¿½n de la habilitaciï¿½n de escritura en ROM
  wire enable_write_to_rom;
  wire [7:0] dout_modulo_enable_write;
  wire modulo_enable_write_oe;

	// Copia del bus de direcciones para las filas del teclado
  assign filas = AZ80[15:8];
  
  assign data_to_sram = DoutZ80;
  assign sram_oe_n = ~(uram_enable | xram_enable | eram_enable) | rd_n;
  assign sram_we_n = ~(uram_enable | xram_enable | eram_enable) | wr_n;
  assign ext_sram_addr = {5'b00000, AZ80};

  // Multiplexor para asignar un valor al bus de datos de entrada del Z80
  assign DinZ80 = (rom_enable == 1'b1)?        dout_rom :
                  (sram_enable == 1'b1)?       dout_sram :
                  (cram_enable == 1'b1)?       dout_cram :
                  (uram_enable == 1'b1)?       data_from_sram : //dout_uram :
                  (xram_enable == 1'b1)?       data_from_sram : //dout_xram :
                  (eram_enable == 1'b1)?       data_from_sram : //dout_eram :
                  (modulo_enable_write_oe == 1'b1)? dout_modulo_enable_write :
                  (data_from_jace_oe == 1'b1)? data_from_jace :
                  (oe_n_ay == 1'b0)?           dout_ay   :
                                               sram_data | cram_data;  // By default, this is what the data bus sees


  // Gestión del color (proyecto según ETI ABRIL 1984)
  // http://www.jupiter-ace.co.uk/hardware_colour_board.html  
  reg [5:0] attr_latch = 6'b000111;   // fondo negro, letras blancas al resetear
  always @(posedge clk65) begin
    if (reset_n == 1'b0)
      attr_latch <= 6'b000111;      
    else if (AZ80 == 16'h2700 && mreq_n == 1'b0 && wr_n == 1'b0 && DoutZ80[7] == 1'b1)
      attr_latch <= {DoutZ80[6:4], DoutZ80[2:0]};
  end 

	// Memoria del equipo
	ram1k_dualport sram (
       .clk(clkram),
       .ce(sram_enable),
       .a1(AZ80[9:0]),
	   .a2(sram_addr),
	   .din(DoutZ80),
	   .dout1(dout_sram),
       .dout2(sram_data),
	   .we(~wr_n)
		);
		
	// Se direcciona en paralelo a la Screen RAM
	ram1k_dualport attrram (
    .clk(clkram),
    .ce(sram_enable),
    .a1(AZ80[9:0]),
	  .a2(sram_addr),
	  .din({2'b00,attr_latch}),
	  .dout1(),
    .dout2(attrram_data),
	  .we(~wr_n)
		);

	ram1k_dualport cram (
       .clk(clkram),
       .ce(cram_enable),
       .a1(AZ80[9:0]),
	   .a2(cram_addr),
	   .din(DoutZ80),
	   .dout1(dout_cram),
       .dout2(cram_data),
	   .we(~wr_n)
		);
		
//	ram1k uram(
//		.clk(clkram),
//        .ce(uram_enable),
//        .a(AZ80[9:0]),
//        .din(DoutZ80),
//        .dout(dout_uram),
//        .we(~wr_n)
//		);
		
//	ram16k xram(
//		.clk(clkram),
//        .ce(xram_enable),
//        .a(AZ80[13:0]),
//        .din(DoutZ80),
//        .dout(dout_xram),
//        .we(~wr_n)
//		);

//	ram32k eram(
//		.clk(clkram),
//        .ce(eram_enable),
//        .a(AZ80[14:0]),
//        .din(DoutZ80),
//        .dout(dout_eram),
//        .we(~wr_n)
//		);

	/* La ROM */
	rom the_rom(
	   .clk(clkram),
       .ce(rom_enable),
	   .a(AZ80[12:0]),
       .din(DoutZ80),
	   .dout(dout_rom),
       .we(~wr_n & enable_write_to_rom)
		);
	
	/* La CPU */
	reg enable_cpu_p = 1'b0;
	reg enable_cpu_n = 1'b0;
	always @(posedge clk65)
	  enable_cpu_p <= ~enable_cpu_p;
	always @(negedge clk65)
	  enable_cpu_n <= ~enable_cpu_n;
	  
	tv80n cpu(
		// Outputs
		.m1_n(), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(), .A(AZ80), .do(DoutZ80),
		// Inputs
		.di(DinZ80), .reset_n(reset_n), .clk(clk65), .cep(enable_cpu_p), .cen(enable_cpu_n), .wait_n(wait_n), .int_n(int_n), .nmi_n(1'b1), .busrq_n(1'b1)
        );
        
  jace_logic todo_lo_demas (
    .clk(clk65),
    // CPU interface
    .reset_n(reset_n),
    .cpu_addr(AZ80),
    .mreq_n(mreq_n),
    .iorq_n(iorq_n),
    .rd_n(rd_n),
    .wr_n(wr_n),
    .data_from_cpu(DoutZ80),
    .data_to_cpu(data_from_jace),
    .data_to_cpu_oe(data_from_jace_oe),
    .wait_n(wait_n),
    .int_n(int_n),
    // CPU-RAM interface
    .rom_enable(rom_enable),
    .sram_enable(sram_enable),
    .cram_enable(cram_enable),
    .uram_enable(uram_enable),
    .xram_enable(xram_enable),
    .eram_enable(eram_enable),
    // Screen RAM and Char RAM interface
    .screen_addr(sram_addr),
    .screen_data(sram_data),
    .char_addr(cram_addr),
    .char_data(cram_data),
    .attr_data(attrram_data),
    // Devices
    .kbdcols(columnas),
    .ear(ear),
    .spk(spk),
    .mic(mic),
    .r(r),
    .g(g),
    .b(b),
    .hsync_pal(hsync),
    .vsync_pal(vsync)
  );

  reg [2:0] divclk65;
  wire enay = (divclk65 == 2'b00);
  always @(posedge clk65)
    divclk65 <= divclk65 + 1;
    
///////////////////////////////////
// AY-3-8912 SOUND
///////////////////////////////////
  // BDIR BC2 BC1 MODE
  //   0   1   0  inactive
  //   0   1   1  read        rd FFFD   F6
  //   1   1   0  write       wr BFFD   F6
  //   1   1   1  address     wr FFFD   F5

  wire portBFFD = AZ80[15] && AZ80[1:0]==2'b01;
  wire portFFFD = AZ80[15] && AZ80[14] && AZ80[1:0]==2'b01;

  wire bdir = !iorq_n && ( ( (portBFFD || portFFFD) && !wr_n) );
  wire bc1  = !iorq_n && ( portFFFD && (!rd_n || !wr_n) );    
    
  ay_3_8192 psg (
    .clk(clk65),
    .clken(enay),
	  .rst_n(reset_n),
	  .a8(1'b1),
	  .bdir(bdir),
	  .bc1(bc1),
	  .bc2(1'b1),
	  .din(DoutZ80),
	  .dout(dout_ay),
	  .oe_n(oe_n_ay),
	  .channel_a(ay_a),
	  .channel_b(ay_b),
	  .channel_c(ay_c),
    .port_a_din(8'h00),
	  .port_a_dout(),
	  .port_a_oe_n()
  );
        
  io_write_to_rom modulo_habilitador_escrituras (
    .clk(clk65),
    .a(AZ80),
    .iorq_n(iorq_n),
    .rd_n(rd_n),
    .wr_n(wr_n),
    .din(DoutZ80),
    .dout(dout_modulo_enable_write),
    .dout_oe(modulo_enable_write_oe),
    .enable_write_to_rom(enable_write_to_rom)
  );
  
endmodule
