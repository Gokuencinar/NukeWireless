# Diagnostic17: ciclo de vida específico para UART

App `2.0.0~diagnostic17` / 20017; Bluetooth `2.0.0~diagnostic7`.
Base: diagnostic16, HEAD anterior `2be985f`. Su desbloqueo Wi-Fi se conserva.

## Investigación conjunta de los reportes

Diagnostic11 rechazaba la configuración. Diagnostic12 registró los valores
reales del driver; diagnostic13 los admitió, escribió Read Local Version y
no recibió ningún byte. El reporte recibido de nuevo coincide en los campos
del fallo ya analizado: es diagnostic13/Bluetooth diagnostic5, no una prueba
de diagnostic16. Los eventos históricos no se cuentan como intentos actuales.
Diagnostic14 añadió el descriptor wake y diagnostic16 lo conserva, pero ambos
seguían retirando bluetoothd antes de adquirir el canal UART.

El [cliente UART de InternalBlue, revisión f524380](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/ios/main.m#L63-L79)
abre wake y el socket sin retirar bluetoothd. Su
[documentación](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/doc/ios.md)
requiere Bluetooth apagado desde Ajustes. No implica soporte probado en iOS 16.

Se extrajo también el kernel del IPSW oficial exacto 20H240 del iPhone10,2.
AppleOnboardSerial adquiere el puerto y convierte el rechazo de acceso
exclusivo en EBUSY; AppleBluetooth implementa la apertura/cierre del nodo wake.
Hashes, direcciones y límites de extracción están en
[la evidencia](evidence/iphone10-2-20H240-uart-lifecycle.json).
No se ejecuta código del kernel ni se añaden offsets al tweak.

La retirada del daemon era una diferencia concreta respecto al cliente UART
de referencia y podía perder el estado de inicialización del chip. Es una
hipótesis causal para el timeout, no una prueba de apagado físico tras bootout.
La apertura de wake no demuestra que el chip esté inicializado.

## Cambio

Solo UART mantiene bluetoothd durante la operación. Sigue exigiendo Bluetooth
apagado, contrato exacto iPhone10,2/20H240, lock exclusivo de la app, apertura
exclusiva del puerto por el kernel, configuración verificada y comandos HCI
permitidos. EBUSY se espera de forma acotada y nunca provoca una retirada del
daemon para forzar la apertura. No cambia Skywalk.

El hijo independiente de recuperación se prepara antes de abrir UART. Tras
una finalización normal, solo observa el servicio si se verifican cierre de
socket/wake, restauración de configuración, limpieza de cualquier comando que
pueda modificar anuncios y el mismo PID del servicio. El PID sirve únicamente
para comparar snapshots; no se señala mediante kill. Un timeout de una consulta
de lectura no obliga a reiniciar un servicio cuya limpieza está confirmada.

Si el trabajador muere, pierde el pipe, lanza una excepción sin evidencia de
limpieza, cambia el PID o no confirma la parada/eliminación de anuncios,
el hijo conserva el lock y aplica retirada/restauración al dominio Bluetooth
ya validado. No se extiende a procesos ni servicios ajenos. Skywalk conserva
su protocolo de recuperación anterior. La duración finita de anuncios y
Detener siguen activos.

El JSON añade `service_strategy`, `service_retired_before_operation` y
`service_preserved`. `service_restored` conserva el contrato existente: el
servicio está operativo al terminar; `service_preserved` distingue que no hubo
retirada/restauración. Estos campos se conservan si el evento se resume por tamaño.

## Verificación

Las regresiones cubren PID ambiguo/inválido, desbordamiento, EOF, mensajes
desconocidos, conservación normal y recuperación Skywalk. Las pruebas UART
usan el timeout de lectura del tester, rechazan cierre/restauración incompletos
y exigen ACK de parada/eliminación cuando pudo modificarse publicidad.
Continúan H4, backpressure, cancelación, ownership wake y readback del firmware.

Las cuatro validaciones CI pasaron para `6c05a35008ac94d17cfc512e116dca98f1941dfc`:
compilación principal, candidatos con destino iOS 15, trabajador Bluetooth y
migración del instalador. El simulador completó 46 comprobaciones y cuatro
ciclos reales de segundo plano por idioma, español e inglés. Los DEB completos
RootHide, rootless y rootful incluyen Bluetooth diagnostic7; pasaron las
comprobaciones locales de integración, procedencia, firma, dependencias y rutas.
Las tres pruebas que requieren dpkg/Linux se ejecutaron allí, y la prueba del
payload real que omite ese trabajo CI se ejecutó localmente sobre los DEB finales.
Hashes, trabajos y resultados en [la verificación](evidence/diagnostic17-verification.json).
Los archivos `src/compat` son idénticos a diagnostic16.

No hay acceso al iPhone del tester: no se declara resuelto el timeout físico ni confirmada la
recepción de anuncios. Esta entrega busca corregir el ciclo de vida con los
reportes existentes, sin pedir otra recogida previa al tester.
