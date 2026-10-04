# Bluetooth nativo: biblioteca de investigación

**Estado: cinco ecos L2CAP reales enviados y respondidos por unos auriculares
propios desde el iPhone, con cierre de conexión confirmado y bluetoothd
restaurado.** La app continúa en dev19, cuyas funciones
el usuario confirmó. Este paquete independiente no es una nueva versión de la
app ni añade un botón de ping.

El alcance solicitado es exclusivamente el Bluetooth del iPhone. No se utiliza
un adaptador Linux ni un servidor externo. El ping propuesto es un diagnóstico
finito: cinco solicitudes pequeñas, intervalo de un segundo, timeout por
respuesta, plazo total y cancelación. La prueba funcional se realizó por SSH;
la integración y ejecución autónoma desde la interfaz de la app siguen pendientes.

## Paquete separado

- ID: `com.gokuencinar.nukewireless.bluetooth`.
- Versión instalada: `0.0.2~probe8`; incluye el motor de eco HCI/ACL.
- Esquema de esta candidata: RootHide; binarios arm64, deployment target iOS 15.
- Biblioteca: `/usr/lib/NukeBluetoothBridge.dylib`.
- Inspector: `/usr/bin/nwbt-inspect --inspect`.
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

La cancelación suave, errores de emparejamiento y timeouts tienen código y
límites, pero esas rutas no están verificadas funcionalmente. Esta prueba
no valida otros modelos, builds de iOS, jailbreaks ni todos los accesorios.
La app todavía no enlaza ni invoca este motor y no muestra un botón de ping.

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

La ruta Skywalk de apertura/lectura/escritura/cierre y los ecos reales quedaron
comprobados después de este análisis, en las pruebas `probe7` y `probe8`
descritas arriba. Continúan pendientes la integración en la app y una gestión
autónoma de exclusividad/recuperación: actualmente las ejecuta el operador por
SSH. No debe llamarse `--l2ping` dejando el servicio retirado sin programar
recuperación independiente antes. El motor no manipula servicios por sí mismo.

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

NukeWireless no depende de este paquete de investigación.
