# Interfaz Bluetooth (dev41)

La pantalla agrupa las herramientas en Exploración, Windows · Swift Pair, Apple · Proximidad y Android · Fast Pair. Cada plataforma ofrece Un dispositivo y Tres dispositivos, con los modelos que anuncia debajo y una etiqueta de duración de 10 s. Los seis comandos del trabajador app26 y sus condiciones de disponibilidad se conservan.

Se eliminan los párrafos repetidos de cada acción. Las condiciones para emitir quedan visibles antes del primer grupo de anuncios; el botón Cómo usar Bluetooth reúne las instrucciones de escaneo, permisos, emisión y recepción. El texto aclara que los anuncios no implementan el emparejamiento de un accesorio ni garantizan un aviso del sistema.

Los botones disponibles usan el color de acento de la app. Los no disponibles se atenúan y VoiceOver los identifica como desactivados. Las etiquetas de accesibilidad incluyen la plataforma, los modelos y la duración. Las filas admiten varias líneas y la pantalla se actualiza al cambiar el tamaño de texto. La apariencia sigue los colores claros y oscuros existentes.

Al iniciar una operación, la lista muestra el grupo En curso, con indicador de actividad y Detener. El control superior Detener conserva su canal de cancelación. La ayuda se desactiva durante una operación para no cubrir ese control. Al finalizar se muestra Última actividad; el grupo de resultado no ocupa espacio antes de disponer de un informe. No se modifica la emisión, la potencia, los permisos ni el trabajador Bluetooth.

## Validación

Las fuentes `567e3cd466eac6fd000e8b5afd90c7b429500ebc` han pasado la [compilación y regresiones del simulador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37358827404). La navegación en español e inglés devuelve ocho comprobaciones aprobadas por idioma. Las pruebas existentes de Bluetooth se adaptan a las nuevas posiciones de las acciones y conservan las comprobaciones de disponibilidad, cancelación y resultados. Se han revisado las capturas de ambos idiomas en modo claro y oscuro. El aviso de módulo ausente que aparece en ellas corresponde al simulador, que no dispone del trabajador del jailbreak.

El paquete dev41 supera las siete comprobaciones de empaquetado, firma, permisos y procedencia. Su SHA-256 es `fa2360e7e1cba66318a17fc81aef2fa09fc16f80f170a85300bda81494839696`. El generador del manifiesto conservaba por error la etiqueta de versión dev40; se corrigió a dev41 después de comprobar el marcador del binario, su hash y los hashes de todas las fuentes. Se preservaron el manifiesto original de CI y un registro de esa corrección local. El binario compilado no se modificó.

Instalación del 5 de octubre de 2026 confirmada por `dpkg` en el iPhone XS con iOS 16.3.1 y RootHide: `1.0.25+rh25.5~dev41`, con el trabajador `0.0.3~app26` sin cambios. El estado del trabajador responde y el ejecutable instalado conserva el identificador de firma `me.midnightchips.harpy-reloaded`. No se observaron informes de crash nuevos durante la instalación. La apertura remota no dejó la app ejecutándose; queda pendiente abrirla manualmente y confirmar la interfaz en el dispositivo.

Se conserva dev40 en `/var/mobile/Documents/NukeWireless-dev40-backup.deb`. Para recuperar la versión anterior, cerrar la app y ejecutar `dpkg -i /var/mobile/Documents/NukeWireless-dev40-backup.deb` desde el entorno SSH del mismo jailbreak.
