# Google Fast Pair: prueba de descubrimiento

NukeWireless dev37 / helper app21 añade Información → Bluetooth → Android: Fast Pair (10 s).
Bluetooth debe estar apagado desde Ajustes del iPhone. El perfil utiliza una sola identidad, dirección pública fija y un límite de diez segundos impuesto por el controlador. Detener usa el mismo canal de cancelación comprobado en app19 y app20; salir al fondo también cancela.

La trama es `02 01 06 03 03 2c fe 06 16 2c fe cd 82 56`: Flags, UUID FE2C y Service Data con Model ID de 24 bits CD8256. Este modelo procede del fixture Pixel Buds de ESP32-TOOLS Modern, commit dc59cd372530d17633efd20b8a2421c3e60cfdfe. El intervalo es 100 ms, siguiendo la recomendación de descubrimiento de Google. No se inventa un valor de calibración de proximidad.

Esta prueba anuncia el formato de descubrimiento; no implementa el servicio GATT, claves, verificación ni emparejamiento completo de un proveedor Fast Pair. Sin receptor Android disponible, no se puede confirmar el aviso de Pixel Buds. La aceptación requiere distinguir el ACK del controlador de una recepción de radio independiente.

Fuentes primarias:
- https://developers.google.com/nearby/fast-pair/specifications/service/provider
- https://developers.google.com/nearby/fast-pair/specifications/introduction
- https://raw.githubusercontent.com/pepeangell5/ESP32-TOOLS-MODERN/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BLESpam.cpp

Pruebas: framing AD y orden de bytes del Model ID, intervalo 100 ms, dirección sin rotación, modo no conectable, duración de controlador 10 s y disponibilidad/bloqueo de la fila en español e inglés. Se conservan la firma y permisos existentes.

La prueba Apple anterior confirmó la cancelación desde la app en 2,277 s de emisión y 0,512 s desde Detener hasta el informe, con desactivación, retirada del anuncio y recuperación del servicio reconocidas. La laptop no recibió el paquete Apple en la captura; no hay prueba de recepción ni de aviso Apple.

## Verificación física dev37/app21

Instalado en iPhone XS / iOS 16.3.1 / RootHide, tras compilaciones CI ef2a125. Las pruebas nativas, interfaz en español/inglés y las siete comprobaciones del paquete pasaron. Se conserva la firma `me.midnightchips.harpy-reloaded`.

La laptop Windows recibió cuatro anuncios con Service Data FE2C `cd8256` y RSSI de −40 a −43 dBm. El ensayo se inició desde la app (UID 501) y se canceló mediante Detener: 3,293604 s de emisión y 0,493590 s de solicitud a informe. Parámetros, datos, activación, desactivación y retirada recibieron HCI Command Complete con status 0; el servicio Bluetooth se restauró. El usuario confirmó el mensaje de parada.

No hay un teléfono Android receptor: el aviso Fast Pair sigue sin verificar. El helper no interpreta un ACK como prueba de recepción; la evidencia RF pertenece al receptor independiente. No se ha verificado con un analizador de radio el instante exacto del último paquete.

Copias anteriores en el iPhone: `/var/mobile/Documents/NukeWireless-dev36-backup.deb` y `/var/mobile/Documents/NukeWireless-Bluetooth-app20-backup.deb`.
