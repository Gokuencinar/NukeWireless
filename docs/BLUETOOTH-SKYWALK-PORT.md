# Emisión Bluetooth: port Skywalk app32 / compat4

La emisión deja de depender de la whitelist iPhone XS / iOS 16.3.1 y del hash de
AppleConvergedTransport. Ese hash protegía una estructura opaca de ACT que la
emisión Skywalk no utiliza. El diagnóstico ACT y el antiguo diagnóstico ACL
conservan la restricción original; no se reintroducen en la interfaz.

## Contrato comprobado

Se compararon las catorce funciones de canal empleadas, sus tipos, enumeraciones
y el layout de `slot_prop_t` en las fuentes primarias de Apple:

| XNU | SHA-256 de `bsd/skywalk/channel/os_channel.h` |
| --- | --- |
| [8020.101.4](https://raw.githubusercontent.com/apple-oss-distributions/xnu/xnu-8020.101.4/bsd/skywalk/channel/os_channel.h) | `08c1e08f0f3d6501aa7b11cb1e1fdd43615a8eaa29d29213371fd4a3a45f474a` |
| [8792.61.2](https://raw.githubusercontent.com/apple-oss-distributions/xnu/xnu-8792.61.2/bsd/skywalk/channel/os_channel.h) | `90abb4c7e3536e920c940a0953b58c08da61fde56b10ab97dfa6239003a445d6` |
| [10002.1.13](https://raw.githubusercontent.com/apple-oss-distributions/xnu/xnu-10002.1.13/bsd/skywalk/channel/os_channel.h) | `f483b9c664e3d8465798f9150ddfa37916208fcc64d32b7de45658fd50ec8af3` |
| [11215.1.10](https://raw.githubusercontent.com/apple-oss-distributions/xnu/xnu-11215.1.10/bsd/skywalk/channel/os_channel.h) | `f483b9c664e3d8465798f9150ddfa37916208fcc64d32b7de45658fd50ec8af3` |

Las declaraciones empleadas coinciden entre las cuatro versiones. La estructura
tiene 64 bytes, alineación de 8 y puntero al buffer en offset 16. Los enums de
primer anillo TX/RX, sincronización y tamaño de buffer también coinciden. Esto
verifica el contrato C revisado; no demuestra que cada controlador Bluetooth
publique un canal HCI ni que cada versión menor tenga funcionamiento probado.

## Admisión y recuperación

Antes de retirar el servicio, el trabajador verifica iOS 15–18 y Darwin 21–24
correspondiente, símbolos XNU, firmas completas de BluetoothManager, estado
Bluetooth y descriptor IOKit `hci`/`skywalk` con UUID válido. `--status` observa
estos contratos sin abrir el canal ni construir el manager. Se rechazan
interfaces ausentes, métodos diferentes y otros transportes.

El runner busca exclusivamente `user/501/com.apple.bluetoothd` o
`system/com.apple.bluetoothd`. Requiere un único servicio activo y habilitado.
El proceso independiente de recuperación hereda ese dominio mediante una
whitelist exacta, además de los pipes y lock originales. No acepta etiquetas,
rutas ni dominios arbitrarios. Conserva la validación del padre instalado,
cancelación cooperativa, propiedad de hijos y recuperación antes de admitir
una nueva operación. No se añaden permisos.

Después de obtener el canal exclusivo y antes de configurar anuncios, se leen
la versión local y los comandos soportados del controlador. Se validan la
respuesta HCI completa y los bits 289, 290, 291, 293, 295 y 296 de
[Local Supported Commands, Bluetooth Core](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host-controller-interface/host-controller-interface-functional-specification.html): dirección del conjunto, parámetros/datos/enable extendidos, capacidad y retirada.
La capacidad real sigue limitando la selección múltiple. Un fallo no configura
anuncios y pasa por recuperación. La prueba dura como máximo diez segundos y
conserva Detener. La confirmación HCI no prueba recepción externa.

## Alcance de la evidencia

El usuario confirma compatibilidad comprobada de BandLock y BetterWiFi en los
distintos iOS. Son referencias para resolución dinámica, disponibilidad de
interfaces y variantes de bootstrap; sus pruebas no se trasladan a NukeWireless.
BetterWiFi inyecta Settings y puede necesitar arm64e; la app y trabajador de
NukeWireless son procesos arm64. No se cambia esa arquitectura por la etiqueta
Debian RootHide.

CoreBluetooth, catálogo y navegación conservan sus funciones anteriores. El
port habilita intentar la emisión en sistemas que cumplan el contrato observado;
no incorpora un driver alternativo para hardware sin HCI Skywalk. iOS 15, 17,
18, Dopamine convencional y rootful requieren pruebas físicas propias. Los
paquetes compat4 y las pruebas de dev53/app32 en la referencia RootHide se
registran en [validación compat4](COMPAT4-VALIDATION.md).
