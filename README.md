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

`module jupiter_ace (`

`  input wire clkram, // reloj para el uso de la BRAM. 4x reloj de pixel`

`  input wire clk65,  // reloj de pixel. Originalmente es el reloj maestro del Jupiter ACE`

`  input wire reset_n,  // reset de la CPU`

`  input wire ear,  // Entrada EAR`

`  output wire [7:0] filas,   // Filas y columnas de`

`  input wire [4:0] columnas, // la matriz de teclado`

`  output wire r,  // Color de`

`  output wire g,  // un pixel`

`  output wire b,  //`

`  output wire hsync,  // Sincronismos`

`  output wire vsync,  // separados`

`  output wire mic,  // Señal MIC`

`  output wire spk,  // Señal del altavoz`

`  output wire [7:0] ay_a,  // Esta parte es nueva`

`  output wire [7:0] ay_b,  // en el ACE. Es la salida de sonido`

`  output wire [7:0] ay_c,  // separada del chip AY-3-8912`

`  //----------------------`

`  output wire [20:0] ext_sram_addr,  // Esta parte tampoco estaba en`

`  output wire [7:0] data_to_sram,    // el core original. Es la interfaz`

`  input wire [7:0] data_from_sram,   // para poder usar memoria externa`

`  output wire sram_we_n,             // como memoria de usuario`

`  output wire sram_oe_n              //`

`);`
