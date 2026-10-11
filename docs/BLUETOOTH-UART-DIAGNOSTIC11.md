# Diagnostic11: transporte UART experimental

La app es `2.0.0~diagnostic11` (20011) y el componente Bluetooth pasa a
`2.0.0~diagnostic3`. Se añade un backend UART H4 junto al backend Skywalk.
La admisión UART está limitada a **iPhone10,2 / iOS 16.7.4 / 20H240**,
el hardware y firmware del tester con evidencia de topología UART en
[la investigación](BLUETOOTH-UART-INVESTIGATION.md). No se declara soporte
para todos los A11 ni para cualquier versión de iOS.

## Comportamiento

La selección se realiza antes de retirar `bluetoothd`: se prefiere un nexus
Skywalk válido; si no existe se comprueba la admisión UART y el registro
`com.apple.uart.bluetooth` mediante CTLIOCGINFO. La consulta no conecta.
La selección queda fijada durante ese proceso. No hay fallback después de
enviar comandos, ni cambios en el transporte ACT/ACL heredado.

El runner conserva la comprobación de Bluetooth apagado, el lock exclusivo,
la cancelación privada y el proceso independiente que restaura `bluetoothd`.
Solo después de retirar el servicio se conecta al socket UART. Se admite una
espera acotada por EBUSY antes del primer comando; nunca se repite un comando
HCI para resolver una apertura fallida.

El socket usa las declaraciones públicas Darwin de kernel control y termios.
Lee la configuración, solicita raw/CS8/CREAD/CLOCAL/CRTSCTS/IGNPAR y 3000000
baudios, y exige lectura de vuelta coincidente antes de enviar HCI. No se usa
un valor numérico de flags copiado, tcflush con parámetros opacos, WriteRAM,
parches de firmware ni comandos de fabricante. Al cerrar intenta restituir y
verificar la configuración original antes de devolver el servicio al sistema.
Un error de restauración se conserva aunque falle la apertura.

Las órdenes existentes se encapsulan con el tipo H4 Command; las respuestas
H4 Event se entregan sin el prefijo al consumidor HCI existente. ACL/SCO/ISO se
consumen completos y se descartan. Framing desconocido, longitudes excesivas,
EOF o límites agotados detienen la sesión; no se busca un prefijo aparente
dentro de datos arbitrarios para resincronizar. Se conservan las allowlists,
deadlines, créditos HCI y las pruebas de diez segundos con Detener.

La emisión sigue exigiendo respuestas válidas a las consultas de capacidades,
bits de extended advertising y capacidad suficiente para la selección. Añadir
UART no demuestra que ese controlador admita todos los comandos actuales.
Si faltan capacidades se informa el rechazo y se recupera el servicio.

## Diagnósticos e interfaz

`--status` y `--diagnostics` identifican el transporte seleccionado y la sonda
UART. Las operaciones registran apertura, configuración, bytes/eventos recibidos,
paquetes de datos descartados y restauración. La comprobación de interfaz durante
la recuperación UART solo confirma registro: no se reconecta al controlador
que ya pertenece a `bluetoothd` ni prueba su funcionamiento de radio.

El catálogo distingue comprobación pendiente, paquete ausente, componente antiguo
y transporte no disponible. Recibe la actualización asíncrona del estado aunque
ya esté abierto. Generación, emisión individual/todos, Detener y permanencia en
el catálogo conservan su funcionamiento anterior.

## Validación y prueba pendiente

El parser C tiene pruebas de fragmentación, agrupación, aislamiento de datos y
límites. Las pruebas macOS usan socketpair para verificar el framing de comandos,
recepción parcial, EOF, rechazo de HCI Reset, escritura de limpieza tras cancelar
y cierre idempotente con ownership del descriptor. No simulan un controlador
Apple ni prueban la configuración termios privada. CI compila con el SDK iOS y
ejecuta la regresión del catálogo en español e inglés.

**Pendiente de prueba física UART**: obtener primero el snapshot de registro del
tester. Después instalar el paquete completo Dopamine/rootless, con Bluetooth
apagado en Ajustes, y ejecutar el diagnóstico del controlador. Revisar el JSON
antes de probar un único modelo, Detener, finalización y una segunda operación.
La recepción externa o un aviso del sistema deben confirmarse por separado.
El iPhone XS de referencia usa Skywalk y no puede validar UART.

Referencias de contrato:
- [XNU 8792.61.2 kern_control.h](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/sys/kern_control.h).
- [XNU termios.h](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/sys/termios.h).
- [InternalBlue ios-proxy.m, revisión fijada](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/ios/ios-proxy.m): evidencia histórica de nombre del control, H4 y opciones termios; no prueba de acceso en 20H240.

## Resultados de compilación y paquete (11 de octubre de 2026)

Fuentes compiladas: `985a1705e724d7bf133f8d5a2c53530f6d991401`. Los cuatro workflows terminaron correctamente:

- [Unified installer packaging](https://github.com/Gokuencinar/NukeWireless/actions/runs/38149905835).
- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/38149871297).
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/38149871316).
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/38149871304).

Pasaron las pruebas H4 y socketpair, incluida contrapresión de escritura y
conservación del fallo de restauración al cancelar. Los dos targets de app
compilaron y completaron 46 comprobaciones UI y cuatro ciclos reales de segundo
plano por idioma (es/en).

Se generaron e inspeccionaron los unificados RootHide, rootless y rootful con
el componente Bluetooth diagnostic3. Las pruebas locales de contenido, carga
obligatoria, firma/identidad y procedencia pasaron. Las tres pruebas de dpkg
que se omiten en Windows pasaron en Linux CI; el test de payload real que CI
omite se ejecutó localmente. Hashes y límites físicos se conservan en
[la verificación](evidence/diagnostic11-verification.json).

No se instaló esta entrega en un dispositivo ni se comprobó UART físico.
La restauración de configuración fallida conserva un aviso de limpieza incluso
si se pulsa Detener; ese caso no se oculta como una finalización correcta.
