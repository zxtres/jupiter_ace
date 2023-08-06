# Simple Jupiter ACE clone.

Jupiter Cantab Jupiter ACE clone.

## Features

-   51K user memory
-   Readable pattern RAM
-   Writable ROM memory (to install alternate ROMs)
-   Colour module as described by ETI 1984, expanded with programmable border colour.
-   AY-3-8912 sound chip at ZX Spectrum 128K I/O ports.

## Keyboard shortcuts

-   Ctrl-Alt-Supr : CPU reset
-   Ctrl-Alt-Bkspace : Master reset. Return to ZX Spectrum core
-   Home : Scanlines on/off
-   End : Cycle monochrome effect
-   ScrBlk : PAL/VGA switch

## Cómo se ha actualizado para ZXTRES

### Introducción

Jupiter ACE es un ordenador muy sencillito: originalmente tiene salida de video en blanco y negro (píxeles blancos sobre fondo negro), y sonido tipo beeper. Nada más. Su señal de TV es parecida a la del Spectrum, con un reloj de pixel de 6.5 MHz. Emite una señal PAL "pseudo progresiva". Como no usa chips dedicados, es fácil ver en el esquemático del Jupiter ACE dónde genera el sincronismo vertical y dónde el horizontal.

Esta parte, la de averiguar dónde se generan ambos sincronismos, puede que sea una de las partes complicadas de averiguar en según qué cores.

Originalmente, el core que escribí para el ZXUNO tenía toda la memoria implementada en BRAM. Esto era posible, incluso en la Spartan 6 LX9, porque el core completo usaba menos de 64 KB (en la LX9 tienes 72 KB de BRAM).

Para poder enseñar un ejemplo lo más completo posible, he modificado aquel core para que use memoria externa (la SRAM) como memoria de usuario (51 KB). La memoria de pantalla y la memoria de patrones (donde se guarda la forma de los caracteres que se ven en pantalla) sigue estando en BRAM, porque son memorias muy pequeñas, y porque el doble puerto viene genial para poder usarlas tanto desde la CPU como desde el circuito de generación de video, sin quebraderos de cabeza.

Otra cosa que he añadido es color. Hay un proyecto para dar color al Jupiter ACE, publicado en la revista [Electronics Today UK, en abril de 1984](https://worldradiohistory.com/UK/Electronics-Today-UK/80s/Electronics-Today-1984-04.pdf). A falta de un nombre mejor, he llamado a este formato de color "formato ETI 1984" tanto en este documento como en algunos sitios del código fuente del core. Esto hace que la salida de video ya no sea un bit (pixel encendido o apagado) sino 3 bits (8 colores disponibles para un pixel).

Mi implementación varía en dos pequeñas cosas respecto de la original: la primera es que, al arrancar, el color por defecto no es tinta verde sobre fondo negro, sino tinta blanca sobre fondo negro, como en el Jupiter ACE original. En el proyecto de ETI 1984 se usa el verde sencillamente porque para inicializar el latch de 6 bits, usar verde sólo requiere una puerta lógica, mientras que hacerlo en blanco requeriría 3 puertas lógicas.

La otra modificación es la posibilidad de programar el color para el borde, como en el Spectrum. Pensé usar el puerto \$FE, también como en el Spectrum, ya que sus tres bits menos significativos estaban sin uso, pero he visto que el comando BEEP del Ace no tiene en cuenta esto, y al ejecutar un BEEP, el color del borde parpadea, así que al final lo he cambiado por el puerto \$00 (decodificando los 8 bits menos significativos del bus de direcciones).

Por último, y para que pueda disfrutarse de la demo "Old School" de MAT/ESI, creada para Jupiter ACE, con sonido AY, he añadido el mismo core de AY-3-8912 que hay en el Spectrum, a este core del Jupiter ACE, en los mismos puertos que usa el Spectrum 128K (y con el mismo tipo de codificación).

### Señales del core original

El Jupiter ACE, después de las modificaciones descritas, tiene esta interfaz:

```verilog
module jupiter_ace (
  input wire         clkram, // reloj para el uso de la BRAM. 4x el reloj de pixel. 26 MHz. Probablemente hubiera bastado con 13.5 MHz
  input wire         clk65,  // reloj de pixel. Originalmente es el reloj maestro del Jupiter ACE. 6.5 MHz
  input wire         reset_n,  // reset de la CPU
  input wire         ear,      // Entrada EAR
  output wire [7:0]  filas,      // Filas y columnas de
  input wire [4:0]   columnas,   // la matriz de teclado
  output wire        r,  // Color de
  output wire        g,  // un pixel
  output wire        b,  //
  output wire        hsync,  // Sincronismos
  output wire        vsync,  // separados
  output wire        mic,  // Señal MIC
  output wire        spk,  // Señal del altavoz
  output wire [7:0]  ay_a,  // Esta parte es nueva
  output wire [7:0]  ay_b,  // en el ACE. Es la salida de sonido
  output wire [7:0]  ay_c,  // separada del chip AY-3-8912
  //----------------------
  output wire [20:0] ext_sram_addr,  // Esta parte tampoco estaba en
  output wire [7:0]  data_to_sram,   // el core original. Es la interfaz
  input wire [7:0]   data_from_sram, // para poder usar memoria externa
  output wire        sram_we_n,      // como memoria de usuario
  output wire        sram_oe_n       //
);
```

Para portar en su totalidad el core (imagen, sonido, acceso a memoria para obtener el modo de video inicial) iremos poco a poco.

En el proyecto, copiamos el fichero XDC con los pines de la FPGA. Usaremos esos nombres de pines en el módulo TLD del proyecto.

Lo primero es comprobar que el core funciona, llevando su salida de video directamente a los pines de la VGA, y creando un sincronismo compuesto que llevaremos al pin vga_hs. En el pin vga_vs ponemos un 1. Para el acceso a la SRAM, vamos a conectarla directamente, sin hacer uso del wrapper aún. En definitiva, en el TLD haremos algo como esto:

```verilog
module tld_jace_color_ay (
   input wire         clk50mhz, 

   output wire [5:0]  vga_r,
   output wire [5:0]  vga_g,
   output wire [5:0]  vga_b,
   output wire        vga_hs,
   output wire        vga_vs,
   input  wire        ear,
   inout  wire        clkps2,
   inout  wire        dataps2,
   output wire        audio_out_left,
   output wire        audio_out_right,
   
   output wire [19:0] sram_addr,
   inout  wire [15:0] sram_data,
   output wire        sram_we_n,
   output wire        sram_oe_n,
   output wire        sram_ub_n,
   output wire        sram_lb_n
  );
    
  wire       clkram; // 26 MHz to clock internal RAM/ROM
  wire       clk65;  // 6.5MHz main frequency Jupiter ACE
  wire       locked;
  
  wire       kbd_reset;
  wire [7:0] kbd_rows;
  wire [4:0] kbd_columns;

  wire [7:0] sram_data_dout;
assign     sram_data = (sram_we_n == 1'b0)? {8'h00, sram_data_out} : 16'hZZZZ;
assign     sram_lb_n = 1'b0;  // usaremos solo el bus bajo
assign     sram_ub_n = 1'b1;  // de datos (0-7)
  
  relojes_mmcm los_relojes (
   .CLK_IN1(clk50mhz),
   .CLK_OUT1(clkram),     // for driving synch RAM and ROM = 26 MHz
   .CLK_OUT2(clk65),      // video clock = 6.5 MHz
   .locked  (locked)      // reloj estable cuando esta señal = 1
  );
  
  jupiter_ace the_core (
   .clkram(clkram),
   .clk65(clk65),
   .reset_n(kbd_reset & locked),  // el Jupiter ACE se resetea por teclado o al principio del todo
   .ear(ear),
   .filas(kbd_rows),             // Esto viene del módulo de teclado, donde se implementa
   .columnas(kbd_columns),       // la matriz de 5x8 teclas
   .r(r_ace),                 // Salida de video en
   .g(g_ace),                 // color, 1 bit por color 
   .b(b_ace),                 // primario (ETI 1984)
   .hsync(pal_hsync & pal_vsync),  // sincronismo compuesto
   .vsync(1'b1),
   .mic(audio_out_left),  // No me complico la vida. Llevo cada señal
   .spk(audio_out_right), // a un altavoz diferente. No uso el I2S aún
   .ay_a(),      // De momento, para comprobar que el core funciona
   .ay_b(),      // no necesito conectar la salida del AY-3-8912
   .ay_c(),      //
   .ext_sram_addr(sram_addr),           //
   .data_to_sram(sram_data_dout),       //
   .data_from_sram(sram_data),          // 
   .sram_we_n(sram_we_n),               //
   .sram_oe_n(sram_oe_n)                //
  );

  keyboard_for_ace the_keyboard (
   .clk(clk65),
   .poweron_reset(poweron_reset),
   .clkps2(clkps2),
   .dataps2(dataps2),
   .rows(kbd_rows),
   .columns(kbd_columns),
   .kbd_reset(kbd_reset)
  );
endmodule
```

Esta primera conversión usa al ZXTRES en su forma mínima: salida de video RGB a 15 kHz (o lo que saque nativamente el core), el sonido tipo beeper de la señal SPK la envío directamente a uno de los altavoces (audio_out_left externamente está conectada a la salida izquierda de sonido sólo con un pequeño filtro paso-baja en medio) y la de MIC, simplemente por no dejarla sola, la conecto al otro (right).

Las señales del teclado no han cambiado respecto a ZXUNO.

En cuanto al reloj, he creado un módulo nuevo usando el MMCM de Artix 7, lo que me permite afinar más en cuanto a las frecuencias sintetizadas, ya que puedo usar divisores con parte decimal. Así, en lugar de los 6.65536 MHz que usaba en el core original, aquí puedo usar exactamente 6.5 MHz y 26 MHz como reloj para la RAM interna.

Lo de usar una frecuencia tan alta para la BRAM es únicamente por desconocimiento mío: este core data del 2011, y no llevaba ni un año experimentando con Verilog, con lo que traducir lógica asíncrona a lógica síncrona no era mi fuerte (tampoco ahora, la verdad). Pensé que, simplemente dando un reloj lo suficientemente rápido respecto al resto del core, la memoria funcionaría como en el caso asíncrono, dándome el dato "lo antes posible".

En el core original había una señal para el reloj de la CPU, a 3.25 MHz. En esta versión, ese reloj no lo he podido sintetizar.

Resulta que en la Artix 7, la versión -2 que estamos usando, necesita que el reloj que se usa internamente como resultado de multiplicar el reloj externo (50 MHz) por el multiplicador, dé una frecuencia de entre 600 y 1400 MHz (en la Spartan 6 el rango por debajo era de 400).

Por otra parte, los valores del divisor que se usan en el MMCM llegan hasta 128. Esto significa que la frecuencia más baja que se puede sintetizar es de 600 MHz / 128 = 4.6875 MHz. Por encima de los 3.25 MHz requeridos. Esto, que es lo que más me ha costado modificar para que el core original funcione, ha hecho que tenga que modificar el módulo de CPU que originalmente usaba, para que permita *clock enables*, y así poder alimentarlo con un reloj más alto (6.5 MHz) y usar una señal de enable a 3.25 MHz. Aquí se ve el cambio:

```verilog
reg enable_cpu_p = 1'b0;
reg enable_cpu_n = 1'b0;
always @(posedge clk65)
  enable_cpu_p <= ~enable_cpu_p;
always @(negedge clk65)
  enable_cpu_n <= ~enable_cpu_n;
	  
tv80n cpu (
  // Outputs
.m1_n(), 
.mreq_n(mreq_n), 
.iorq_n(iorq_n), 
.rd_n(rd_n), 
.wr_n(wr_n), 
.rfsh_n(), 
.halt_n(), 
.busak_n(), 
.A(AZ80), 
.do(DoutZ80),
  // Inputs
.di(DinZ80), 
.reset_n(reset_n), 
.clk(clk65),          // Reloj x2 del habitual
.cep(enable_cpu_p),   // Los nuevos enables para flanco positivo
.cen(enable_cpu_n),   // y flanco negativo
.wait_n(wait_n), 
.int_n(int_n), 
.nmi_n(1'b1), 
.busrq_n(1'b1)
);
```

En la CPU hay partes que funcionan con el flanco negativo del reloj y otras con el flanco positivo, así que necesito dos tipos de *enable*: uno para cada tipo de flanco. Cada señal de *enable* tiene la mitad de frecuencia del reloj de 6.5 MHz, así que con ellas conseguimos que el módulo de CPU funcione a la frecuencia original de 3.25 MHz.

### Conexión del sonido

Vamos a comenzar adaptando el sonido. Antes de nada, añadir todos los ficheros de ZX3W, y modificar el TLD añadiendo las señales que no teníamos: las concernientes al módulo I2S, joystick (aunque éstas no las usaremos en el core), y las más importantes: las del DisplayPort. La definición del nuevo TLD queda así (que puede usarse como plantilla para casi cualquier otro core):

```verilog
module tld_jace_color_ay (
   input  wire clk50mhz,

   output wire [5:0]  vga_r,
   output wire [5:0]  vga_g,
   output wire [5:0]  vga_b,
   output wire        vga_hs,
   output wire        vga_vs,
   input  wire        ear,
   inout  wire        clkps2,
   inout  wire        dataps2,
   output wire        audio_out_left,
   output wire        audio_out_right,
   
   output wire [19:0] sram_addr,
   inout  wire [15:0] sram_data,
   output wire        sram_we_n,
   output wire        sram_oe_n,
   output wire        sram_ub_n,
   output wire        sram_lb_n,
   
   input  wire        joy_data,
   output wire        joy_clk,
   output wire        joy_load_n,
   
   output wire        i2s_bclk,
   output wire        i2s_lrclk,
   output wire        i2s_dout,  
   
   output wire        sd_cs_n,    
   output wire        sd_clk,     
   output wire        sd_mosi,    
   input  wire        sd_miso,
   
   output wire        dp_tx_lane_p,
   output wire        dp_tx_lane_n,
   input  wire        dp_refclk_p,
   input  wire        dp_refclk_n,
   input  wire        dp_tx_hp_detect,
   inout  wire        dp_tx_auxch_tx_p,
   inout  wire        dp_tx_auxch_tx_n,
   inout  wire        dp_tx_auxch_rx_p,
   inout  wire        dp_tx_auxch_rx_n
);
```

Este TLD está casi completo. Las únicas señales que no he añadido son las del módulo I2C del RTC, ni el puerto serie del módulo wifi.

No vamos a usar todas estas señales en el core, pero no pasa nada porque estén ahí.

La primera instanciación que haremos del ZX3W sólo tendrá conectadas las señales de sonido, los relojes, y la salida al DisplayPort (aunque aún no la usemos). Definimos dos señales de 16 bits: `reg [15:0] audio_l_del_core, audio_r_del_core` a las que asignaremos el valor correspondiente (en un momento).

```verilog
  // Conexión del core al ZX3W.
  zxtres_wrapper #(.HSTART(0), .VSTART(0), .CLKVIDEO(13), .INITIAL_FIELD(0)) scaler (
  .clkvideo(clkvideo),          // Reloj de video (debe estar en torno a los 14 MHz, porque 
  .enclkvideo(1'b1),            // debe dar un tick por cada pixel de pantalla PAL)
  .clkpalntsc(1'b0),          // Reloj de 100 MHz proveniente del MMCM
  .reset_n(locked),             // El módulo PLL o MCMM que genera los relojes debería generar una 
                                // señal "locked" que vale 1 cuando el reloj es estable, 
                                // y 0 cuando no lo está. Conéctala aquí.
  .reboot_fpga(),   // Señal generada por el teclado. Vale 1 para indicar reboot de la FPGA 
  ///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .sram_addr_in(21'h1FFFFF),    //
  .sram_we_n_in(1'b1),          // 
  .sram_oe_n_in(1'b1),          //
  .sram_data_from_chip(),       //
  .sram_data_to_chip(8'hFF),    //
  .sram_addr_out(sram_addr),        // Estas señales que vienen del
  .sram_we_n_out(sram_we_n),        // y hacia el ZX3W las dejamos
  .sram_oe_n_out(sram_oe_n),        // ya conectadas al
  .sram_ub_n_out(sram_ub_n),        // chip SRAM, para 
  .sram_lb_n_out(sram_lb_n),        // usarlas más tarde
  .sram_data(sram_data),            //
  .poweron_reset(),             // De momento, no usamos 
  .config_vga_on(),             // nada de esto
  .config_scanlines_off(),      //
///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .video_output_sel(1'b0),     // De momento, ponemos aquí PAL
  .disable_scanlines(1'b1),    // De momento, sin scanlines
  .monochrome_sel(2'b00),      // De momento, sin efecto mono
  .interlaced_image(1'b0),     // La imagen del Jupiter ACE no es entrelazada
  .ad724_modo(1'b0),           // Se genera un reloj de color PAL (17.74 MHz)
  .ad724_clken(1'b0),          // De momento, no usaremos el reloj PAL generado en la FPGA  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ri(),               //
  .gi(),               // Aquí irían las señales de color
  .bi(),               // del Jupiter ACE. De momento, no
  .hsync_ext_n(),      // ponemos nada aquí
  .vsync_ext_n(),      //
  .csync_ext_n(),      //
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .audio_l(audio_l_del_core),            // Entrada de audio
  .audio_r(audio_r_del_core),            // 16 bits, PCM, ca2
  .i2s_bclk(i2s_bclk),                   // 
  .i2s_lrclk(i2s_lrclk),                 // Salida hacia el módulo I2S
  .i2s_dout(i2s_dout),                   //
  .sd_audio_l(audio_out_left),           // Salida de 1 bit desde
  .sd_audio_r(audio_out_right),          // los conversores sigma-delta
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ro(),          // 
  .go(),          // Lo mismo con la entrada de imagen.
  .bo(),          // Aquí, de momento, no ponemos nada
  .hsync(),       // ni conectamos nada. El core está ahora mismo
  .vsync(),       // conectado directamente a los pines de la VGA
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
```

`audio_l_del_core` y `audio_r_del_core` son señales de 16 bits, en formato de complemento a 2. Por otra parte, el core de Jupiter ACE ofrece las siguientes señales:

```verilog
wire spk;
wire mic;
wire ear;
wire [7:0] ay_a, ay_b, ay_c;
```

Hay que mezclar estas señales y obtener, de ahí, dos valores para `audio_l_del_core` y `audio_r_del_core`. Esto es lo que he hecho:

```verilog
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
```

Primero, combino en un único valor, `audio_basico`, las señales `ear`, `mic` y `spk`. En la mezcla, `spk` es la que suena más alto, seguido de `ear`, y por último, `mic`. Esto lo consigo moviendo cada señal a un peso más o menos elevado según la importancia que quiero que tenga. Los valores mínimo y máximo que consigo son: 0000 0000 0000 0000 y 0001 1111 1111 1111, o dicho de otra forma, un rango entre 0000h y 1FFFh (0 a 8191). Estos valores son positivos en complemento a 2.

Como además tengo un AY-3-8912, pretendo crear señales estéreo compatibles con el formato ACB (canal A+C por el altavoz izquierdo, y B+C por el derecho). Las señales de audio básico las quiero sacar por ambos altavoces, así que mi mezcla es:

```
altavoz izquierdo = A + C + audio_basico
altavoz derecho   = B + C + audio_basico
```

Cada suma usa términos positivos, y en ca2 de 16 bits, el valor más positivo posible es 7FFF o 32767, así que cada una de estas sumas no debe sobrepasar esa cantidad, o si no tendremos distorsión. Como son 3 sumandos, y cada uno de ellos puede ir de 0 a máximo, entonces ninguno puede sobrepasar el valor 32767/3 = 10922.3 . La potencia de 2 más cercana, por defecto, es 8192, que corresponde a un valor de 13 bits. 13 bits tendrán, por tanto, cada uno de estos sumandos.

En el caso de `audio_basico`, la forma en la que genero el valor ya me proporciona el rango deseado, como hemos visto antes. Los tres bits a 0 por la izquierda me dan un valor en total de 16 bits.

Para cada uno de los canales del AY-3-8912, que originalmente viene como un valor de 8 bits sin signo, lo que hago es concatenarlo consigo mismo por la derecha, hasta rellenar 13 bits, para luego rellenar con 3 bits a 0 por la izquierda hasta llegar a 16 bits. Por ejemplo, para el canal A (señal `ay_a`) queda así: `{3'b000, ay_a, ay_a[7:3]}`

De esta forma, y como se puede observar en el código mostrado más arriba, cada suma dará un valor compatible con el rango positivo del complemento a 2 para 16 bits. En realidad, el rango obtenido irá desde 0 hasta 8191\*3 para cada salida, es decir, de 0 a 24573.

### Conexión a la SRAM

La parte de ZX3W que gobierna la SRAM tiene esta interfaz:

```verilog
  //////////////////////////////////////////
  input  wire [20:0] sram_addr_in,
  input  wire        sram_we_n_in,
  input  wire        sram_oe_n_in,
  input  wire [7:0]  sram_data_to_chip,
  output wire [7:0]  sram_data_from_chip,
  //----------------------------------------
  output wire [19:0] sram_addr_out,
  output wire        sram_we_n_out,
  output wire        sram_oe_n_out,
  output wire        sram_ub_n_out,
  output wire        sram_lb_n_out,
  inout  wire [15:0] sram_data,
  output wire        poweron_reset,
  output wire        config_vga_on,
  output wire        config_scanlines_off,
  //////////////////////////////////////////
```

La descripción está dividida en dos partes: la superior, que es la que se conecta al core, y ofrece una interfaz de SRAM con un bus de direcciones de 21 bits, un bus de datos de 8 bits, una señal de habilitación de escritura `sram_we_n_in` y otra de lectura `sram_oe_n_in`. Estas dos últimas señales las debe proporcionar el core, y son entradas para el ZX3W. El bus de datos está separado, con señales de entrada y de salida. La señal `sram_data_to_chip` es de entrada, y recibe un dato de 8 bits que el core pretende escribir en la SRAM. La señal `sram_data_from_chip` es de salida, y contiene un dato que la SRAM entrega para que lo consuma el core.

La mitad inferior, en concreto, las seis primeras señales de esa mitad, se conectan directamente a sus señales homónimas en el TLD. Aquí el bus de datos es de 16 bits, pero con dos señales que seleccionan qué mitad se va a usar. De la multiplexión y gestión de estas señales se encarga el propio ZX3W.

Conectamos las señales del core al ZX3W así:

```verilog
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
  .config_vga_on(),                   // a 1 para indicar que inicialmente hay que poner el core en modo VGA. Va para el módulo de teclado
  .config_scanlines_off(),       // a 1 para indicar que hay que deshabilitar las scanlines. Va para el módulo de teclado
///////////////////////////////////////////////////////////////////////////////////////////////////////////
```

Las nuevas señales que usamos son estas:

```verilog
  wire [20:0] jace_sram_addr;
  wire        jace_sram_we_n, jace_sram_oe_n;
  wire [7:0]  jace_sram_data_to_chip;
  wire [7:0]  jace_sram_data_from_chip;
```

Y en el core las conectamos (y por tanto, conectamos el core al ZX3W), así:

```verilog
   .ext_sram_addr(jace_sram_addr),              //
   .data_to_sram(jace_sram_data_to_chip),       // La memoria de usuario básica (1K) y la memoria
   .data_from_sram(jace_sram_data_from_chip),   // extendida (48K) se cogen de la memoria SRAM
   .sram_we_n(jace_sram_we_n),                  // externa. En total, este Jupiter ACE tiene 51K de RAM
   .sram_oe_n(jace_sram_oe_n)                   // La memoria de caracteres y de patrones se implementa con BRAM
```

En ZX3W hemos conectado otra señal, `poweron_reset`, activa a nivel alto. En el momento en que usamos la SRAM a través de ZX3W, tenemos que recordar que no siempre tenemos a nuestra disposición la SRAM. Durante 32 ciclos, al principio del arranque del core, la SRAM no está a disposición de éste, porque se está leyendo de memoria la configuración de VGA y scanlines que dejó la BIOS antes de arrancar este core.

Para que el core no pretenda usar la SRAM antes de tiempo, la señal `poweron_reset` indica, mientras vale 1, que el core debe permanecer en estado de reseteo. Esto se traduce a que en la instanciación del core, la señal `reset_n` que hasta entonces se definía así:

`.reset_n (kbd_reset & locked),`

Ahora se haga así, añadiendo esta nueva señal:

`.reset_n (kbd_reset & locked & ~poweron_reset),`
