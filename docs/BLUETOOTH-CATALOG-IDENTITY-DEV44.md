# Identidad de modelos del catálogo · dev44/app28

El catálogo usa la identidad codificada en el protocolo del receptor. Se añade Samsung como cuarta marca sin cambiar los índices Apple/Google/Microsoft. Las tarjetas muestran el ID del perfil, en lugar del UUID local NWLab. Los UUIDs siguen siendo locales y se conservan en memoria; no se usan como direcciones Bluetooth.

Cada marca mantiene seis entradas, tres selecciones distintas, veinte combinaciones y exclusión de la última combinación por marca. Samsung contiene modelos y variantes de color; no son seis familias diferentes. Generar o cambiar de marca no emite. Emitir vuelve al panel Bluetooth con Detener accesible, duración máxima de diez segundos, cancelación cooperativa y restauración de servicios.

## Perfiles

| Marca | Entrada | Identidad emitida |
|---|---|---|
| Apple | AirPods / AirPods 2 / AirPods Pro / AirPods Pro 2 / AirPods Max | 2002 / 200F / 200E / 2014 / 200A |
| Google | Pixel Buds / Pixel Buds A-Series / Pixel Buds Pro | 92BBBD / 8B66AB / 9ADB11 |
| Microsoft | Las seis entradas existentes | Nombre completo en Display Name de Swift Pair |
| Samsung | Galaxy Buds (White) / (Black) | B8B905 / D30704 |
| Samsung | Galaxy Buds Live (Black) / (Bronze) | 850116 / 3F6718 |
| Samsung | Galaxy Buds2 (White) / Galaxy Buds2 Pro | EAAA17 / AB0C46 |

AirPods 4, Pixel Buds Pro 2, Nest Mini y Nest Audio permanecen visuales sin perfil verificado. No se inventan IDs para completarlos. El número Emitir N de 3 solo incluye perfiles disponibles.

Se corrige una identificación incorrecta de dev43: CD8256 pertenece a Bose NC 700 y 000047 a Arduino 101, no a Pixel Buds/A-Series. También se corrigen las acciones Android existentes: Pixel Buds 92BBBD, A-Series 8B66AB, Sony WH-1000XM4 01EEB4. El módulo declara `supports_le_catalog_identity_v2`; dev44 desactiva la emisión del catálogo con un trabajador anterior que conserva la tabla incorrecta.

Los anuncios Samsung usan un único segmento Manufacturer Specific completo de 28 bytes, compañía 0075. Buds2 Pro reproduce la captura completa; las otras variantes usan el cuerpo investigado y sus IDs. No se incorpora el segundo segmento truncado de la implementación de referencia, ni una respuesta a escaneo. Esto necesita aceptación específica en el receptor.

La dirección estática aleatoria de laboratorio es distinta por marca/modelo y estable al cambiar de posición en otra generación. El handle sigue siendo un índice interno. No hay rotación de direcciones durante la emisión. Apple y Android conservan 100 ms; Microsoft 152,5 ms. No cambia la potencia solicitada ni se afirma una medición física.

## Fuentes contrastadas

- Apple: [decodificador AirPods de esphome-components](https://github.com/myhomeiot/esphome-components/blob/0df6c5f898fb02d4b6ec9fe82589ad29a4a70b1c/examples/ble_gateway/airpods.yaml) y [campos de Proximity Pairing](https://github.com/furiousMAC/continuity/blob/d9fa98bddafbfa3baafc84e37a417d78a0598546/messages/proximity_pairing.md). Se conserva el fixture heredado; no se modifica un byte de estado sin validación.
- Google: [tabla investigada de modelos](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/fastpair.c) y [especificación de proveedor](https://developers.google.com/nearby/fast-pair/specifications/service/provider). Las correspondencias de la tabla son evidencia de investigación, no una certificación ni aceptación propia en el receptor.
- Samsung: [tabla y estructura EasySetup investigada](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/easysetup.c) y [captura de Galaxy Buds2 Pro](https://github.com/SpeastTV/BLE-Payloads/blob/afccfb8b580672a0a1ea287afec353b4aea9765b/README.md#galaxy-buds-2-pro).
- Microsoft: [especificación Swift Pair](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/bluetooth-swift-pair). Display Name no es un identificador registrado de producto.

## Validación y límites

Las pruebas C comprueban IDs, captura Samsung, segmentos AD completos y límite de 31 bytes, direcciones distintas y estables al mover el modelo, las 80 selecciones y rechazo de entradas inválidas. El simulador cubre cuatro marcas, traducciones y apariencia oscura, además de navegación, Stop y rechazo de trabajador anterior. El informe de entrega registra la procedencia exacta de compilación, paquete e instalación.

El usuario informó que dev43 no mostraba error. Ese informe no confirma por sí solo Detener antes de diez segundos, restauración o reconocimiento de un modelo en el receptor. La aceptación de dev44 en iPhone/iPad, Android de varias marcas y Windows permanece pendiente. Un ACK del controlador tampoco prueba recepción ni un aviso del sistema. No se implementa un accesorio emparejable ni se garantiza que todos los receptores interpreten estos perfiles o muestren una tarjeta.

## Entrega verificada

Fuentes `7b761333db270b275c0d8cad3fca7b5eac633543`: [app y simulador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37587166918) y [trabajador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37587166571) aprobados. Doce comprobaciones por idioma (es/en); capturas de las cuatro marcas y modo oscuro revisadas. Siete comprobaciones del paquete de la app y validación del trabajador (procedencia, hashes, metadatos, permisos, capacidad nueva y rechazo de fuentes obsoletas) aprobadas.

Paquete app: SHA-256 `44acc1133c31e18d1298e7d044f344af34b629e9a12a6855b5a9d3284ef5b302`. Trabajador: SHA-256 `7b05da070a7f85671019a32e6cd2839d8a52534d0b1bf8f61d21246209a82f89`. Instalación confirmada en el mismo iPhone XS/iOS 16.3.1, SSH 192.168.1.22 con clave conocida, `dpkg` dev44/app28 y capacidad `supports_le_catalog_identity_v2`. CodeDirectory mantiene `me.midnightchips.harpy-reloaded`; no aparecen nuevos informes de crash relevantes durante la instalación.

Recuperación: cerrar NukeWireless e instalar conjuntamente `/var/mobile/Documents/NukeWireless-app27-backup.deb` y `/var/mobile/Documents/NukeWireless-dev43-backup.deb` desde el entorno SSH del mismo jailbreak. Ambos paquetes se transfirieron y verificaron por hash antes de instalar dev44/app28. No requiere respring ni reinicio general.

La recepción pasiva en la laptop Windows confirma los doce anuncios seleccionados en cuatro ensayos de diez segundos: AirPods, AirPods Pro, AirPods Pro 2; Pixel Buds, A-Series, Pro; Surface Keyboard, Surface Mouse, Xbox Wireless Controller; Galaxy Buds (White), Buds Live (Black), Buds2 Pro. Coinciden las direcciones y los IDs/nombres recibidos; los cuatro ensayos confirman desactivación, retirada de sets y restauración del servicio. Es inspección del payload recibido, no aceptación de un aviso ni del reconocimiento del sistema en iOS/Android/Windows. Véase el informe `RECEPCION-CATALOGO-DEV44.json` de la entrega.

El primer intento Google, inmediatamente después de restaurar el servicio tras Apple, se rechazó en preflight (`skywalk_registry`) sin emitir ni retirar servicios. Se conserva esa evidencia; los ensayos restantes pasaron dejando tiempo para que el servicio publicase de nuevo la interfaz. No se modificó el guard del trabajador ni se hicieron reinicios generales.

## Aceptación manual parcial

El usuario confirma que Windows muestra **Surface Headphones** al emitir desde el catálogo dev44. Es aceptación manual del nombre interpretado en ese receptor, distinta de la captura pasiva de doce payloads. No se ha especificado la versión de Windows ni el tipo de aviso; no prueba emparejamiento. iPhone/iPad y Android permanecen pendientes de aceptación; Detener antes de diez segundos no se ha confirmado específicamente en dev44.
