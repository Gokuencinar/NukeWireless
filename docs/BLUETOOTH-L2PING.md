# Bluetooth nativo: biblioteca de investigación

**Estado: diagnóstico local del controlador compilado e instalado; pendiente
de ejecución con Bluetooth apagado en Ajustes. El ping L2CAP todavía no está
implementado.** La app continúa en dev19, cuyas funciones
el usuario confirmó. Este paquete independiente no es una nueva versión de la
app ni añade un botón de ping.

El alcance solicitado es exclusivamente el Bluetooth del iPhone. No se utiliza
un adaptador Linux ni un servidor externo. El ping propuesto es un diagnóstico
finito: cinco solicitudes pequeñas, intervalo de un segundo, timeout por
respuesta, plazo total y cancelación. No se ejecutó ningún ping.

## Paquete separado

- ID: `com.gokuencinar.nukewireless.bluetooth`.
- Versión instalada: `0.0.2~probe1`.
- Esquema de esta candidata: RootHide; binarios arm64, deployment target iOS 15.
- Biblioteca: `/usr/lib/NukeBluetoothBridge.dylib`.
- Inspector: `/usr/bin/nwbt-inspect --inspect`.
- Fuente: [NWBTBridge.m](../src/bluetooth/NWBTBridge.m) y
  [NWBTInspector.m](../src/bluetooth/NWBTInspector.m).
- No tiene daemon, filtro de inyección ni constructor con efectos sobre Bluetooth.
  La inspección pasiva carga bibliotecas del sistema, busca símbolos y enumera
  metadatos Objective-C. `--transport-code` copia exclusivamente una sección
  de código de AppleConvergedTransport para análisis local de su ABI.
- `nwbt-inspect --controller-info --exclusive` intenta abrir BTI/HCI y enviar
  únicamente **Read Local Version Information** al controlador local. Comprueba
  UID root, modelo/iOS, SHA-256 de la sección de código y estado apagado de
  Bluetooth antes de llamar al transporte. No conecta dispositivos remotos.
  Tiene timeout de lectura, liberación de handles y watchdog de 20 segundos
  que termina exclusivamente el helper si una llamada privada queda atascada.
- El JSON declara `l2ping_implemented: false`,
  `bluetooth_packets_sent: 0` y `signatures_verified: false`.

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
- No se ejecutó todavía el diagnóstico exclusivo. Se solicitó al usuario
  apagar Bluetooth en Ajustes; se espera esa preparación antes de abrir handles.
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

## Transporte pendiente de validar

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

Para completar el backend nativo falta verificar en este iOS el ABI de
creación/lectura/escritura/liberación, el canal de recepción y el acceso al
controlador compatible con el servicio Bluetooth del sistema. Después harán
falta resultados de ecos reales en un dispositivo objetivo. No se sustituyen
por datos simulados ni por una apertura de canal. No se modificó firmware,
BlueTool o bluetoothd, ni se reiniciaron esos servicios.

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
