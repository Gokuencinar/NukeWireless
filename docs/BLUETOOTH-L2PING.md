# Bluetooth nativo: biblioteca de investigación

## Opciones de ping: candidata dev24 / app9

La pantalla **Información → Bluetooth** incorpora dos controles de incremento:

- Número de pings: de 1 a 20, limitado según el intervalo.
- Intervalo: de 1 a 5 segundos, en pasos de un segundo.
- Valores iniciales: 5 pings, intervalo de 1 segundo; se guarda la selección.
- Se exige `número × intervalo <= 20`. Si se aumenta el intervalo, el número
  se reduce automáticamente al máximo permitido. Los controles se desactivan
  durante el diagnóstico. La confirmación muestra ambos valores.
- Cada respuesta conserva un plazo de un segundo; los intervalos mayores
  añaden espera entre solicitudes, atendiendo cancelación y eventos del enlace.
- Ventana de pings de 20 segundos; conectar, desconectar y restaurar requieren
  tiempo adicional. Los retrasos o errores pueden dejar resultados parciales.
- Los límites se comparten entre UIKit y el transporte y también se validan
  en el helper antes de cambiar el servicio Bluetooth.
- El watchdog del runner es de 45 segundos, la recuperación independiente
  tiene un máximo de espera de 60 segundos y la app espera hasta 85 segundos.
  La cancelación sigue disparando la recuperación antes de esos máximos.

`nwbt-run --ping ADDRESS COUNT INTERVAL_SECONDS` admite exclusivamente enteros
dentro de esos límites. La forma previa `--ping ADDRESS` y el inspector anterior
mantienen los 5 pings con intervalo de 1 segundo. La app detecta si el módulo
admite opciones: con app8 conserva el diagnóstico predeterminado y pide
actualizar el módulo para utilizar una selección distinta. Textos en español
e inglés; resultados persistentes con número solicitado e intervalo.

Estado de esta ampliación: ambos paquetes compilados e inspeccionados, sin
instalación ni prueba funcional en el iPhone. Las evidencias de dev23/app8
descritas abajo corresponden al diagnóstico original de cinco pings.

- App dev24: compilación `37202560686`, commit `3901926`, SHA-256 del `.deb`
  `bc31460ef154a822a2b355d93249710151ac3d906ce4e6a62070a7147e29df66`.
- Módulo app9: compilación `37202623622`, commit `e097884`, SHA-256 del `.deb`
  `701890dae293d1ed49691ea146bcd8ba1a2f2e4e27054d179f11afc0b6687199`.
- Comparación de paquetes: solo cambian metadatos de versión, traducciones y
  el adaptador UIKit. Ejecutable original, dos bibliotecas de rutas, `aegis`,
  `arp-scan` y `arpspoof` mantienen exactamente los bytes de dev23.
- Para revertir esta ampliación: reinstalar los paquetes dev23 y app8.

**Estado: cinco ecos L2CAP reales comprobados por SSH; interfaz Bluetooth
integrada en dev23 y helper separado con recuperación independiente.** Dev19
tiene la confirmación previa de las funciones existentes. El usuario confirmó
la pantalla Bluetooth y cinco respuestas desde el botón en dev23/app8; el
registro local del helper confirma ecos, desconexión y recuperación.

El alcance solicitado es exclusivamente el Bluetooth del iPhone. No se utiliza
un adaptador Linux ni un servidor externo. El ping propuesto es un diagnóstico
finito: cinco solicitudes pequeñas, intervalo de un segundo, timeout por
respuesta, plazo total y cancelación. La primera prueba funcional se realizó
por SSH. Se comprobaron los errores con los auriculares apagados y después cinco
respuestas desde la interfaz, con el accesorio preparado.

## Paquete separado

- ID: `com.gokuencinar.nukewireless.bluetooth`.
- Motor HCI/ACL: `probe8` validó cinco ecos reales.
- Candidata integrada: app `1.0.25+rh25.5~dev23`, módulo `0.0.3~app8`.
- Esquema de esta candidata: RootHide; binarios arm64, deployment target iOS 15.
- Biblioteca: `/usr/lib/NukeBluetoothBridge.dylib`.
- Inspector: `/usr/bin/nwbt-inspect --inspect`.
- Helper de la app: `/usr/bin/nwbt-run`; firma y permisos se aplican durante
  `postinst`. Se comprueba el ejecutable padre bajo el mismo bootstrap antes
  de elevar los UID de un llamante mobile. Operadores root también pueden
  ejecutar el diagnóstico.
- Fuente: [NWBTL2Ping.m](../src/bluetooth/NWBTL2Ping.m),
  [NWBTController.m](../src/bluetooth/NWBTController.m) y
  [NWBTInspector.m](../src/bluetooth/NWBTInspector.m).
- No tiene daemon, filtro de inyección ni constructor con efectos sobre Bluetooth.
  La inspección pasiva carga bibliotecas del sistema, busca símbolos y enumera
  metadatos Objective-C. `--transport-code` copia secciones acotadas de código
  y constantes de AppleConvergedTransport para análisis local de su ABI.
- `nwbt-inspect --controller-info --exclusive` intenta abrir HCI y enviar
  únicamente **Read Local Version Information** al controlador local. Comprueba
  UID root, modelo/iOS, SHA-256 de la sección de código y estado apagado de
  Bluetooth antes de llamar al transporte. No conecta dispositivos remotos.
  Tiene timeout de lectura, liberación de handles y watchdog de 20 segundos
  que termina exclusivamente el helper si una llamada privada queda atascada.
- `nwbt-inspect --skywalk-open --exclusive` es una comprobación separada de
  apertura/cierre del canal HCI real, localizado por IORegistry. No consume ni
  escribe slots. Tiene las mismas guardas de ABI, root, Bluetooth apagado y
  watchdog. No enciende el controlador ni llama selectores de configuración.
- `--l2ping DIRECCIÓN --exclusive` abre HCI y ACL, consulta buffers, solicita
  una conexión BR/EDR y envía hasta cinco ecos de ocho bytes. Verifica identificador
  y contenido de cada respuesta. No crea claves de emparejamiento, canales de
  audio ni conexiones a otros destinos. La dirección procede del argumento;
  no está incorporada en fuentes ni catálogos.
- La inspección pasiva declara `l2ping_implemented: true`,
  `bluetooth_packets_sent: 0` y `l2ping_verified: false`: sus resultados no
  sustituyen la ejecución de un eco. La comprobación de firmas ACT sigue
  siendo investigación; el motor utiliza el transporte Skywalk contrastado.

Se comprobó su ejecución únicamente en **iPhone XS (`iPhone11,2`), iOS 16.3.1
(20D67), Dopamine RootHide**. El deployment target no valida otros iOS ni
otros jailbreaks. Los entitlements incluyen los cuatro permisos base
documentados por [RootHide](https://github.com/roothide/Developer/blob/main/entitlements.md).
El diagnóstico exclusivo añade acceso a AppleBluetoothModule/AppleConvergedIPC
y las clases AppleBTHciUC, AppleBTMgmtUC y AppleConvergedIPCUserClient, observados
en la firma del bluetoothd de este dispositivo. No se copiaron sus permisos
de NVRAM, task_for_pid, DriverKit ni la firma completa del daemon.

## Nueva investigación y candidata probe1

- [Actions 37172118854](https://github.com/Gokuencinar/NukeWireless/actions/runs/37172118854)
  compiló `inspect2` (`ed5b5d8`). Se instaló y ejecutó el inspector y la captura
  de código sin error. Se obtuvo la sección `__TEXT.__text` de 63 748 bytes.
- SHA-256 de dicha sección:
  `16278d023790c1d38a796b31b7c52d4a105916fa7b9be6995b0ec5e3cf91ffed`.
- [Actions 37172561306](https://github.com/Gokuencinar/NukeWireless/actions/runs/37172561306)
  compiló `probe1` (`16706cf`). El `.deb` instalado tiene SHA-256
  `0f94755f31e7df5042aa8f93e8dbad2a93e48011e4c3e67021394b18a9b1fc17`.
  Su inspección pasiva terminó con código 0; la app conserva dev19.
- Con Bluetooth apagado en Ajustes, `probe1` terminó con `bti_open`; no llegó
  a enviar comandos HCI. La apertura directa de HCI en `probe2` también falló.
- `probe3` incorpora la API pública OSLogStore, con alcance exclusivo al
  proceso del helper. Su registro muestra `failed to open 0xe00002c7`.
  Apple define este valor como `kIOReturnUnsupported` en
  [IOReturn.h](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/IOReturn.h).
  No prueba denegación de permisos ni que el canal esté ocupado.
- IORegistry muestra AppleConvergedIPCOLYBTControl, interfaces RTI hci/sco/acl
  con transporte Skywalk y debug con userclient. No hay un dispositivo CBTI.
  Los identificadores de nexus se conservan solo localmente y se consultan
  dinámicamente; no se incluyen identificadores del dispositivo en el código.
- `probe4` compiló en
  [Actions 37173561387](https://github.com/Gokuencinar/NukeWireless/actions/runs/37173561387),
  se instaló y ejecutó sin error. Su paquete tiene SHA-256
  `87f912061bbc9c438c936cfae9f2c0cff1ed164c469bdd609cd14963b8b1eea3`.
  Capturó además 1445 bytes de constantes y 1085 bytes de cadenas del transporte.
  El código y sus cadenas describen una implementación PCI diferente de la
  ruta Skywalk que BlueTool implementa directamente. Esto justifica investigar
  esa ruta; no demuestra todavía una apertura funcional.
- El usuario dispone de unos Mi True Wireless EBs Basic 2 como posible destino.
  Su dirección se localizó en los dispositivos emparejados de Windows y se
  conserva exclusivamente en el entorno de trabajo local.

### ABI contrastada para el diagnóstico

La captura de código del transporte y los bloques de bluetoothd permiten
contrastar estos puntos, sin ejecutar las funciones de transferencia aún:

| Interfaz | Evidencia en iOS 16.3.1 |
| --- | --- |
| InitParameters | Escribe 0x58 bytes; inicializa todo a cero y QoS en offset 0x50 a 0x15 |
| Create | Configuración en x0, puntero de salida de 64 bits en x1; devuelve 0/1 |
| Free | Puntero al handle en x0; lee su valor y pone cero al liberar; devuelve 0/1 |
| Write/Read | Handle, buffer, tamaño de 32 bits, puntero de salida de 32 bits, timeout en milisegundos y callback opcional de liberación |
| Timeout | El cuerpo multiplica los milisegundos por 1 000 000; -1 espera indefinidamente, por lo que la candidata utiliza plazos finitos |
| Configuración | Tipo en 0x00, queue en 0x08, bloque de estado en 0x10, timeout en 0x18, flags en 0x20 |
| Bloque de estado | Los descriptores de bloques HCI/ACL de bluetoothd declaran `v28@?0i8^v12^v20`: void(int, void*, void*) |
| Read síncrono | Rechazado con flags bit 2 activo; HCI de la candidata usa flags 8 |

Las cabeceras del protocolo HCI de
[BlueZ](https://github.com/bluez/bluez/blob/master/lib/bluetooth/hci.h)
se consultaron para el opcode y formato de Read Local Version Information.
No se portó su transporte Linux ni se utilizó su backend de sockets.

### Ruta Skywalk contrastada

En BlueTool de 20D67, `0x100003fac` llama `os_channel_create(uuid, 0)` y los
callsites siguientes consultan el tamaño de buffer y los slots TX/RX. Las
firmas se contrastan con el código de Apple
[XNU 8792.61.2, os_channel.h](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/skywalk/channel/os_channel.h)
y [IOKitLib.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/IOKitLib.h).
`probe5` consulta hci/skywalk bajo AppleConvergedIPCRTIInterface y busca el
IOSkywalkNexusUUID de sus hijos. Abre puerto 0, lee atributos y cierra el canal.
No llama los selectores 3/5 de AppleBluetoothModule observados en BlueTool:
su efecto sobre alimentación/configuración no está verificado.

La candidata `probe5` compiló en
[Actions 37173878281](https://github.com/Gokuencinar/NukeWireless/actions/runs/37173878281)
desde `5728732`. SHA-256 del paquete instalado:
`3c4d72a57a336284e791bca988c38c083d4accbc8922648ee440f6f65ad1cd71`.
La inspección y captura pasivas terminaron con código 0. La apertura Skywalk
terminó con código 1 y `errno=16`, `Resource busy`, sin crash ni paquetes.
El canal se localiza correctamente pero no se ha abierto. No se llegó a leer
atributos ni a consumir slots. `bluetoothd` sigue ejecutándose en
`user/501/com.apple.bluetoothd` aun con Bluetooth apagado en Ajustes.
Esto permite proponer una prueba de exclusividad con recuperación acotada,
pero no demuestra por sí solo que bluetoothd sea el propietario que bloquea
la apertura. En las pruebas de `probe5` no se detuvo, deshabilitó ni reinició
ese servicio.

### Prueba exclusiva autorizada: probe6

El usuario autorizó detener temporalmente el servicio Bluetooth y restaurarlo.
`disable` más `SIGTERM` no mantuvo el servicio detenido: launchd volvió a
iniciarlo con otro PID. Se restauró su estado habilitado. Un intento posterior
se agotó durante la comprobación previa, antes de retirar el servicio.

`probe6` hace opcional la recogida de OSLog (`NWBT_PROCESS_LOGS=1`) y registra
fases acotadas en stderr. Además se utiliza el `timeout` instalado en el
bootstrap, con límite de 25 segundos y SIGKILL de recuperación a los dos
segundos adicionales, exclusivamente para este helper.

[Actions 37176758909](https://github.com/Gokuencinar/NukeWireless/actions/runs/37176758909)
compiló `97f6fa8`. SHA-256 del `.deb` instalado:
`2a0973b9192cb612388c9de1651d6464ee8dbfebc41fa1cccceedb3deeb6d5f1`.
La comprobación previa devolvió errno 16. Tras `bootout` del servicio verificado
`user/501/com.apple.bluetoothd`, el helper terminó con código 0 y:

```json
{"stage":"skywalk_opened","slot_buffer_size":512,"tx_slots":16,"rx_slots":16,
 "local_hci_commands_sent":0,"remote_bluetooth_packets_sent":0,"l2ping_verified":false}
```

Se cerró el canal y se restauró el servicio con `bootstrap user/501` usando
su plist original bajo `/rootfs/System/Library/LaunchDaemons`, `enable` y
`kickstart`. `launchctl print` confirmó estado `running` con nuevo PID.
La recuperación independiente a los 45 segundos estaba programada antes de
retirar el servicio y no requiere que SSH continúe conectado.

`probe7` mantiene la apertura sin paquetes y añade `--skywalk-info --exclusive`:
un único HCI Read Local Version Information, drenaje previo de RX acotado,
buffers/slots limitados, respuesta en tres segundos y cierre del canal. Las
funciones y estructura de 64 bytes se contrastan con XNU 8792.61.2. En BlueTool,
`0x100005414` elimina el prefijo H4 antes de escribir el ring; el inspector envía
solo `01 10 00`. La candidata aún no añade ACL, conexión remota ni eco L2CAP.

[Actions 37176928783](https://github.com/Gokuencinar/NukeWireless/actions/runs/37176928783)
compiló `c74fce5` (`probe7`). Se instaló y obtuvo una respuesta Command Complete
real: HCI version 9, revision 2831, fabricante 15, LMP subversion 33005.
SHA-256 del paquete: `669a40ded2e775f7a52784b5bec610e63e6f2ef976d21560b255e1f1a44bd742`.

### Cinco ecos reales: probe8

[Actions 37177516897](https://github.com/Gokuencinar/NukeWireless/actions/runs/37177516897)
compiló `5b3f52b`, exclusivamente el módulo Bluetooth. SHA-256 del paquete
instalado: `8c8dc1a2ce286fa6ff893b7405907c20e890def70b10442f8a9d3cd472a60639`.
`dpkg-query` confirmó `0.0.2~probe8` y que NukeWireless conserva dev19.

El usuario preparó sus Mi True Wireless EBs Basic 2 en modo de emparejamiento,
desconectados de la laptop. Autorizó la prueba exclusiva temporal. La dirección
se conserva solo en archivos locales ignorados. El helper devolvió código 0:

| Eco | Respuesta comprobada | RTT observado |
| --- | --- | --- |
| 1 | Sí, mismo identificador y ocho bytes | 16,71 ms |
| 2 | Sí | 30,21 ms |
| 3 | Sí | 32,99 ms |
| 4 | Sí | 25,69 ms |
| 5 | Sí | 28,52 ms |

El controlador devolvió Connection Complete para la dirección solicitada,
créditos ACL y finalmente Disconnection Complete para ese handle. Se enviaron
cinco ecos y una respuesta auxiliar L2CAP Information Response. El helper
cerró ambos canales; la recuperación inmediata confirmó bluetoothd `running`.
La recuperación independiente se había programado antes de retirar el servicio.
No se modificaron firmware, BlueTool, bluetoothd ni sus plists.
La comprobación posterior confirmó el servicio habilitado y en ejecución;
no aparecieron nuevos registros de cierre de `nwbt-inspect`.

El formato ACL se contrastó con `skywalk_write_channel` de bluetoothd 20D67
en `0x100061d80`: escribe dos bytes de handle/flags y dos de longitud,
seguidos del cuerpo, sin prefijo H4. Las constantes HCI y L2CAP se contrastan
con las cabeceras del protocolo de BlueZ; no se utiliza su transporte Linux.

Esta prueba no valida otros modelos, builds de iOS, jailbreaks ni todos los
accesorios. Los errores de emparejamiento siguen sin prueba funcional.

## Integración dev22: Información → Bluetooth

La nueva pantalla usa UIKit y los mismos colores de la app. Tiene entrada de
dirección Bluetooth clásica, instrucciones, confirmación para cinco pings,
cancelación y resultados individuales con RTT. Los textos se incluyen en
español e inglés. Recuerda solo la dirección introducida en las preferencias
locales; el paquete no contiene la dirección de los auriculares del usuario.

El trabajo se ejecuta fuera del hilo principal, en `nwbt-run`. La app no enlaza
la biblioteca privada Bluetooth: si falta el módulo, muestra un aviso. El
helper recibe argv validados, sin shell, y comprueba root, ABI y estado apagado.
Antes de retirar el servicio crea un proceso independiente, espera su señal
de disponibilidad y lo arma. Ese hijo conserva el bloqueo exclusivo y restaura
Bluetooth al terminar, al cerrarse el pipe del worker o después de 45 segundos.
La app cancela al pasar a segundo plano; el hijo de recuperación no depende
del tiempo de ejecución que iOS conceda a la app.

El helper resuelve `launchctl` y su lock desde su ruta física bajo el bootstrap,
porque `/bin/launchctl` no existe en el sistema original de este iPhone. Los
argumentos del bootstrap mantienen el plist original bajo `/rootfs`. No se
instala un daemon permanente, se escribe firmware ni se modifica bluetoothd.

### Compilaciones e instalación

- App: [Actions 37178460542](https://github.com/Gokuencinar/NukeWireless/actions/runs/37178460542),
  commit `026aa28`, compilación sin ejecutar tests. Paquete dev20 instalado:
  `677b283250ae38c5c807ef98e17b082c80ec98007cda3b295da8d22d0e4b4cbf`.
- Supervisor `app3`: [Actions 37178980756](https://github.com/Gokuencinar/NukeWireless/actions/runs/37178980756),
  commit `36cdeaa`. Paquete instalado:
  `dffb58b48cafa7c1e64d99034e23b0f4421aebcaeae02b21424a3101432747bb`.
- Supervisor `app4`: [Actions 37179266397](https://github.com/Gokuencinar/NukeWireless/actions/runs/37179266397),
  commit `43a2050`; corrige que una cancelación mostrara un timeout de conexión.
  SHA-256 del paquete:
  `47cc36717e6f38084b06f504230931ac2162ef6c62274b06d20e1a2a0ae40cc6`.

El ejecutable de la app, aegis, arp-scan, arpspoof y ambas bibliotecas originales
de rutas tienen los mismos SHA-256 en dev19 y dev22. Se conservó una copia de
dev19 en `/var/mobile/Documents/NukeWireless-dev19-backup.deb`.

La candidata final añade sincronización entre la cancelación de la interfaz y
la recogida del proceso hijo: tras terminar o devolver `ECHILD`, el PID deja de
ser un destino de señales, también durante el plazo de cancelación. El runner
restaura `SIGCHLD` antes de crear sus hijos para poder observar su finalización.

Compilaciones finales:

- App `dev22`: [Actions 37180047210](https://github.com/Gokuencinar/NukeWireless/actions/runs/37180047210),
  commit `79f474f`; compilación sin tests. SHA-256 del paquete:
  `c580ff135baa5e8ec409fda15fd5a87c4b3d0694985c7615116d822d6b932928`.
- Módulo `app5`: [Actions 37179650167](https://github.com/Gokuencinar/NukeWireless/actions/runs/37179650167),
  commit `d142afe`; compilación sin tests. SHA-256 del paquete instalado:
  `1ce58e94a22448e66d46262c2d2f9938a9fbed9d682f066a4b3bf39e96b86c7c`.

`dpkg-query` confirmó `install ok installed` para app `dev22` y módulo `app5`.
El primer intento de instalar la app agotó la espera SSH y conservó dev20.
Se comprobó que no quedaba un proceso dpkg activo; después se repitió con
`nohup`, salida local y hash del archivo remoto verificado. El registro confirma
unpack, configure y triggers completos. La instalación ya no depende de que
SSH conserve abierta su salida. La comprobación posterior volvió a confirmar
ambas versiones, bluetoothd en estado `running` y ausencia de nuevos registros
de cierre de la app o sus helpers respecto al inventario previo. La invocación
desde un shell mobile siguió rechazada por permisos, como se esperaba.

### Comprobaciones sin auriculares encendidos

`app3` se ejecutó mediante SSH con el destino propio autorizado apagado:

- Consulta pasiva: módulo disponible para el modelo y versión inspeccionados.
- Dirección inválida: rechazada antes de acceso al servicio.
- Invocación desde un shell mobile: rechazada por la whitelist del padre.
- Destino apagado: HCI `0x04`, cero ecos enviados y servicio restaurado por el
  supervisor; `launchctl print` confirmó estado `running`.
- Cancelación durante el intento: Create Connection Cancel confirmado por
  el controlador y restauración confirmada. El mensaje incorrecto de timeout
  detectado en esta prueba motivó `app4`.
- SIGKILL dirigido exclusivamente al PID del worker: el hijo independiente
  restauró bluetoothd; el estado `running` se comprobó desde otra sesión SSH.

`app4` confirmó después que la cancelación devuelve `error_code: cancelled`.
`app5` repitió el caso de accesorio apagado: HCI `0x04`, cero ecos enviados,
`service_restored: true` y servicio `running` observado desde otra sesión SSH.
La cancelación en `app5` confirmó Create Connection Cancel, `error_code:
cancelled`, cero ecos y restauración. Un intento previo agotó la espera de
salida SSH; el servicio ya estaba de nuevo en ejecución y no había nuevos
crashes. La repetición con drenaje simultáneo de stdout/stderr terminó con
JSON completo. No se atribuye ese timeout a una causa confirmada.

### Auriculares encendidos: supervisor app5

El usuario volvió a preparar sus auriculares propios, encendidos y sin
emparejar. `nwbt-run --ping` se ejecutó por SSH con el módulo `0.0.3~app5`.
Devolvió código 0, cinco solicitudes y cinco respuestas verificadas:

| Eco | RTT observado |
| --- | --- |
| 1 | 16,32 ms |
| 2 | 36,76 ms |
| 3 | 15,72 ms |
| 4 | 14,06 ms |
| 5 | 8,92 ms |

Se confirmó Disconnection Complete, `disconnect_confirmed: true` y
`service_restored: true`. Una consulta independiente confirmó bluetoothd
`running`. Este resultado comprueba el ciclo completo del supervisor con el
accesorio, sin intervención manual para restaurar el servicio. Su dirección
continúa solo en archivos locales ignorados.

El usuario confirmó la pantalla y después comunicó que el botón de dev22
termina con «Exclusive Bluetooth controller access could not be obtained».
No era una ausencia de resultados: el fallo sí aparece en la sección Results.
Las comprobaciones posteriores no mostraron nuevos crashes y bluetoothd
continuaba en ejecución. El éxito por SSH no valida este contexto de llamada.

### Dev23 y app6: resultados persistentes y diagnóstico del acceso exclusivo

- Dev23 guarda el último JSON en preferencias locales, refresca directamente
  el controlador al terminar, muestra el resumen también arriba y desplaza
  la lista hasta Resultados. Registra fases y stderr acotado para distinguir
  errores de lanzamiento, lectura y apertura, sin guardar el destino en ese
  registro. La dirección introducida conserva su preferencia local anterior.
- App6 captura `errno` inmediatamente después de `os_channel_create`, antes
  de `fputs`, y conserva el resultado del preflight o la retirada del servicio
  si falla la exclusividad. La captura tardía era un defecto de código; no era
  la causa del rechazo finalmente observado en app7.
- App: [Actions 37200033425](https://github.com/Gokuencinar/NukeWireless/actions/runs/37200033425),
  commit `d3d6c52`, SHA-256 del paquete instalado:
  `64782dd109cfe412f1f4a076c0527d045cc71d11a28bfcd32159207eadbe3dc6`.
- Módulo: [Actions 37200273225](https://github.com/Gokuencinar/NukeWireless/actions/runs/37200273225),
  commit `eef1d3d`, SHA-256 del paquete instalado:
  `75593a87320c3b22bac52e1679d2deb8698cb5de422e485590914410a7f11282`.
  Su consulta pasiva devuelve `version: 0.0.3~app6`; el build rechaza versiones
  distintas entre la cabecera y el manifiesto.
- Ambas compilaciones completaron sin ejecutar tests. `dpkg-query` confirmó
  la instalación de dev23/app6. Los hashes de los binarios originales de red
  y de rutas se conservan respecto a dev19.

El usuario repitió la prueba y confirmó el mismo error con app6.
App7 añadió un registro JSON accesible únicamente a root (modo 0600,
propietario root) en `var/run/nukewireless-bluetooth-app.json` dentro del bootstrap.
Guarda respuesta y UID/PID del llamante, sin dirección de destino; las consultas
pasivas y el hijo de recuperación no lo sustituyen. El usuario reprodujo el
fallo de nuevo y el registro capturó UID original 501 y:

```json
{"error_code":"exclusive","exclusive_phase":"preflight",
 "preflight":{"stage":"skywalk_opened","slot_buffer_size":512,
              "remote_bluetooth_packets_sent":0}}
```

La apertura previa funcionaba, pero el runner solo admitía `skywalk_open` con
errno EBUSY, el resultado observado desde SSH. App8 admite además la apertura
validada `skywalk_opened` que ya cierra el canal en `finally`. Después mantiene
el mismo bloqueo, recuperación armada y retirada comprobada del servicio antes
del motor de ecos. Continúa rechazando los demás fallos del preflight.

App7 compiló desde `7a074f8` en
[Actions 37200825415](https://github.com/Gokuencinar/NukeWireless/actions/runs/37200825415),
SHA-256 `badec2e869f57ce0904ceb67299edbbb5b5758afc7eeb06cc11db34c584fcbb2`.
App8 compiló desde `eee2cc5` en
[Actions 37201062696](https://github.com/Gokuencinar/NukeWireless/actions/runs/37201062696),
SHA-256 `62ed83a51b70795540cfd44e727c2d2a2c09a9ae5aa18f8ebd67ceb41676ad41`.
La instalación y consulta pasiva confirmaron versión `0.0.3~app8`.
No se añadieron entitlements ni se cambió la ABI de los canales para esta
corrección. Los workflows de ambos módulos compilaron sin ejecutar tests.

### Cinco respuestas desde el botón real: dev23/app8

El usuario confirmó «5 de 5 pings respondidos». El registro del helper capturó
UID original 501, versión `0.0.3~app8`, `preflight_stage: skywalk_opened`, cinco
solicitudes y cinco respuestas con identificador y nonce verificados:

| Eco | RTT observado |
| --- | --- |
| 1 | 18,38 ms |
| 2 | 31,91 ms |
| 3 | 9,58 ms |
| 4 | 30,52 ms |
| 5 | 16,93 ms |

La respuesta incluye `disconnect_confirmed: true`, `service_restored: true`
y ausencia de error. Esta ejecución confirma el recorrido desde el botón
hasta el motor, el retorno de resultados y la recuperación del servicio en
el iPhone XS / iOS 16.3.1 / Dopamine RootHide observado. La interfaz y los
resultados fueron confirmados por el usuario; no se deducen de `uiopen`.
La consulta independiente posterior confirmó bluetoothd `running`, ambos
paquetes instalados y ausencia de nuevos registros de cierre. El registro
completo, incluido el PID efímero, permanece solo en archivos locales ignorados. La dirección Bluetooth no se publica.
La captura remota de pantalla no estuvo disponible: agotó su plazo de conexión.
No se instalaron herramientas de depuración ni se cambió Developer Mode para
suplirla. `uiopen` confirma que la orden de abrir se aceptó; no confirma por sí
solo la vista mostrada. La confirmación desde la interfaz llegó posteriormente en la prueba dev23/app8 anterior.

## Evidencia de compilación, empaquetado y carga — 4 de octubre de 2026

1. [Actions 37170874373](https://github.com/Gokuencinar/NukeWireless/actions/runs/37170874373)
   compiló la biblioteca y el inspector desde `a9186f7`. El workflow
   `bluetooth-inspector.yml` realiza compilación; no ejecuta pruebas.
2. El empaquetador verifica hashes de artefactos y fuentes, arquitectura,
   deployment target y dependencias Mach-O antes de producir el `.deb`.
3. SHA-256 de la candidata instalada:
   `446c0153b0eae468c0584d6a4ecc09bba776e1a264b9900368532d845d9cc2dd`.
4. `dpkg-query` confirmó `install ok installed 0.0.1~inspect1+rh2` y conservó
   `install ok installed 1.0.25+rh25.5~dev19` para la app.
5. El inspector terminó con código 0 y devolvió JSON válido. Cargó
   `AppleConvergedTransport.dylib`, `CoreBluetooth` y `BluetoothManager`.
   Encontró `AppleConvergedTransportInitParameters`, `Create`, `Read`, `Write`,
   `Free`, `IsValid` y `RegisterEventBlockQ` mediante `dlsym`.
6. Entre los métodos inspeccionados aparecen `CBClassicPeer.openL2CAPChannel:`,
   `CBPeripheral.openL2CAPChannel:` y métodos de gestión de canales. No se
   encontró un selector de eco/ping entre las clases CB/Bluetooth/BT cargadas
   e inspeccionadas. Esto no demuestra que el daemon carezca de funciones internas.

Los resultados y registros del dispositivo se conservan localmente en
`work/audit/bluetooth-inspect1-device.json`; no se suben archivos del sistema a Git.

### Reparaciones de carga

La primera instalación no cargó la biblioteca por un rechazo de dyld (`errno=1`).
Se añadieron los permisos base de RootHide a la firma del ejecutable y firma
SHA-256 a la biblioteca. La revisión `rh1` pasó a fallar en PatchLoader:
los archivos vacíos con sufijo `.roothidepatch` se intentaban abrir como dylibs.
El crash report identifica exactamente ese intento. La revisión `rh2` elimina
esos archivos; la ejecución posterior terminó correctamente.

El sufijo es un enlace a un módulo de parche real, según
[DynamicPatches](https://github.com/roothide/DynamicPatches), y no un marcador
vacío. Esta biblioteca no necesita dicho parche. La dependencia interna usa
`@rpath/NukeBluetoothBridge.dylib` con `@executable_path/../lib` en el inspector;
la ruta y su carga se observaron en este bootstrap. No se ha integrado ese
enlace en el ejecutable de NukeWireless.

## Fuentes y análisis previo del transporte

- [l2ping de BlueZ](https://github.com/bluez/bluez/blob/master/tools/l2ping.c)
  depende del transporte Linux `PF_BLUETOOTH`/`BTPROTO_L2CAP`. Recompilarlo
  para arm64 no crea ese transporte en iOS.
- [CoreBluetooth openL2CAPChannel](https://developer.apple.com/documentation/corebluetooth/cbperipheral/openl2capchannel(_:))
  abre un canal con un PSM. No equivale al eco del canal de señalización L2CAP.
- [IOBluetooth sendL2CAPEchoRequest](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/sendl2capechorequest(_:length:))
  pertenece al framework de macOS; no valida una interfaz disponible en iPhone.
- [InternalBlue para iOS](https://github.com/seemoo-lab/internalblue/blob/f524380672564dc4869f3d9a6cbcdeaf5b8a6b85/doc/ios.md)
  documenta transportes de investigación UART/PCIe, marca el XS como no probado
  y requiere desactivar Bluetooth. Sus declaraciones no validan iOS 16.3.1.
- En copias locales autorizadas de `BlueTool` y `bluetoothd` del dispositivo
  hay referencias a AppleConvergedTransport. El segundo contiene mensajes de
  recepción de ecos L2CAP, pero no exporta una función de ping localizada en
  esta revisión. Un texto de log no prueba un punto de entrada ni una firma.

La revisión estática de los callsites de `bluetoothd` revela una incompatibilidad
con las declaraciones antiguas de InternalBlue: en `0x1000629cc`,
`0x100062a10` y `0x100062a54`, la llamada a `AppleConvergedTransportFree` recibe
la **dirección** de la variable que guarda el transporte; el código antiguo
declara/pasa el valor. Los callsites de `Write` usan una variable de salida de
32 bits. No se invocó ninguna de esas funciones. Estos datos son evidencia para
reconstruir su ABI; no constituyen todavía un contrato completo de parámetros,
callbacks, propiedad del transporte ni cancelación.

SHA-256 de los binarios observados:

- `BlueTool`: `9e49c69d4e74d36db823aa85b0b5553c3ce4c4620ca3c45bfcbd01d88de8ce00`.
- `bluetoothd`: `b33953b06d4644377b936b000546d9976aadd3d3664a14ff075783a89d6ed837`.

RootHide presenta el bootstrap como `/` para sus herramientas. El sistema real
se inspeccionó mediante `/rootfs`, como documenta
[RootHide Developer](https://github.com/roothide/Developer/blob/main/roothide.md).
Los frameworks están en la caché compartida de dyld; que no exista un archivo
individual en SFTP no significa que el framework no esté disponible.

La ruta Skywalk y los ecos reales quedaron comprobados después de este análisis,
en `probe7` y `probe8`. `nwbt-run` añade gestión autónoma de exclusividad y
recuperación, comprobada por SSH en el caso negativo y al interrumpir el worker.
Su invocación desde la interfaz quedó comprobada en dev23/app8. No debe llamarse
el inspector crudo `--l2ping` dejando el servicio retirado sin programar
recuperación independiente antes. El motor de la biblioteca no manipula
servicios por sí mismo; esa responsabilidad pertenece al runner.

## Construcción y retirada

En macOS con Xcode:

```sh
bash scripts/build_bluetooth_inspector.sh
```

Descargar el artefacto `nuke-bluetooth-inspector` de esa misma compilación y
empaquetar con Python:

```sh
python scripts/build_bluetooth_deb.py --artifact RUTA_AL_ARTEFACTO
```

El `.deb` queda en `dist/bluetooth/`, excluido de Git. No se creó una release
de Bluetooth. La firma se aplica en `postinst` con `ldid` dentro de RootHide.
Para retirar exclusivamente el módulo:

```sh
dpkg -r com.gokuencinar.nukewireless.bluetooth
```

NukeWireless no depende de este paquete de investigación. Para volver a la app
anterior conservada en este iPhone:

```sh
dpkg -i /var/mobile/Documents/NukeWireless-dev19-backup.deb
```

La reversión de la app y la retirada del módulo son operaciones separadas.
