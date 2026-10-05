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
