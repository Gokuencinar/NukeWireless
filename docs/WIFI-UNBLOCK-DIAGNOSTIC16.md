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
