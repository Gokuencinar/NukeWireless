# Diagnostic14: retención de wake durante la sesión UART

App `2.0.0~diagnostic14` / 20014; componente Bluetooth `2.0.0~diagnostic6`.

## Evidencia

El informe recibido confirma diagnostic13 y las fuentes `5c265c96` en
iPhone10,2 / iOS 16.7.4 / 20H240 / Dopamine rootless. La configuración UART
supera la validación `h4-stream-effective-v2`; el socket acepta un frame H4 con
Read Local Version (0x1001). No se recibe ningún byte ni evento antes del plazo.
El error actual es `Controller read completion deadline expired.`, en
`le_capabilities`. Se restauran configuración y servicio correctamente.

Hay una prueba actual del controlador, duplicada en el diario importante; las
emisiones de diagnostic11/12 conservadas en el mismo JSON son históricas.
Diagnostic13 no demuestra una emisión. Los valores actuales están en
[la evidencia](evidence/iphone10-2-20H240-diagnostic13-timeout.json).

## Corrección y procedencia

El cliente de referencia abre `/dev/btwake` antes de conectar el socket UART
y mantiene ese descriptor hasta después de cerrar el socket:
[InternalBlue ios/main.m, commit f524380, líneas 63–79](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/ios/main.m#L63-L79).
NukeWireless omitía ese paso. Su ausencia es un candidato para el timeout, no
una causa física confirmada en el iPhone del tester.

Diagnostic14 adquiere ese nodo con lectura, sin escribir, antes del canal UART.
Usa `O_NONBLOCK`, `O_CLOEXEC` y `O_NOFOLLOW`; comprueba mediante `fstat` que
se trata de un dispositivo de caracteres. Si falla, no conecta ni envía HCI y
devuelve `uart_wake`, errno y detalles de apertura. No crea nodos ni cambia permisos.

El descriptor se conserva durante configuración, consultas y operación, y se
libera después de restaurar y cerrar UART. También se libera si la creación del
socket falla, al cancelar y en destrucción. El cierre es idempotente.
`wake_open`, `wake_opened` y `wake_closed` quedan en el diagnóstico.
La recuperación independiente del servicio y el bloqueo exclusivo no cambian.

Se conserva la admisión exacta iPhone10,2 / 20H240 y toda la validación UART de
diagnostic13. Skywalk, los perfiles, los plazos de lectura y la UI no cambian.
No se añaden resets, órdenes de firmware ni comandos HCI para despertar el chip.

## Pruebas y aceptación

Las pruebas nativas usan `/dev/null` para verificar ownership, flags y cierre de
un descriptor de caracteres; un archivo ordinario y una ruta inexistente deben
rechazarse. Comprueban cierre sin canal UART y con socketpair, incluido Detener.
Son pruebas de recursos en macOS, no una simulación de la activación del chip.
Se conservan las pruebas de readback, framing, velocidad, flujo y H4.

En el dispositivo: instalar el DEB unificado rootless diagnostic14, cerrar y
abrir NukeWireless y verificar la versión en Info y Diagnósticos. Apagar Bluetooth
en Ajustes y ejecutar Test Bluetooth controller. Exportar JSON antes de repetir
si falla. Solo si el controlador responde, probar un modelo, Detener y repetición.
No se declara emisión ni recepción física hasta recibir esa comprobación.
