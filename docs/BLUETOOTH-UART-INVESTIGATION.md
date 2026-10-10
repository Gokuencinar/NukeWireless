# iPhone 8 Plus: emisión no disponible

Investigación del 11 de octubre de 2026. Fuentes NukeWireless revisadas:
`ca10b07` (binarios diagnostic9 compilados desde `57a6e91`).
No modifica los binarios ni acredita emisión en un dispositivo nuevo.

## Evidencia del caso

El tester anterior corresponde a iPhone10,2, iPhone 8 Plus, iOS 16.7.4
(20H240), Dopamine/rootless. Su JSON incluye una sesión diagnostic8/20008,
interfaz integrada y componente Bluetooth `2.0.0~diagnostic2` ejecutado.
El usuario confirma que el nuevo build abre el catálogo; la versión de ese
último intento sigue sin verificarse. No se registra como aceptación de
diagnostic9 ni como prueba de emisión.

El diagnóstico anterior devuelve `hci_registry.stage=skywalk_registry`,
`Interface lookup failed: 0x00000000.`, `interface_pending=1`,
`channel_opened=false` y `hci_commands_submitted=0`.
La biblioteca acompañante está presente. El fallo observado no demuestra
que falte el paquete Bluetooth; ocurre antes de abrir el canal.
El crash de CoreUI/CoreImage del catálogo es un problema diferente.

## Qué hace el código actual

`NWBTNativeAvailability()` exige el contrato de iOS/Darwin y busca una instancia
de `AppleConvergedIPCRTIInterface`, protocolo `hci`, transporte `skywalk`, con
`IOSkywalkNexusUUID` válido. No implementa transporte UART como alternativa.
El antiguo transporte ACT/ACL permanece limitado a la referencia XS/16.3.1
y no sirve como fallback automático para este caso.

`--status` puede devolver `available=true` y `supported=false`: el ejecutable
está disponible pero no se admite la interfaz. El catálogo reduce ese resultado
a un booleano y muestra `bt.catalog.worker_required` ante cualquier falta de
disponibilidad, incluyendo interfaz no encontrada, error del proceso, módulo
antiguo o comprobación todavía pendiente. El booleano se captura al abrir;
si la comprobación termina después, no se actualiza esa pantalla. Esa carrera
también puede producir un aviso transitorio en hardware compatible, aunque
no explica por sí sola el fallo de registro guardado del tester.

## Contraste con fuentes primarias

- [IOKitUser, IOServiceGetMatchingServices](https://github.com/apple-oss-distributions/IOKitUser/blob/main/IOKitLib.c):
  el puerto nulo pide el puerto predeterminado; no implica una llamada inválida.
- [XNU 8792.61.2, IOUserClient.cpp](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/iokit/Kernel/IOUserClient.cpp):
  `internal_io_service_get_matching_services` puede devolver éxito con un
  iterador nulo; `IOUserIterator::withIterator(NULL)` devuelve NULL.
  [IOService.cpp](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/iokit/Kernel/IOService.cpp)
  deja el resultado nulo si no hay coincidencias. Por tanto, `0x00000000`
  es éxito de la consulta, no un código de fallo HCI ni prueba de canal listo.
  Son fuentes de referencia, no una extracción del kernel exacto 20H240.
- [InternalBlue, documentación iOS](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/doc/ios.md)
  distingue UART y PCIe y enumera iPhone 8 en UART. No enumera explícitamente
  el 8 Plus con iOS 16.7.4: es una pista fuerte, no validación de ese equipo.
- [InternalBlue, ios-proxy.m](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/ios/ios-proxy.m)
  busca `com.apple.uart.bluetooth` y usa un socket H4, en vez del nexus Skywalk.
  El código histórico no se copia ni se ejecuta: contiene constantes de
  termios y conexiones que necesitan contrastarse en la build objetivo.
- [XNU, kern_control.c](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/kern/kern_control.c)
  declara `net.systm.kctl.reg_list` de lectura y separa `CTLIOCGINFO`
  (consulta del registro) de la conexión al controlador.

La hipótesis principal es que el dispositivo requiere el transporte UART que
NukeWireless todavía no implementa. Instalar otra vez el mismo componente o
retirar la comprobación Skywalk no añade ese transporte. No se generaliza la
hipótesis a todos los chips A11/A12 ni se atribuye a una limitación de potencia.

## Datos preparados para el siguiente paso

`scripts/collect_bt_transport_readonly.sh` está dirigido a este caso Dopamine
rootless. Recoge modelo/kernel, versiones de paquetes, presencia del nombre
UART en la lista de controles (si las herramientas existen), existencia de
`/dev/btwake` sin abrirlo y `nwbt-run --diagnostics`.
No conecta al socket HCI, no cambia Bluetooth ni servicios y no instala nada.
No imprime la lista completa de controles. Una consulta fallida, herramientas
ausentes o nombre no observado se informa como **unknown**, no como ausencia
demostrada. En un unificado puede no existir el paquete separado `.bluetooth`;
su ausencia en dpkg-query no prueba que falte el ejecutable incluido.

Puede ejecutarse sin `su` ni `sudo`:

```sh
sh collect_bt_transport_readonly.sh > bluetooth-transport.txt 2>&1
```

La presencia de UART es únicamente evidencia para preparar el transporte:
no demuestra que permita conectarse, enviar comandos o emitir. Para confirmar
el caso todavía hacen falta el snapshot del tester y la versión instalada.
Después se podrá comprobar el ABI de H4, capacidades reales y recuperación
antes de integrar un backend. No se necesitan parches de firmware/WriteRAM
para esta investigación.

El aviso de UI debe separar comprobación pendiente, componente ausente,
componente antiguo y transporte no disponible, además de recibir la actualización
asíncrona. Se deja identificado para la siguiente revisión; los DEB ya generados
conservan el aviso y no se presentan como corregidos.

## Verificación de esta entrega

Se revisó la sintaxis POSIX con Bash y se comprobaron mediante funciones fixture
tres respuestas: nombre UART observado, otro nombre y fallo de lectura. Solo la
primera informa `yes`; las otras conservan `unknown`, sin exponer nombres ajenos.
También se comprobó la ruta de herramientas opcionales ausentes. Estas pruebas
validan el flujo del script, no el contenido binario de sysctl ni su disponibilidad
en el iPhone. No se ha ejecutado en un dispositivo, recompilado la app o generado
otro DEB: esta entrega contiene investigación y recogida de datos únicamente.
