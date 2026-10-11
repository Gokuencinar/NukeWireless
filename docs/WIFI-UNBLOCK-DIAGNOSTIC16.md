# Diagnostic16: desbloqueo Wi-Fi directo

App `2.0.0~diagnostic16` / 20016; Bluetooth `2.0.0~diagnostic6`, sin cambios.

## Evidencia y alcance

Diagnostic15 se instaló en iPhone XS, iOS 16.3.1 / RootHide. El usuario confirmó
la versión, pero Desbloquear dejó la mano roja. El registro contiene el hook
Objective-C instalado y el lanzamiento de un único bloqueo; no contiene su
limpieza. La inspección del ejecutable fijado identifica la entrada Swift
`0x100039610`, que construye `/bin/kill` y usa la ruta shell. Los controles Swift
pueden llamarla directamente sin pasar por el método de clase Objective-C.
No se atribuye por ello a una sola causa toda pérdida de conectividad.

El usuario indicó que solo bloqueó un equipo y que otros perdieron Internet,
recuperado al cerrar NukeWireless. La lectura posterior no encontró arpoison
activo. No se repitió el bloqueo. La causa de ese alcance sigue pendiente.

## Cambio

Se mantiene `unblockIPWithIp:` con la firma verificada `v24@0:8@16` y se añade
la entrada nativa del ejecutable fijado. Antes de instalar el hook se verifica
el segmento TEXT y los 16 bytes de la entrada y de su puente String/NSString
`0x1001152fc`. La regresión estática contrasta ambos con el baseline SHA fijado.
Se conserva la función original con sus dos palabras de String y su llamada.

Si MSHookFunction no está visible, se intenta cargar únicamente la biblioteca
API del bootstrap de la app: libsubstrate, libellekit o el framework Substrate.
Se exige archivo regular, propietario root y sin escritura de grupo/otros;
se conserva el handle mientras vive el hook. No se carga el injector de tweaks.
La distribución de API de ElleKit está descrita en su [Makefile](https://github.com/tealbathingsuit/ellekit/blob/main/Makefile)
y la firma en [Usage.md](https://github.com/tealbathingsuit/ellekit/blob/main/Usage.md).

Ambas rutas usan NWPerformWiFiUnblock. La guarda por hilo evita doble limpieza
de una misma IP si el método Objective-C llama a la entrada Swift. @finally
restaura la guarda incluso al fallar; se conserva la excepción nativa.
La limpieza existente solo señala la tarea propia aún activa, retiene ownership
si sigue viva y conserva la restauración ARP acotada. No se modifica el mecanismo
de bloqueo ni se declara probado su alcance físico.

El JSON añade `hooks.native_unblock`: true/false si está presente el adaptador,
null si no está disponible. El registro distingue resolución del backend,
instalación y entrada al hook. Un true demuestra instalación, no restauración
de Internet en el receptor.

## Verificación requerida

La regresión nativa cubre entrada directa, anidamiento de la misma IP,
repetición, excepción y recuperación de la guarda, además de ABI, superclase,
IP inválida y nil. Se mantienen UI, paquetes y pruebas UART anteriores.
No se realizará un bloqueo remoto automático. Antes de una prueba manual,
comprobar carga y `native_unblock`, identidad del cliente y puerta de enlace.
La pérdida general de conectividad y la aceptación de desbloqueo siguen pendientes.

## Validación de entrega (12 de octubre de 2026, Europe/Madrid)
Fuentes compiladas: `254e353f32062ce7df2dd1003aced56b489c9d43`.
Los cuatro workflows aprobaron:

- [Unified installer packaging](https://github.com/Gokuencinar/NukeWireless/actions/runs/38183157950)
- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/38183157898)
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/38183157900)
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/38183166607)

Las regresiones de ownership y fallo de wake, y UART con los valores del
tester, pasaron en macOS, junto con H4,
cancelación, EOF y propiedad del descriptor. También pasó la regresión de desbloqueo Objective-C
con entrada directa, anidamiento, recuperación de guarda, ABI y excepción. El simulador pasó 46 comprobaciones
y cuatro ciclos reales de segundo plano por idioma (español e inglés).

Se generaron los tres DEB unificados con Bluetooth diagnostic6 incluido:
RootHide, Dopamine/rootless y rootful.
Pasaron 20 pruebas locales; las tres
pruebas exclusivas de dpkg/Linux se cubrieron en CI. CI pasó ocho pruebas
de empaquetado y omitió una de payload real, cubierta localmente.

Hashes, versiones y procedencia están en
[el registro de entrega](evidence/diagnostic16-verification.json).
Aceptación física del desbloqueo, causa de la caída general y UART del tester: pendientes.

## Instalación y carga observadas

Se instaló el DEB unificado RootHide en el XS de referencia, iOS 16.3.1.
Se verificaron transferencias SHA-256, dpkg, versión 20016, commit compilado,
identidad CodeDirectory y fingerprints de los componentes frente a CI.
Se conserva `NukeWireless-diagnostic15-backup.deb`, además de la copia anterior.
No había arpoison, trabajador Bluetooth ni dpkg activos al instalar.
No se realizaron bloqueos, ni reinicios generales; solo se cerró NukeWireless.

El diagnóstico Bluetooth de solo lectura no abrió HCI ni cambió el servicio;
bluetoothd conservó su PID y no se observaron nuevos crashes relevantes durante
la instalación. El usuario abrió la app y confirmó diagnostic16. El diario
confirma las fuentes instaladas y `hooks.native_unblock: true` tras el escaneo.
El registro muestra carga de `/usr/lib/libsubstrate.dylib` y hook Swift instalado.
La lectura posterior muestra NukeWireless abierta y ningún arpoison activo.

La comprobación de los fingerprints nativos se ejecutó localmente sobre el
baseline fijado. Las regresiones de limpieza se ejecutaron en macOS CI.
No se confunden esos resultados con restauración real de Internet: falta
identificar el cliente de prueba antes de repetir el bloqueo. La causa de la
caída general continúa sin confirmar y no se publica una release.
