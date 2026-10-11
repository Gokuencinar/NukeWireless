# Diagnostic15: desbloqueo Wi-Fi y wake UART

App `2.0.0~diagnostic15` / 20015. Bluetooth `2.0.0~diagnostic6`, sin cambios
respecto a diagnostic14. Incluye la retención de `/dev/btwake` de
[diagnostic14](BLUETOOTH-UART-DIAGNOSTIC14.md).

## Regresión de desbloqueo comprobada

En el iPhone XS de referencia, iOS 16.3.1 / RootHide, la app instalada era
diagnostic10, commit `9210fb07`. El registro contiene el lanzamiento del bloqueo
del equipo de prueba pero muestra `swift-unblock-hook: unavailable`, sin parada
privilegiada para ese equipo. El usuario confirmó que el bloqueo solo cesaba al
reiniciar la app. No se alteraron procesos ni reglas al recoger el registro.
[Evidencia sin direcciones ni identificadores personales](evidence/diagnostic10-unblock-regression.json).

El adaptador conservaba un hook Swift mediante `MSHookFunction`. La carga
integrada de la biblioteca no garantiza que ese símbolo esté disponible. Si
faltaba, la parada privilegiada quedaba desconectada del método usado por la UI.
Esto explica la ruta ausente observada; no implica que todos los problemas de
conectividad tengan esa causa.

## Corrección

`NWWiFiUnblock` intercepta el método de clase `unblockIPWithIp:` en
`NWLegacyCommandsClass`, usado y validado por `NWScanBridge`. Exige la firma
Objective-C exacta `v24@0:8@16`, modifica únicamente la metaclase seleccionada
y conserva la implementación original. La instalación es idempotente y no
requiere backend de hooks, offsets Swift ni conversión de su ABI de strings.

Solo acepta una IPv4 válida para la limpieza. Marca la parada esperada del
proceso registrado, llama una vez al método nativo y garantiza mediante
`@finally` la parada privilegiada existente aunque el método lance excepción.
La excepción original no se oculta. El adaptador conserva la validación del
NSTask propio, nunca señala un PID de una tarea ya terminada, mantiene ownership
si sigue activa y conserva la restauración ARP. La UI sigue verificando el estado
del proceso; eso no prueba por sí solo la recuperación de Internet del receptor.

Se elimina el hook Swift sustituido y su dependencia de `MSHookFunction`.
El registro de instalación pasa a `objc-unblock-hook`.
Los menús Wi-Fi heredados también pasan por `NWDeviceSetBlocked` al desbloquear:
su closure Swift podría saltarse el despacho Objective-C. Se conserva la
verificación de generación, dispositivo y estado del proceso. Los menús de
Punto de acceso se identifican explícitamente y conservan su handler del filtro.
La regresión del simulador comprueba ambas rutas dentro del test de acciones.
No se cambia el bloqueo Wi-Fi, el filtro de Punto de acceso ni la identidad de firma.

## Validación y aceptación

La prueba nativa usa métodos de clase reales para comprobar la firma, que la
implementación original y la limpieza se llamen una vez, repetición, rechazo de
IP inválida y nil, respeto a la superclase y limpieza cuando la llamada nativa
lanza una excepción. Se ejecuta en CI junto a las regresiones anteriores.

En el XS: cerrar la app solo cuando no haya operaciones activas, instalar el
DEB RootHide unificado y probar bloquear y desbloquear el equipo propio indicado.
Comprobar que la mano vuelve a azul y páginas nuevas vuelven a cargar sin reiniciar
NukeWireless; repetir. La restauración de Internet requiere esa aceptación manual.

En el iPhone 8 Plus: seguir la prueba de controlador UART de diagnostic14 y
exportar JSON antes de repetir si falla. No se declara que despertar el enlace
esté resuelto físicamente hasta recibir una respuesta HCI.

## Validación de entrega (12 de octubre de 2026, Europe/Madrid)
Fuentes compiladas: `ce471cef352a50e4f3407f5e353602548fa16648`.
Los cuatro workflows aprobaron:

- [Unified installer packaging](https://github.com/Gokuencinar/NukeWireless/actions/runs/38180682543)
- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/38180682546)
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/38180682544)
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/38180899976)

Las regresiones de ownership y fallo de wake, y UART con los valores del
tester, pasaron en macOS, junto con H4,
cancelación, EOF y propiedad del descriptor. También pasó la regresión de desbloqueo Objective-C
con comprobación de ABI, repetición, clase padre y limpieza ante excepción. El simulador pasó 46 comprobaciones
y cuatro ciclos reales de segundo plano por idioma (español e inglés).

Se generaron los tres DEB unificados con Bluetooth diagnostic6 incluido:
RootHide, Dopamine/rootless y rootful.
Pasaron 20 pruebas locales; las tres
pruebas exclusivas de dpkg/Linux se cubrieron en CI. CI pasó ocho pruebas
de empaquetado y omitió una de payload real, cubierta localmente.

Hashes, versiones y procedencia están en
[el registro de entrega](evidence/diagnostic15-verification.json).
Instalación, respuesta HCI y emisión física en el iPhone del tester: pendientes.

Instalación en el XS de referencia y aceptación del desbloqueo: pendientes;
el intento SSH no obtuvo conexión. No se cerró ni modificó la app del teléfono.
