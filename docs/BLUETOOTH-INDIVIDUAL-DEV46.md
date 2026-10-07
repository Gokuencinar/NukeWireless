# Catálogo: emisión individual · dev46/app28

Bluetooth → Catálogo aleatorio permite emitir cada modelo generado al tocar su tarjeta, identificada con un icono de reproducción. El botón Emitir conserva la emisión conjunta de los perfiles disponibles. Ambas opciones duran como máximo 10 s y usan el mismo trabajador app28 y su canal privado de cancelación.

La emisión individual envía únicamente el índice del modelo tocado, con su marca. No sustituye un modelo sin perfil disponible: su tarjeta queda atenuada y sin reproducción. Durante cualquier emisión se bloquean nuevas emisiones, marca y generación; el modelo activo muestra un indicador y el estado. Detener sigue accesible en la barra y la misma pantalla. Al terminar se conserva la selección y el catálogo, sin resultado cuando emisión, retirada y restauración están confirmadas. Los fallos siguen visibles.

No cambia el contenido de los perfiles, las identidades, permisos, firma ni potencia. El reconocimiento Surface Headphones de dev44 en Windows sigue siendo evidencia histórica; este cambio no acredita reconocimiento adicional en otros receptores.

## Verificación

El simulador recorre las 80 combinaciones de las cuatro marcas y comprueba que cada tarjeta emite exactamente su modelo, omite los no disponibles y rechaza emisión sin trabajador. El backend simulado verifica la misma pantalla, argumentos de un solo modelo, selección conservada, bloqueo de otra tarjeta mientras está ocupado, Detener desde la barra y final silencioso. Incluye captura de emisión individual y conserva las comprobaciones de dev45.

Compilación, paquete e instalación verificados. Aceptación manual del comportamiento en el teléfono confirmada por el usuario.

## Entrega verificada

Fuentes `f2cbfddbe8cd7743f5108fe50ab31ff8598de46b`, [CI aprobado](https://github.com/Gokuencinar/NukeWireless/actions/runs/37591669144). Dieciocho comprobaciones por idioma (es/en), con capturas de las cuatro marcas, modo oscuro y emisión individual, conjunta, detención y fallo revisadas. El backend del simulador no emite radio.

Paquete `1.0.25+rh25.5~dev46`, SHA-256 `5b82134511b62584aa24c43961a60cc6b198fd805724668777a07ee3a9f28e56`, validado con siete comprobaciones. app28 conserva los mismos hashes de paquete y fuentes, sin recompilar ni reinstalar. Dpkg confirma dev46/app28 en iPhone11,2/iOS 16.3.1 con clave SSH conocida en 192.168.1.22. Capacidades del trabajador y CodeDirectory `me.midnightchips.harpy-reloaded` verificados; sin nuevos informes de crash relevantes durante la instalación.

Recuperación: cerrar NukeWireless e instalar `/var/mobile/Documents/NukeWireless-dev45-backup.deb` desde el entorno SSH del mismo jailbreak. Copia comprobada por hash antes de instalar. app28 permanece. No requiere respring ni reinicio general.

## Aceptación manual

El usuario respondió «Sí, funciona así» a la comprobación de dev46: tocar ▶ de un modelo disponible hace que solo esa tarjeta indique emisión, conserva abierto el catálogo, permite detener desde la barra superior y no muestra resultado tras detener o terminar correctamente. Esta aceptación corresponde a la interfaz en el iPhone; no demuestra reconocimiento adicional de modelos en los receptores.
