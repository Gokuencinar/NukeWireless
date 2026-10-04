# Swift Pair: prueba BLE de 10 segundos (dev33/app17)

El usuario eligió el perfil Windows y una prueba limitada de diez segundos en su
laptop. NukeWireless añade Información → Bluetooth → «BLE Spam: Swift Pair
(10 s)». Emite el nombre de laboratorio NWLab con el formato de descubrimiento
Swift Pair de Microsoft. No implementa un accesorio GATT emparejable.

La sección de fabricante usa company ID `0x0006`, beacon ID `0x03`, escenario
LE-only `0x00`, byte reservado `0x80` y nombre para mostrar NWLab. Cada sección
AD contiene exactamente los bytes que declara. Se omite el UUID Fast Pair
que Modern añade también a su anuncio de Microsoft. Los datos manufacturer que
debe observar un receptor son `0300804e574c6162`.

Se conserva el transporte verificado, un único set no conectable, dirección
pública fija y duración de diez segundos en el controlador. El intervalo
solicitado es 152,5 ms, una cadencia normal de Swift Pair documentada por
Microsoft. No hay rotación de identidad, ráfagas de solicitudes de conexión ni
actualizaciones de datos. Windows deduplica avisos por sesión, por lo que esta
prueba no promete una sucesión de ventanas. La prueba breve tampoco implementa
el ciclo de emparejamiento y enfriamiento de un periférico comercial.

La app conserva cancelación, exclusión mutua y recuperación independiente del
servicio Bluetooth. El helper comprueba que el estado del servicio sea legible
y que Bluetooth esté apagado antes de abrir el transporte o retirar bluetoothd.
Para ello usa `com.apple.bluetooth.system`, observado y comprobado en el
iPhone durante la investigación anterior; no modifica los permisos de la app
ni la base TCC. Un estado desconocido devuelve un error y evita el acceso
exclusivo. Los callbacks del gestor se procesan en una cola propia del helper.

El informe separa:

- Aceptación de comandos HCI y confirmación de desactivación/eliminación.
- Recepción externa del company ID y payload exactos.
- Aparición del aviso en Windows, que requiere observación del receptor.

`transmission_verified` y `windows_notification_verified` permanecen en false
en el helper: no puede comprobar lo que recibió o mostró otro equipo.

Para la prueba: activar Bluetooth y las notificaciones Swift Pair en Windows,
mantener el iPhone desbloqueado y apagar Bluetooth desde sus Ajustes. Pulsar
una vez la opción nueva y observar si Windows muestra un aviso de NWLab.
El anuncio de prueba no permite completar un emparejamiento.

## Resultado comprobado

Dev33/app17 compilados e instalados en el iPhone XS con iOS 16.3.1 y Dopamine
RootHide. Las comprobaciones del formato C, los tests de la app, la navegación
del simulador y las siete comprobaciones del paquete terminaron correctamente.
La identidad de firma de la app sigue siendo me.midnightchips.harpy-reloaded.

La ejecución desde NukeWireless (UID 501) confirmó las cinco órdenes HCI con
status 0, la desactivación, la eliminación del set y `service_restored=1`.
La laptop registró tres recepciones válidas del company ID y datos exactos,
con RSSI de -50 a -42 dBm. El usuario confirmó: «Termina correctamente y aparece
el aviso NWLab». El aviso queda verificado por esa observación del usuario;
el informe nativo conserva sus flags de verificación externa en false.
No se observaron nuevos cierres inesperados relevantes y el receptor mantuvo
Bluetooth encendido, sin cambios de alimentación.

Antes de la ejecución correcta se registró un rechazo por Bluetooth encendido.
Ese resultado se produjo antes de retirar el servicio y no emitió anuncios.
El monitor inicial terminó al observar ese primer resultado; la verificación
final usa el registro posterior de la ejecución correcta y la captura externa.

Recuperación: se conservan en el iPhone
`/var/mobile/Documents/NukeWireless-dev32-backup.deb` y
`/var/mobile/Documents/NukeWireless-Bluetooth-app16-backup.deb`.

El perfil Windows de diez segundos está comprobado. Esta compilación no incluye
los perfiles Apple, Samsung o Google ni el modo continuo de Modern.

Fuentes:

- [Microsoft: Swift Pair](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/bluetooth-swift-pair)
- [Modern: BLESpam.cpp, commit dc59cd3](https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BLESpam.cpp)
