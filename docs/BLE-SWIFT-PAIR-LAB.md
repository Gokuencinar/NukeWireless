# Swift Pair: prueba BLE de 10 segundos (dev33/app17)

El usuario eligió el perfil Windows y una prueba limitada de diez segundos en su
laptop. NukeWireless añade Información → Bluetooth → «BLE Spam: Swift Pair
(10 s)». Emite el nombre de laboratorio NWLab con el formato de descubrimiento
Swift Pair de Microsoft. No implementa un accesorio GATT emparejable.

La sección de fabricante usa company ID `0x0006`, beacon ID `0x03`, escenario
LE-only `0x00`, byte reservado `0x80` y nombre para mostrar NWLab. Se corrige
la longitud AD del generador de Modern: el paquete contiene exactamente los
bytes anunciados, sin estructuras incompletas. Los datos manufacturer que
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

Recuperación: se conserva dev32/app16 como copia de reinstalación. Las versiones
nuevas y la aparición del aviso deben verificarse antes de afirmar éxito.

Fuentes:

- [Microsoft: Swift Pair](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/bluetooth-swift-pair)
- [Modern: BLESpam.cpp, commit dc59cd3](https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BLESpam.cpp)
