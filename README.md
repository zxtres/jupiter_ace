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
	  
	tv80n cpu(
		// Outputs
		.m1_n(), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(), .halt_n(), .busak_n(), .A(AZ80), .do(DoutZ80),
		// Inputs
		.di(DinZ80), .reset_n(reset_n), .clk(clk65), .cep(enable_cpu_p), .cen(enable_cpu_n), .wait_n(wait_n), .int_n(int_n), .nmi_n(1'b1), .busrq_n(1'b1)
        );
```

En la CPU hay partes que funcionan con el flanco negativo del reloj y otras con el flanco positivo, así que necesito dos tipos de *enable*: uno para cada tipo de flanco. Cada señal de *enable* tiene la mitad de frecuencia del reloj de 6.5 MHz, así que con ellas conseguimos que el módulo de CPU funcione a la frecuencia original de 3.25 MHz.
