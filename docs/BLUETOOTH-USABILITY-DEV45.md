# Bluetooth: navegación y resultados discretos · dev45/app28

Emitir desde el catálogo conserva la pantalla, marca, selección y posición de lectura. Se elimina el regreso explícito al panel Bluetooth y los desplazamientos automáticos al iniciar o terminar. Durante la operación, Emitir pasa a Detener, con indicador de actividad; la barra superior también mantiene Detener accesible aunque la lista esté desplazada. Tras pulsarlo queda desactivado con estado de restauración hasta que el trabajador termine. Generar, cambiar de marca y volver quedan bloqueados durante esa operación.

Las emisiones correctas no muestran resultados, incluidos los informes guardados al reabrir el panel. Una parada solicitada tampoco muestra resultado si están confirmadas emisión, desactivación, retirada de conjuntos y restauración. Los informes completos siguen guardados; la política afecta a su presentación. Los errores o confirmaciones incompletas se muestran en una fila Atención, en el catálogo y el panel, sin desplegar la lista técnica de comandos de radio. La consulta explícita de capacidades conserva sus resultados.

El catálogo reduce las tarjetas a nombre e identidad de perfil, con iconos de auriculares/equipo. Ayuda reúne las instrucciones extensas; la pantalla mantiene el requisito de apagar Bluetooth en Ajustes para emitir. Se conservan traducciones es/en, texto adaptable, VoiceOver, colores dinámicos, la integración con tres hosts SwiftUI y el canal privado de cancelación. No hay cambios de radio, perfiles, potencia, permisos, firma ni trabajador: app28 permanece idéntico.

## Verificación

El simulador comprueba la misma pantalla antes, durante y después de emitir; bloqueo de regeneración, Detener desde el catálogo, estado de cancelación, retorno silencioso y visibilidad de una restauración fallida. Comprueba todas las acciones de emisión con éxito completo y con cada confirmación ausente. Captura cuatro marcas, claro/oscuro, emisión activa, detención y fallo. Los estados de captura usan un trabajador simulado sin operaciones de radio.

Dev45 cuenta con procedencia de CI, siete comprobaciones del paquete, instalación y firma verificadas. La aceptación manual del comportamiento nuevo queda pendiente. El reconocimiento Surface Headphones en Windows aceptado en dev44 se conserva como evidencia histórica; este cambio de UI no demuestra reconocimiento adicional en iPhone/iPad o Android.

## Entrega verificada

Fuentes `b85561bac6a7294e928ba9f17686f81c1f3b466e`, [CI aprobado](https://github.com/Gokuencinar/NukeWireless/actions/runs/37590065805). Dieciséis comprobaciones por idioma (es/en) y capturas de catálogo, cuatro marcas, claro/oscuro, emisión, detención y fallo revisadas. Estas comprobaciones de UI usan el backend simulado; no afirman una prueba manual del botón en el teléfono.

Paquete `1.0.25+rh25.5~dev45`, SHA-256 `c79b9103d361a1259360a5df41c9f6a6004c28d18d229dbcc41a031326690b0d`, validado con siete comprobaciones. Trabajador app28 sin recompilar ni reinstalar; los hashes del paquete y de sus fuentes coinciden con la entrega anterior. Instalación confirmada por dpkg en el mismo iPhone11,2/iOS 16.3.1, clave SSH conocida en 192.168.1.22, capacidad del trabajador conservada y CodeDirectory `me.midnightchips.harpy-reloaded`. Sin nuevos informes de crash relevantes durante la instalación.

Recuperación: cerrar NukeWireless e instalar `/var/mobile/Documents/NukeWireless-dev44-backup.deb` desde el entorno SSH del mismo jailbreak. El paquete se transfirió y comprobó por hash antes de instalar dev45. app28 se mantiene. No requiere respring ni reinicio general.
