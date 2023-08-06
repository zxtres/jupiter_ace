`timescale 1ns / 1ps
`default_nettype none
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    17:18:12 11/07/2015 
// Design Name: 
// Module Name:    tld_jace_spartan6 
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
module tld_jace_color_ay (
   input wire clk50mhz,

   output wire [5:0] vga_r,
   output wire [5:0] vga_g,
   output wire [5:0] vga_b,
   output wire vga_hs,
   output wire vga_vs,
   input wire ear,
   inout wire clkps2,
   inout wire dataps2,
   output wire audio_out_left,
   output wire audio_out_right,
   
   output wire [19:0] sram_addr,
   inout wire [15:0] sram_data,
   output wire sram_we_n,
   output wire sram_oe_n,
   output wire sram_ub_n,
   output wire sram_lb_n,
   
   input wire joy_data,
   output wire joy_clk,
   output wire joy_load_n,
   
   output wire i2s_bclk,
   output wire i2s_lrclk,
   output wire i2s_dout,  
   
   output wire sd_cs_n,    
   output wire sd_clk,     
   output wire sd_mosi,    
   input wire sd_miso,
   
   output wire dp_tx_lane_p,
   output wire dp_tx_lane_n,
   input wire  dp_refclk_p,
   input wire  dp_refclk_n,
   input wire  dp_tx_hp_detect,
   inout wire  dp_tx_auxch_tx_p,
   inout wire  dp_tx_auxch_tx_n,
   inout wire  dp_tx_auxch_rx_p,
   inout wire  dp_tx_auxch_rx_n
  );
    
  wire clkram; // 26 MHz to clock internal RAM/ROM
  wire clk65;  // 6.5MHz main frequency Jupiter ACE
  wire clkcpu; // CPU CLK
  wire clkvideo;
  wire clk100; // para el reloj PAL/NTSC
  wire locked;
  
  wire kbd_reset;
  wire return_to_zx;
  wire [7:0] kbd_rows;
  wire [4:0] kbd_columns;
  wire r_ace, g_ace, b_ace;  // color de 1 bit.
  wire pal_hsync, pal_vsync; // sincronismo separado
  wire mic,spk;
  wire [7:0] ay_a, ay_b, ay_c;
  wire poweron_reset;  
  
  wire disable_scanlines, video_output;
  wire vi_disable_scanlines, vi_video_output;
  wire [1:0] monochrome_sel;

  wire [20:0] jace_sram_addr;
  wire jace_sram_we_n, jace_sram_oe_n;
  wire [7:0] jace_sram_data_to_chip;
  wire [7:0] jace_sram_data_from_chip;
  
  relojes_mmcm los_relojes (
   .CLK_IN1(clk50mhz),
   .CLK_OUT1(clk100),     // para generar los reslojes PAL/NTSC
   .CLK_OUT2(clkram),     // for driving synch RAM and ROM = 26 MHz
   .CLK_OUT3(clkvideo),   // video clock X 2, para el framescaler
   .CLK_OUT4(clk65),      // video clock = 6.5 MHz
   .locked  (locked)      // hasta que el reloj no sea estable, ZX3W debe estar parado, y si es posible, el core también
  );
  
  jupiter_ace the_core (
   .clkram(clkram),
   .clk65(clk65),
   .reset_n(kbd_reset & ~poweron_reset & locked),  // el Jupiter ACE se resetea por tres fuentes distintas
   .ear(ear),
   .filas(kbd_rows),             // Esto viene del módulo de teclado, donde se implementa
   .columnas(kbd_columns),       // la matriz de 5x8 teclas
   .r(r_ace),                 //
   .g(g_ace),                 // Salida de video en color, 1 bit por color primario (ETI 1984)
   .b(b_ace),                 // 
   .hsync(pal_hsync),
   .vsync(pal_vsync),
   .mic(mic),              // Comportamiento parecido a MIC y SPK del Spectrum
   .spk(spk),              // MIC lleva la señal de SAVE al cassette.
   .ay_a(ay_a),      //
   .ay_b(ay_b),      // Añadido propio: un AY-3-8912 en los puertos del 128K, para que funcione la demo Old School de MAT/ESI
   .ay_c(ay_c),      //
   .ext_sram_addr(jace_sram_addr),              //
   .data_to_sram(jace_sram_data_to_chip),       // La memoria de usuario básica (1K) y la memoria
   .data_from_sram(jace_sram_data_from_chip),   // extendida (48K) se cogen de la memoria SRAM
   .sram_we_n(jace_sram_we_n),                  // externa. En total, este Jupiter ACE tiene 51K de RAM
   .sram_oe_n(jace_sram_oe_n)                   // La memoria de caracteres y de patrones se implementa con BRAM
  );

  keyboard_for_ace the_keyboard (
   .clk(clk65),
   .poweron_reset(poweron_reset),
   .clkps2(clkps2),
   .dataps2(dataps2),
   .rows(kbd_rows),
   .columns(kbd_columns),
   .kbd_reset(kbd_reset),
   .kbd_nmi(),
   .kbd_mreset(return_to_zx),                   // señal a 1 para indicar un reseteo maestro para volver al Spectrum
   .vi_video_output(vi_video_output),           // valor inicial que debe tener video_output
   .vi_disable_scanlines(vi_disable_scanlines), // valor inicial que debe tener la opción de disable_scanlines
   .video_output(video_output),          // valor actual de video_output
   .monochrome_sel(monochrome_sel),      // valor actual de monochrome_sel
   .disable_scanlines(disable_scanlines) // valor actual de disable_scanlines       
  );
 
 // Conversión de las señales de audio del core a valores de 16 bits ca2
 // En este caso usamos la mitad positiva del rango (0000 a 7FFF)
 //////////////////////////////////////////////////////////////////////////////
  reg [15:0] audio_l_del_core, audio_r_del_core;
  reg [15:0] audio_basico;
  always @* begin
    audio_basico = {3'b000, {3{spk}}, {3{ear}}, {7{mic}} };
    audio_l_del_core = audio_basico + {3'b000, ay_a, ay_a[7:3]} + {3'b000, ay_c, ay_c[7:3]};
    audio_r_del_core = audio_basico + {3'b000, ay_b, ay_b[7:3]} + {3'b000, ay_c, ay_c[7:3]};  
  end
//////////////////////////////////////////////////////////////////////////////

  // Conexión del core al ZX3W.
  zxtres_wrapper #(.HSTART(80), .VSTART(31), .CLKVIDEO(13), .INITIAL_FIELD(0)) scaler (
  .clkvideo(clkvideo),          // Reloj de video (debe estar en torno a los 14 MHz, porque 
  .enclkvideo(1'b1),            // debe dar un tick por cada pixel de pantalla PAL)
  .clkpalntsc(clk100),          // Reloj de 100 MHz proveniente del MMCM
  .reset_n(locked),             // El módulo PLL o MCMM que genera los relojes debería generar una 
                                // señal "locked" que vale 1 cuando el reloj es estable, 
                                // y 0 cuando no lo está. Conéctala aquí.
  .reboot_fpga(return_to_zx),   // Señal generada por el teclado. Vale 1 para indicar reboot de la FPGA 
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .sram_addr_in(jace_sram_addr),                     // Bus de direcciones proveniente del core (el Jupiter ACE)
  .sram_we_n_in(jace_sram_we_n),                     // Señal de escritura proveniente del core 
  .sram_oe_n_in(jace_sram_oe_n),                     // Señal de habilitación de lectura proveniente del core
  .sram_data_from_chip(jace_sram_data_from_chip),    // Datos que vienen del chip de SRAM, de salida para el core
  .sram_data_to_chip(jace_sram_data_to_chip),        // Datos que vienen del core, de entrada, para el chip SRAM
  .sram_addr_out(sram_addr),                         // Bus de direcciones que se conecta directamente a la SRAM
  .sram_we_n_out(sram_we_n),                         // Señal de escritura que se conecta directamente a la SRAM
  .sram_oe_n_out(sram_oe_n),                         // Señal de habilitación de lectura que se conecta directamente a la SRAM
  .sram_ub_n_out(sram_ub_n),                         // Señales de selección del bus de la SRAM
  .sram_lb_n_out(sram_lb_n),                         //
  .sram_data(sram_data),                             // Bus de datos de 16 bits conectado a la SRAM
  .poweron_reset(poweron_reset),                     // Señal de reset (nivel alto) de entrada para el core 
  .config_vga_on(vi_video_output),                   // a 1 para indicar que inicialmente hay que poner el core en modo VGA. Va para el módulo de teclado
  .config_scanlines_off(vi_disable_scanlines),       // a 1 para indicar que hay que deshabilitar las scanlines. Va para el módulo de teclado
///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .video_output_sel(video_output),          // Señal que viene del módulo de teclado, para conmutar entre PAL y VGA
  .disable_scanlines(disable_scanlines),    // Señal que viene del módulo de teclado, para poner/quitar scanlines
  .monochrome_sel(monochrome_sel),          // Señal que viene del módulo de teclado, para cambiar el modo monocromático
  .interlaced_image(1'b0),                  // La imagen del Jupiter ACE no es entrelazada
  .ad724_modo(1'b0),                        // Se genera un reloj de color PAL (17.74 MHz)
  .ad724_clken(1'b0),                       // De momento, no usaremos el reloj PAL generado en la FPGA (aunque generar, se genera)
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ri(r_ace),                            // Señal de salida del Jupiter ACE. Originalmente es blanco y negro
  .gi(g_ace),                            // pero este ACE tiene integrado el módulo de color ETI 1984, que 
  .bi(b_ace),                            // da 1 bit por cada color primario.
  .hsync_ext_n(pal_hsync),               // Sincronismos horizontal y vertical
  .vsync_ext_n(pal_vsync),               // por separado
  .csync_ext_n(pal_hsync & pal_vsync),   // El sincronismo compuesto se forma de forma muy sencilla
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .audio_l(audio_l_del_core),            // Entrada de audio
  .audio_r(audio_r_del_core),            // 16 bits, PCM, ca2
  .i2s_bclk(i2s_bclk),                   // 
  .i2s_lrclk(i2s_lrclk),                 // Salida hacia el módulo I2S
  .i2s_dout(i2s_dout),                   //
  .sd_audio_l(audio_out_left),           // Salida de 1 bit desde
  .sd_audio_r(audio_out_right),          // los conversores sigma-delta
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ro(vga_r),           // Salida de 6 bits directas
  .go(vga_g),           // a los pines del monitor VGA
  .bo(vga_b),           // 
  .hsync(vga_hs),       // Lo mismo, pero para los sincronismos
  .vsync(vga_vs),       // horizontal y vertical.
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .joy_data(joy_data),          // Aunque este core no usa el joystick
  .joy_latch_megadrive(1'b1),   // (porque no sé siquiera si se usa en el
  .joy_clk(joy_clk),            // Jupiter ACE), dejo conectadas las señales
  .joy_load_n(joy_load_n),      // de comando, pero desconectadas las salidas
  .joy1up(),                    //
  .joy1down(),                  //
  .joy1left(),                  //
  .joy1right(),                 //
  .joy1fire1(),                 //
  .joy1fire2(),                 //
  .joy1fire3(),                 //
  .joy1start(),                 //
  .joy2up(),                    //
  .joy2down(),                  //
  .joy2left(),                  //
  .joy2right(),                 //
  .joy2fire1(),                 //
  .joy2fire2(),                 //
  .joy2fire3(),                 //
  .joy2start(),                 //    
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .dp_tx_lane_p(dp_tx_lane_p),          // De los dos lanes de la Artix 7, solo uso uno.
  .dp_tx_lane_n(dp_tx_lane_n),          // Cada lane es una señal diferencial. Esta es la parte negativa.
  .dp_refclk_p(dp_refclk_p),            // Reloj de referencia para los GPT. Siempre es de 135 MHz
  .dp_refclk_n(dp_refclk_n),            // El reloj también es una señal diferencial.
  .dp_tx_hp_detect(dp_tx_hp_detect),    // Indica que se ha conectado un monitor DP. Arranca todo el proceso de entrenamiento
  .dp_tx_auxch_tx_p(dp_tx_auxch_tx_p),  // Señal LVDS de salida (transmisión)
  .dp_tx_auxch_tx_n(dp_tx_auxch_tx_n),  // del canal AUX. En alta impedancia durante la recepción
  .dp_tx_auxch_rx_p(dp_tx_auxch_rx_p),  // Señal LVDS de entrada (recepción)
  .dp_tx_auxch_rx_n(dp_tx_auxch_rx_n),  // del canal AUX. Siempre en alta impedancia ya que por aquí no se transmite nada.
  /////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .dp_ready(),                  // Señales de depuración 
  .dp_heartbeat()               // del DisplayPort
  );
endmodule
