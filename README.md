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
-   Home : Líneas on/off
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
  .config_líneas_off(),      //
///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .video_output_sel(1'b0),     // De momento, ponemos aquí PAL
  .disable_líneas(1'b1),    // De momento, sin líneas
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

Para comprobar que todo esto funciona, al arrancar el Jupiter ACE debe hacerlo como siempre. Para probar un sonido simple, he usado el comando 250 1000 BEEP que emite un sonido de 1 kHz durante 1 segundo. Para probar que funciona MIC, he probado a grabar algo (SAVE loquesea) y para probar el AY-3-8912, he cargado por audio la demo Old School Demo para Jupiter ACE, de MAT/ESI. Al escuchar el audio de la carga por los altavoces, constato que también tengo la señal EAR presente.

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
  output wire        config_líneas_off,
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
  .config_líneas_off(),       // a 1 para indicar que hay que deshabilitar las líneas. Va para el módulo de teclado
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

En ZX3W hemos conectado otra señal, `poweron_reset`, activa a nivel alto. En el momento en que usamos la SRAM a través de ZX3W, tenemos que recordar que no siempre tenemos a nuestra disposición la SRAM. Durante 32 ciclos, al principio del arranque del core, la SRAM no está a disposición de éste, porque se está leyendo de memoria la configuración de VGA y líneas que dejó la BIOS antes de arrancar este core.

Para que el core no pretenda usar la SRAM antes de tiempo, la señal `poweron_reset` indica, mientras vale 1, que el core debe permanecer en estado de reseteo. Esto se traduce a que en la instanciación del core, la señal `reset_n` que hasta entonces se definía así:

`.reset_n (kbd_reset & locked),`

Ahora se haga así, añadiendo esta nueva señal:

`.reset_n (kbd_reset & locked & ~poweron_reset),`

Después de esto, el core debería seguir arrancando y funcionando como hasta ahora.

### Imagen por VGA y DisplayPort

Aquí es donde más modificaciones pueden ser necesarias al propio ZX3W, y quizás al core. Es posible que el core dé una señal en color RGB con varios bits por cada color primario, y que no use modos paletizados, esto es, que no codifique el color de los píxeles con un índice a una paleta fija, sino que use directamente RGB. Este sería... un poco el peor caso, porque obligaría a usar una mayor cantidad de memoria para el frame buffer.

Puede que dé una señal en color RGB con varios bits por cada color primario, pero que esos valores sean fijos según una paleta establecida en el hardware, como por ejemplo pasa en el Commodore 64, que puede dar un valor de color de 24 bits, pero en realidad son 16 colores diferentes. Ese caso lo abordaremos en un tutorial aparte.

Por último, es posible que el core dé una señal RGB pero muy simple, con 1 ó 2 bits por color primario, como es este caso del Jupiter ACE, en donde tenemos 1 bit por color primario. En este caso, sería un desperdicio total el guardar 24 bits de información por pixel, cuando nos basta con 3.

Por otra parte, el core no da salida entrelazada y no hay, como en el Spectrum, software que use efectos tipo gigascreen, lo que significa que no necesitamos un framebuffer completo (640x480) sino uno de un solo campo (640x240).

Con esto conseguimos que la memoria BRAM necesaria para implementar el framebuffer se reduzca a 640\*240\*3 bits = 921600 bits, lo que está dentro del tamaño máximo de BRAM permitido por la menor de las FPGAs, la A35T.

En resumen, esto significa que el core se verá igual en cualquiera de los tres modelos de ZXTRES, y que, de hecho, podremos usar la misma versión del módulo ZX3W para las tres FPGAs.

Para hacer la menor cantidad posible de cambios al wrapper, vamos a optar por la siguiente estrategia:

**Primero:** damos a ZX3W un valor de color de 24 bits. Esto es, las señales ri, gi, bi del ZX3W se instanciarán de esta forma:

(en el propio core...)

```verilog
   wire r_ace, g_ace, b_ace;

   ...
   ...
   ...
   ...

   .r(r_ace),                 //
   .g(g_ace),                 // Salida de video en color, 1 bit por color primario (ETI 1984)
   .b(b_ace),                 //
```

(en ZX3W...)

```verilog
///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ri({8{r_ace}}),       // Repito 8 veces el valor del bit
  .gi({8{g_ace}}),       // de cada color primario que tengo del CE
  .bi({8{b_ace}}),       // para obtener un valor de 24 bits
  .hsync_ext_n(pal_hsync),               // Sincronismos horizontal y vertical
  .vsync_ext_n(pal_vsync),               // por separado
.csync_ext_n(pal_hsync & pal_vsync),   // El sincronismo compuesto se forma de forma muy sencilla
////////////////////////////////////////////////////////////////////////////////////////////////////////////
```

**Segundo:** hemos quedado en que usaremos la misma instancia de ZX3W para las tres FPGAs: borramos los ficheros `zxtres_wrapper_a200t.v` , `zxtres_wrapper_a100t.v` y `zxtres_wrapper.v` . El fichero que nos queda, `zxtres_wrapper_a35t.v` lo renombramos como `zxtres_wrapper.v` . En el proyecto, eliminamos los ficheros que ya no existen.

Tercero: abrimos nuestro nuevo `zxtres_wrapper.v` , que originalmente corresponde a la A35T. Navegamos hasta la parte en la que se define el framebuffer, que es un módulo llamado `dp_memory` (hacia la línea 692), y que tiene esta pinta:

```verilog
module dp_memory (
  input  wire        campoparimpar_pal,
  input  wire        lineaparimpar_vga,
  input  wire        interlaced_image,
  input  wire        clkw,
  input  wire [18:0] aw,
  input  wire [7:0]  rin,
  input  wire [7:0]  gin,
  input  wire [7:0]  bin,
  input  wire        we,
  input  wire        clkr,
  input  wire [18:0] ar,
  output wire [7:0]  rout,
  output wire [7:0]  gout,
  output wire [7:0]  bout
  );

  reg [8:0] fb [0:640*240-1];  // 640*240 pixeles
  reg [8:0] dout;

  assign rout = {dout[8:6], dout[8:6], dout[8:7]};
  assign gout = {dout[5:3], dout[5:3], dout[5:4]};
  assign bout = {dout[2:0], dout[2:0], dout[2:1]};

  always @(posedge clkw) begin
    if (we == 1'b1) begin
      fb[aw] <= {rin[7:5],gin[7:5],bin[7:5]};
    end
  end

  always @(posedge clkr) begin
    dout <= fb[ar];
  end

endmodule
```

Esta versión, la de la A35T tiene señales que no se usan, porque no implementamos el framebuffer completo. Sin embargo, están ahí por si pudieran usarse en la implementación concreta de un framebuffer para un core. Este podría ser el caso, pero como no tenemos necesidad de implementarlo, seguiremos ignorándolas.

El cambio que hay que hacer aquí es cambiar la definición de la memoria que implementa el framebuffer, de esto:

```
  reg [8:0] fb [0:640*240-1];  // 640*240 pixeles
  reg [8:0] dout;
```

A esto:

```
  reg [2:0] fb [0:640*240-1];  // 640*240 pixeles
  reg [2:0] dout;
```

Antes, para escribir un nuevo valor a una celda del framebuffer, se hacía esto:

```
      fb[aw] <= {rin[7:5],gin[7:5],bin[7:5]};
```

Ahora basta con esto:

```
      fb[aw] <= {rin[7],gin[7],bin[7]};
```

En realidad, cualquier bit de `rin`, `gin` o `bin` valen, ya que todos los bits valen lo mismo: o todos 1, o todos 0.

Al leer un valor se deposita en el registro `dout` . Desde ahí los valores de color de salida se reconvierten a 24 bits. Originalmente es así:

```
  assign rout = {dout[8:6], dout[8:6], dout[8:7]};
  assign gout = {dout[5:3], dout[5:3], dout[5:4]};
  assign bout = {dout[2:0], dout[2:0], dout[2:1]};
```

Y ahora, como es sólo 1 bit el que se usa para generar 8, pues hacemos así:

```
  assign rout = {8{dout[2]}};
  assign gout = {8{dout[1]}};
  assign bout = {8{dout[0]}};
```

Y con esto ya estaría modificado ZX3W para este core, o para cualquier otro que implemente salida de color con 3 bits (el QL por ejemplo, también podría usar esto).

De vuelta a la instanciación del ZX3W en el TLD de nuestro core, terminamos de instanciar las señales que necesitamos para obtener video. Además, vamos a pedirle que siga mostrando la señal PAL. De esa forma seguimos teniendo monitorizado el comportamiento del core, y que éste siga estable. Si tenemos un monitor DisplayPort, podremos ver, al mismo tiempo, que genera correctamente la imagen. Si no, y si tampoco tenemos un conversor DisplayPort -\> HDMI adecuado, pasaremos a generar una señal compatible VGA en un paso posterior.

La parte que queda de la instanciación de señales para la parte de video, queda así (recordemos que las conexiones al DisplayPort ya las habíamos hecho)

```verilog
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
  .ro(vga_r),           // Salida de 6 bits directas
  .go(vga_g),           // a los pines del monitor VGA
  .bo(vga_b),           // 
  .hsync(vga_hs),       // Lo mismo, pero para los sincronismos
  .vsync(vga_vs),       // horizontal y vertical.
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////
```

Y un poco antes, en la parte en la que se elige la salida de video, forzamos a que se emita la señal PAL original, sin efectos monocromáticos, y poner o no las líneas, lo dejamos a gusto de cada uno.

```verilog
///////////////////////////////////////////////////////////////////////////////////////////////////////////
  .video_output_sel(1'b0),    // Señal PAL por el conector VGA
  .disable_líneas(1'b0),   // Líneas activas, porque yo lo valgo
  .monochrome_sel(2'b00),     // Sin modo monocromático
  .interlaced_image(1'b0),    // La imagen del Jupiter ACE no es entrelazada
  .ad724_modo(1'b0),          // Se genera un reloj de color PAL (17.74 MHz)
  .ad724_clken(1'b0),         // De momento, no usaremos el reloj PAL generado en la FPGA (aunque generar, se genera)

////////////////////////////////////////////////////////////////////////////////////////////////////////////
```

Faltan dos cosas en la instanciación:

-   Un reloj de video adecuado
-   Especificar los valores de HSTART, VSTART

**Para el reloj:** es cierto que tenemos disponible el reloj de color original, los 6.5 MHz. La cuestión es que el framescaler funciona con píxeles con temporización de PAL. Dicho de otra forma: el framescaler, y la lógica que opera con él, espera relojes de video del orden de los 13-14 MHz, que es lo habitual en PAL.

Lo que ocurre con muchos sistemas antiguos es que trabajan a la mitad (o menos) de la resolución horizontal nominal de PAL. Por ejemplo, el ZX Spectrum opera con 352 píxeles horizontales y no con 704. Su reloj de pixel es de 7 MHz, cuando debería ser de 14 MHz.

En el Jupiter ACE ocurre lo mismo: su reloj de pixel es de 6.5 MHz, y el framescaler espera 13 MHz. A esa frecuencia, en realidad estaremos guardando el valor del mismo pixel dos veces seguidas, lo que es un desperdicio de memoria. Se deja como ejercicio para el lector el reducir a la mitad el framebuffer, de forma que no se escriban dos píxeles idénticos, uno detrás de otro.

Así, al generar los relojes, hay que generar otro del doble de la frecuencia del reloj de pixel: 13 MHz, que es el que en realidad usaremos como `clkvideo` dentro de ZX3W. No es, como digo, una situación ideal, pero permite generalizar el wrapper, para que funcione con la mayor cantidad posible de sistemas. Al portar uno del que se sepa que funciona a la mitad de la resolución PAL (MSX, Commodore 64, ZX81, Jupiter ACE, etc.) se puede optar por modificar la lógica de lectura/escritura en el framebuffer y así usar la mitad de la memoria. Para el ZX Spectrum (con el modo Timex HiRes), Amstrad CPC, SAM Coupé, QL, MSX2 y alguno que otro, habrá que dejar el framebuffer como lo tenemos ahora.

**Valores de HSTART y VSTART:** he pensado en algunos momentos el añadir una interfaz interactiva, disponible activando algún flag de depuración, para asistir a la búsqueda de valores adecuados, pero de momento no me he picado tanto como para necesitarlo. Lo que quiero decir es que habrá que usar un poco de cálculo tirando de que lo sepamos de la generación de video del core que estamos portando, y otro poco de ensayo y error.

**HSTART** se define como el número de ciclos de reloj (del reloj usado en `clkvideo`) que hay desde que termina (pasa de 0 a 1) la señal de sincronismo horizontal hasta que ocurre el primer pixel que queremos guardar en el framebuffer.

El framebuffer es de 640 píxeles por línea. Un línea en PAL son 704, o 720, o 768, según el reloj que tengamos. Ese dato es algo que tienes que averiguar en tu core. Para el ejemplo, supongamos 704. Como no cabe entero, hay que desperdiciar píxeles a izquierda y derecha. En concreto, hay que desperdiciar (704-640)/2 píxeles.

A este valor hay que añadir el número de ciclos de reloj (o píxeles) que hay desde que ha terminado el sincronismo horizontal hasta que comienza el primer pixel de la imagen original.

Esto en PAL es el tiempo de back porch. Suele ser unos 8 us, pero mejor intenta averiguarlo en tu core. En el de Jupiter ACE, esa información está en `jace_logic.v` , entre las líneas 73 y 122, que es donde se generan todos los timings de la señal de video.

El valor final de esa suma es HSTART.

En el caso del ACE, en el ciclo 342 (del reloj de 6.5 MHz) termina el sincronismo horizontal (línea 97) y en el ciclo (416-40=376, en la línea 118) termina el back porch. Total: 376-342=34 ciclos de reloj de 6.5 MHz. Para un reloj de 13 MHz, será el doble, 68 ciclos.

La cantidad de píxeles que se pintan en un línea se denomina "la zona activa". Suelen ser unos 52 us. En el Jupiter ACE, esto incluye la zona de borde (que en el ordenador original siempre está a negro) más la zona de "paper" (256 píxeles). En la línea 118 tenemos el cálculo: todo lo que no es blanking, es zona activa: desde 416-40 hasta 416, y desde 0 hasta 256+40. O sea, 256+80=336 píxeles, o ciclos de reloj.

Para el reloj que estamos usando, esos píxeles son el doble: 672 píxeles. Esto es lo que se "ve" en una pantalla original del Jupiter ACE. De esta línea tenemos que coger los 640 píxeles centrales. Tenemos que descartar (672-640)/2 = 16 píxeles (a cada lado, izquierda y derecha).

Sumando este valor 16 con el 68 de antes (el back porch), obtenemos 84. Ese será nuestro valor de HSTART.

El valor final que veis en el core, 80, viene de haber hecho ajustes manuales. No siempre el valor que obtenemos con este cálculo es el perfecto, ya que cada monitor añade su propio offset. No obstante, es un buen valor para empezar.

Si no os es posible averiguar la información de timing concreta de vuestro core, asumid 8 us de back porch, y 704 píxeles por línea. Sólo necesitaréis el valor de la frecuencia en MHz del reloj de pixel a usar (que estará en torno a los 13-14 MHz antes mencionados). El cálculo es por tanto: `HSTART = (704-640)/2 + 8*clkvideo`

**VSTART** se define de forma análoga: el número de líneas (que no ciclos de reloj) que ocurren desde que termina el sincronismo vertical hasta que comienza el primer línea que se va a guardar.

Aquí, tanto si la imagen original es entrelazada, como si no lo es, asumimos un valor de 288 líneas por frame/campo, que es lo estándar en PAL. De este frame/campo, guardaremos 240 líneas, así que nos sobran (288-240)/2 = 24 líneas. Como no estamos trabajando con ciclos de reloj, sino con líneas, no se multiplica por 2 como antes.

La parte que toca calcular, y que dependerá un poco del core, es cuántas líneas están a negro (back porch vertical, o como se llame en este caso), antes de que comience la imagen propiamente dicha. En PAL, la imagen "debe" comenzar en la línea 23, lo que significaría que, en teoría, el valor de VSTART debería ser 23+24=47. Sin embargo, aquí es donde el core puede cambiar cosas. Si no podemos averiguar esta información, 47 es un buen valor para tantear.

En el Jupiter ACE, el sincronismo vertical se genera en `jace_logic.v` en la línea 85 a 92, y de la 116 a la 122 se genera el blanking vertical.

Podemos ver (línea 97) que el sincronismo vertical termina en la línea 255. La 256 es la primera línea después del sincronismo. En la línea 118 vemos que el blanking vertical termina en (312-48)=264. Por tanto, tenemos 264-256=8 líneas de blanking vertical (bastante menos que 23).

La cantidad de líneas que se emiten en la zona activa van desde la línea 264 (hasta la 311 inclusive, o sea 48 líneas que corresponden al borde superior) más las 192 líneas que corresponden a la pantalla "normal", más otras 48 líneas del borde inferior. En total, 192+48+48=288 líneas. De aquí hay que coger las 240 líneas centrales. El cálculo ya lo habíamos hecho antes: tenemos que descartar arriba y abajo 24 líneas.

Sumando este 24 al 8 de antes, tenemos 32, como valor final de VSTART. En este caso, el valor calculado es muy parecido al que se ha usado finalmente (31).

En ZX3W, cambiad `video_output_sel` para que ahora tenga un 1 y podáis ver la imagen en VGA, o mejor aún, si disponéis de un monitor con entrada DisplayPort y otro que admita PAL RGB, dejad esa señal a 0, conectad ambos y así podéis ver la pantalla original en PAL RGB, que no debe haberse alterado por todo esto que hemos calculado, y la pantalla escalada en digital en el monitor DP. Con esa imagen ya podéis hacer las correcciones oportunas.

### Auto configuración del modo inicial de video

La BIOS del ZXTRES proporciona a los cores que se cargan desde ella (vía menú de selección de cores, o desde el comando .core en ESXDOS o desde el comando .zx3 también de ESXDOS) la información básica de modo de video configurado (PAL o VGA) y si las scanlines están activas o no.

Esta información se recoge desde la memoria SRAM justo al arrancar el core y está disponible en las señales de salida `config_vga_on` y `config_scanlines_off` .

Si desde el propio core no se va a dar opción a que el usuario cambie el modo de video, entonces basta con conectar mediante una señal estas dos salidas, a sus correspondientes entradas, también en ZX3W, que son: `video_output_sel` y `disable_scanlines` . En cuanto a `monochrome_sel` , tanto el core de ZX Spectrum como el de Jupiter ACE usan la tecla *Fin* (*End* en el teclado inglés) para ciclar entre los cuatro modos monocromáticos que existen.

En el Jupiter ACE se permite al usuario cambiar el modo de video (usando BlqDesp/ScrLck) y si usamos o no las scanlines (tecla Inicio/Home). Esto se hace desde el módulo de teclado. Los registros que guardan la información del modo activo de video, scanlines, etc, se inicializan con los valores de configuración suministrados por ZX3W. Esto se hace durante el reset inicial en donde ZX3W está leyendo la memoria. Esa señal de reset inicial se envía al módulo de control de teclado para que sea usada como enable para cargar en esos registros la información inicial, así:

```verilog
  always @(posedge clk) begin
    if (poweron_reset == 1'b1) begin
      video_output <= vi_video_output;
      disable_scanlines <= vi_disable_scanlines;
    end
    else if ................
```

`poweron_reset` viene del ZX3W, y está a nivel alto mientras ZX3W está leyendo la configuración desde la SRAM.
