# Diagnostic12: verificación efectiva del socket UART

App `2.0.0~diagnostic12` / 20012 y componente Bluetooth `2.0.0~diagnostic4`.

## Fallo recibido

Los dos informes de diagnostic11 corresponden a iPhone10,2, iOS 16.7.4
(20H240), rootless y fuentes `985a1705`. Son exportaciones acumulativas:
no se suman como pruebas independientes los eventos repetidos.
Hay trece emisiones fallidas en `uart_configuration_verify`; la segunda
exportación añade una consulta de capacidades que falla en el mismo punto.
Se abre el socket, no se reciben eventos HCI y se registran configuración
original y servicio restaurados. Los intentos anteriores con Bluetooth
encendido se rechazan antes por `bluetooth_off`.

El informe antiguo combina fallo de lectura, longitud incorrecta y diferencia
de campos. No contiene los valores termios y puede copiar un errno residual.
No permite identificar qué campo difiere ni atribuirlo a un timeout HCI.

## Cambio

La solicitud conserva `c_cc` original: VMIN/VTIME y caracteres de edición no
controlan los reads de un socket AF_SYSTEM/SOCK_STREAM. La validación comprueba
todos los bits de hardware, 8N1, RTS/CTS, velocidad de salida de 3000000,
velocidad de entrada efectiva y los flags que pueden traducir, filtrar o
procesar los bytes H4. No exige igualdad de caracteres de terminal ni de
flags de salida/eco inactivos. Con paridad desactivada no exige IGNPAR/INPCK.
La velocidad de entrada cero se interpreta como la de salida según termios.

Se guardan los valores original/solicitado/observado/restaurado, flags,
velocidades, caracteres y campos discrepantes. Se separan retorno de syscall,
errno válido y longitud devuelta. Una discrepancia de datos informa errno 0.
La restauración conserva la comparación completa del estado original y su
aviso de fallo. El diario retiene los detalles UART acotados aunque trunque
otras partes de un informe grande.

Se mantienen admisión exacta, exclusividad, H4, allowlist de comandos,
capacidades, duración de diez segundos, Detener y recuperación de bluetoothd.
Skywalk no cambia. Esta corrección de la comparación es una candidata para
el fallo recibido: no demuestra qué normalización realizó ese driver ni
confirma todavía emisión física.

## Contrato y prueba

- [Apple termios.h / XNU 8792.61.2](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/sys/termios.h): significado de flags y estructura.
- [Apple tcsetattr(3)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/tcsetattr.3.html): velocidad de entrada cero y restauración del estado guardado.
- [InternalBlue ios-proxy, revisión fijada](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/ios/ios-proxy.m): contrato histórico del socket; no valida el firmware del tester.

La tolerancia a campos de terminal inactivos es una interpretación del contrato
de stream, no una extracción del driver privado de 20H240. Se conserva el
rechazo ante discrepancias de hardware o procesamiento efectivo.

Pruebas añadidas: caracteres conservados, normalizaciones inactivas aceptadas,
velocidad/paridad/framing/flujo/traducciones/eco rechazados y conservación de
detalles UART al truncar el diario. Continúan las pruebas H4/socketpair.

Aceptación física pendiente: con Bluetooth apagado en Ajustes, ejecutar
primero Test Bluetooth controller y exportar JSON. Solo si responde, probar
un modelo, Detener, finalización natural y repetición. Si aún falla, el nuevo
JSON debe identificar syscall/longitud/campos reales; no se deben retirar más
guardas sin esa evidencia. Un ACK del controlador no prueba recepción externa.

## Validación de entrega (11 de octubre de 2026)

Fuentes compiladas: `396618ffdcde2c3124b7cfa3aa059525f1281f81`. Los cuatro workflows pasaron:

- [Unified installer packaging](https://github.com/Gokuencinar/NukeWireless/actions/runs/38173466026).
- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/38173465992).
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/38173465988).
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/38173465954).

Pasaron las pruebas UART efectivas/socketpair y de retención del diario.
Ambos targets completaron 46 comprobaciones de interfaz y cuatro ciclos reales
de segundo plano por idioma (es/en). Se inspeccionaron los tres DEB unificados:
20 comprobaciones locales ejecutadas pasaron; las tres pruebas dpkg omitidas
en Windows pasaron en Linux CI. La comprobación del payload real que CI omite
se ejecutó localmente. Procedencia y hashes en
[la verificación](evidence/diagnostic12-verification.json).

No se instaló diagnostic12 en un dispositivo ni se confirmó emisión UART.
El fallo de configuración de diagnostic11 está observado; la eficacia física
de esta candidata sigue pendiente del tester.
