# Escaneo y prueba de publicidad BLE (dev31 / app15)

En el iPhone XS con iOS 16.3.1 y RootHide, el ejecutable instalado estaba firmado
con identifier HarpyReloaded mientras LaunchServices registraba
me.midnightchips.harpy-reloaded. CoreBluetooth iniciaba la solicitud, pero
authorization permanecía en 0 y no había aviso ni resultados. Al corregir solo
el identifier de firma con ldid -I (conservando entitlements), apareció el aviso
de autorización. El usuario confirmó recepción y el diagnóstico registró
authorization=3, 709 callbacks y 27 dispositivos. Dev31 conserva esta corrección
en postinst para reinstalaciones; los otros helpers conservan su firma anterior.

El escáner retoma la solicitud pendiente al volver a estado activo. Antes podía
perder el comienzo del escaneo cuando el callback PoweredOn llegaba mientras el
diálogo de autorización dejaba UIApplication inactivo. Una fixture de estado de
UI comprueba solicitud pendiente, reanudación sin duplicar el escaneo y parada.
Esta fixture no valida recepción de radio ni permisos reales del iPhone.

Diagnóstico del escaneo muestra estado, autorización, isScanning, callbacks y
dispositivos. Se guardan contadores y estado en NukeWirelessBLELastScan; no guarda
identificadores, nombres o payloads del entorno. El indicador scan_submitted y la
observación de isScanning se conservan después de detener para distinguir una
solicitud que no arrancó de un escaneo sin anuncios. El diagnóstico numérico usa
los enums públicos: PoweredOn=5 y AllowedAlways=3.

La prueba de anuncios usa el transporte HCI validado y el proceso independiente
de recuperación del módulo. El CLI y la app aceptan únicamente la operación fija
--le-advertise-test, sin payload, dirección, intervalo o opcode externos.
Usa la familia de comandos extendidos 0x2036/0x2037/0x2039/0x203c y un anuncio
legacy ADV_NONCONN_IND con handle dedicado 0xee. Anuncia NWLab y el servicio
7AD172A1-6D8C-4D0A-9BEA-8D8F3B5C9C21 con intervalo de 1000 ms, dirección pública
existente y potencia solicitada de 0 dBm. No es conectable, no rota identidades ni
suplanta fabricantes. La duración de 10 s se programa en el propio controlador.
La limpieza deshabilita y elimina el set de prueba antes de restaurar bluetoothd.

El JSON separa aceptación por el controlador, confirmación de desactivación y
transmission_verified (false). Para verificar la recepción, otro escáner BLE debe
detectar NWLab durante la prueba. No etiquetar el build como BLE Spam o BT
Disruptor funcional antes de comprobar la ruta de emisión y definir pruebas de
laboratorio. Los modos de ESP32 Modern con esos nombres construyen anuncios;
sus nombres no prueban conexiones, ecos L2CAP, desconexiones o captura de claves.

La prueba NWLab de app14 se ejecutó desde la app (UID 501), con las cinco órdenes
HCI completadas con status 0, set eliminado y service_restored=1. La laptop
Windows recibió el servicio y el nombre NWLab a -52 dBm. Un callback posterior
con RSSI -127 corresponde al valor inválido del receptor y no se cuenta como
otra recepción de radio.

El usuario eligió continuar con anuncios de fabricante en una prueba limitada.
App15 añade --le-manufacturer-test y Dev31 lo muestra como «Anuncio de fabricante
(10 s)». Conserva servicio UUID y flags; sustituye el nombre local por AD 0xFF,
company ID 0xFFFF y datos 4E574C616201 (NWLab y versión 1). El anuncio completo
ocupa exactamente 31 bytes. Conserva intervalo de 1000 ms, duración de 10 s,
handle dedicado y recuperación independiente. No acepta payloads, fabricantes,
direcciones, velocidades o duraciones externos. La recepción de esta nueva
variante debe verificarse después de instalar app15.

Fuentes de protocolo: Bluetooth Core HCI; tabla y decodificación primaria BlueZ:
https://github.com/bluez/bluez/blob/master/monitor/packet.c
Opcodes y tamaños se verifican sin instalar BlueZ en el iPhone.
