# Catálogo: emisión individual · dev46/app28

Bluetooth → Catálogo aleatorio permite emitir cada modelo generado al tocar su tarjeta, identificada con un icono de reproducción. El botón Emitir conserva la emisión conjunta de los perfiles disponibles. Ambas opciones duran como máximo 10 s y usan el mismo trabajador app28 y su canal privado de cancelación.

La emisión individual envía únicamente el índice del modelo tocado, con su marca. No sustituye un modelo sin perfil disponible: su tarjeta queda atenuada y sin reproducción. Durante cualquier emisión se bloquean nuevas emisiones, marca y generación; el modelo activo muestra un indicador y el estado. Detener sigue accesible en la barra y la misma pantalla. Al terminar se conserva la selección y el catálogo, sin resultado cuando emisión, retirada y restauración están confirmadas. Los fallos siguen visibles.

No cambia el contenido de los perfiles, las identidades, permisos, firma ni potencia. El reconocimiento Surface Headphones de dev44 en Windows sigue siendo evidencia histórica; este cambio no acredita reconocimiento adicional en otros receptores.

## Verificación prevista

El simulador recorre las 80 combinaciones de las cuatro marcas y comprueba que cada tarjeta emite exactamente su modelo, omite los no disponibles y rechaza emisión sin trabajador. El backend simulado verifica la misma pantalla, argumentos de un solo modelo, selección conservada, bloqueo de otra tarjeta mientras está ocupado, Detener desde la barra y final silencioso. Incluye captura de emisión individual y conserva las comprobaciones de dev45.

La compilación, paquete e instalación se documentarán tras verificarlos. Aceptación manual pendiente.
