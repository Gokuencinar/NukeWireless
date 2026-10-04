# Desconexión de accesorios sin emparejamiento previo

Requisito actualizado el 4 de octubre de 2026: el iPhone debe interrumpir por
Bluetooth una conexión accesorio–laptop u otro dispositivo, aunque el accesorio
nunca se haya emparejado con el iPhone. Un agente en la laptop no cumple el
requisito. El objetivo no está implementado ni verificado.

## Alcance del controlador

`HCI_Disconnect` termina una conexión existente identificada por un
`Connection_Handle` del controlador que recibe la orden. La dirección Bluetooth
de unos auriculares no identifica un enlace laptop–auriculares dentro del
controlador del iPhone. Conseguir acceso a HCI en el jailbreak no convierte ese
enlace externo en un enlace local.

Abrir una conexión ACL puede ser posible antes del emparejamiento, según el
accesorio y su estado. Eso no otorga control sobre sus otras conexiones. Un
cambio de host mediante conexión normal dependería de la política del accesorio;
no constituye una desconexión remota general. La prueba de cambio de host
preparada aquí exigía un emparejamiento existente y no cumple el nuevo requisito.

Los anuncios BLE finitos de dev32/app16 tienen emisión observada, pero no
constituyen una prueba de desconexión de audio Bluetooth Classic. Los modos de
BT Disruptor examinados en Modern actualizan anuncios; sus nombres no demuestran
la terminación de un enlace de otro controlador.

## Investigación en este dispositivo

Combinación observada: iPhone XS (`iPhone11,2`), iOS 16.3.1 (`20D67`), Dopamine
RootHide. Se compiló una herramienta aislada `NWBTConnectionProbe` que permite
una única solicitud de conexión normal a un accesorio ya emparejado.

- Windows confirmó mediante `BluetoothFindFirstDevice`, con `fIssueInquiry=0`,
  que los Mi True Wireless EBs Basic 2 seguían conectados. No se enviaron
  órdenes de conexión ni de desconexión desde Windows.
- Las firmas de `BluetoothManager.sharedInstance`, `setSharedInstanceQueue:`,
  `pairedDevices`, `enabled`, `available` y `connectDevice:` y de los getters del
  accesorio se comprobaron contra el runtime de este iOS.
- La herramienta inicial no recibía un inventario útil. Una cola de callbacks
  propia no bastó para resolverlo. Se observó `com.apple.bluetooth.system` en
  las firmas de SpringBoard y Ajustes de este dispositivo; al añadir únicamente
  ese permiso Bluetooth a la herramienta aislada, el mismo binario devolvió
  `available=true`, Bluetooth encendido y 11 accesorios emparejados.
- Ningún nombre coincidió exactamente con el nombre que presenta Windows.
  Se compiló una variante que puede comparar la dirección del accesorio de
  Windows con entradas ya emparejadas. Esa variante no se ejecutó tras el
  cambio de requisito.
- En esta investigación se enviaron **cero solicitudes de conexión**, cero
  comandos HCI y cero órdenes de cambio de alimentación del radio. No hay
  evidencia nueva de cambio de host ni de desconexión remota.

La ausencia de permiso hizo que `enabled` devolviera `false` mientras Bluetooth
estaba encendido. Una futura herramienta no debe interpretar un inventario
vacío o un getter sin acceso al servicio como prueba de que el radio está apagado.
Debe validar que el servicio está disponible antes de adquirirlo en exclusiva.

## Lo que falta para una vía diferente

La investigación BrakTooth demuestra fallos en implementaciones específicas con
instrumentación y firmware LMP modificado. No demuestra que estos auriculares
sean vulnerables ni proporciona una implementación para el controlador de este
iPhone. InternalBlue documenta el iPhone XS/PCIe como no probado. No se ha
verificado aquí una ruta para emitir LMP arbitrario, ni un fallo aplicable al
modelo y firmware concretos del accesorio.

Por tanto, no se añade un botón que afirme desconectar accesorios externos. La
compilación instalada sigue siendo dev32/app16. La herramienta de investigación
es infraestructura acotada, no una implementación de este objetivo.

## Fuentes y build

- [Bluetooth Core 5.4, HCI, apartado 7.1.6 Disconnect](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host-controller-interface/host-controller-interface-functional-specification.html)
- [Microsoft: BluetoothFindFirstDevice](https://learn.microsoft.com/en-us/windows/win32/api/bluetoothapis/nf-bluetoothapis-bluetoothfindfirstdevice)
- [BrakTooth: investigación original](https://asset-group.github.io/disclosures/braktooth/disclosure.html)
- [InternalBlue: soporte iOS](https://github.com/seemoo-lab/internalblue/blob/master/doc/ios.md)
- [Modern, fuente examinada](https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BTDisruptor.cpp)
- [Build correcto de la variante por dirección, a949cb3](https://github.com/Gokuencinar/NukeWireless/actions/runs/37231652208)
