# Diagnostic13: contrato de readback UART observado

App `2.0.0~diagnostic13` / 20013; componente Bluetooth `2.0.0~diagnostic5`.

## Evidencia nueva y límite de diagnostic12

La prueba `le_capabilities` del tester ejecutó diagnostic4 desde diagnostic12
en iPhone10,2 / iOS 16.7.4 / 20H240 / rootless. La lectura tiene retorno 0,
errno 0 y longitud 72. La velocidad solicitada y devuelta es 3000000 en ambas
direcciones, sin cambios en caracteres, salida ni flags locales.

| Campo | Solicitado | Devuelto |
| --- | --- | --- |
| c_iflag | 5 / IGNBRK + IGNPAR | 0 |
| c_cflag | 232192 / 0x38b00 | 197376 / 0x30300 |
| Diferencia c_cflag | CREAD + CLOCAL | No se representan |
| Bits conservados | CS8 + CRTSCTS | CS8 + CRTSCTS |

Se restauran exactamente flags, caracteres y velocidades originales, y el
servicio se recupera. No hay eventos recibidos ni HCI confirmado. Diagnostic12
no resolvió el fallo: seguía exigiendo IGNBRK, CREAD y CLOCAL en la lectura.

El JSON conserva trece emisiones anteriores con worker diagnostic3; no contiene
un evento nuevo de emisión con diagnostic4. La confirmación actual procede del
diagnóstico del controlador y no se atribuyen eventos históricos a la build nueva.
Valores sin información personal y hash del archivo recibido en
[la evidencia](evidence/iphone10-2-20H240-uart-readback.json).

## Corrección

Se mantiene la solicitud aceptada (IGNBRK + IGNPAR, CS8 + CREAD + CLOCAL +
CRTSCTS, 3000000) y los caracteres originales. No se interpreta una omisión
en la lectura como prueba de que sea seguro retirar CREAD de la solicitud.

La política `h4-stream-effective-v2` reconoce únicamente la representación
completa observada: c_iflag 5 solicitado / 0 leído y c_cflag 0x38b00 solicitado /
0x30300 leído. Conserva la validación de velocidad, framing, paridad, ambas
direcciones RTS/CTS y procesamiento de bytes. Un valor parcial o distinto no
recibe esa excepción. La admisión de hardware/firmware sigue siendo exacta.
Se registra la normalización reconocida en `reported_differences`.

La prueba de regresión reproduce las estructuras original y leída del tester,
en vez de usar una copia de la estructura solicitada. Comprueba que se conserva
la solicitud 232192/5 y se admite 197376/0, y que perder CTS o RTS sigue
rechazándose. Continúan pruebas de velocidad, flags, H4, cancelación y recuperación.

Este contrato procede de una observación real de configuración, no demuestra
que el controlador conteste HCI ni que admita extended advertising. Las consultas
locales siguen siendo obligatorias antes de emitir; la recepción y los avisos
del receptor requieren comprobación independiente.

## Primera prueba

Instalar el unificado rootless diagnostic13, cerrar/abrir la app y comprobar
la misma versión en Info y Diagnósticos. Con Bluetooth apagado en Ajustes,
ejecutar primero Test Bluetooth controller y exportar JSON. Si responde,
probar un modelo, Detener, finalización natural y repetición. Si falla,
exportar antes de repetir; no borrar el diario. No se ha probado diagnostic13
en el dispositivo del tester ni se declara resuelta la emisión física.
