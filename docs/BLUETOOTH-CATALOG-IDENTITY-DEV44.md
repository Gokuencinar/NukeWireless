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

Las pruebas C comprueban IDs, captura Samsung, segmentos AD completos y límite de 31 bytes, direcciones distintas y estables al mover el modelo, las 80 selecciones y rechazo de entradas inválidas. El simulador cubre cuatro marcas, traducciones y apariencia oscura, además de navegación, Stop y rechazo de trabajador anterior. Compilación, paquete e instalación se registrarán con su procedencia exacta en el informe de entrega.

El usuario informó que dev43 no mostraba error. Ese informe no confirma por sí solo Detener antes de diez segundos, restauración o reconocimiento de un modelo en el receptor. La aceptación de dev44 en iPhone/iPad, Android de varias marcas y Windows permanece pendiente. Un ACK del controlador tampoco prueba recepción ni un aviso del sistema. No se implementa un accesorio emparejable ni se garantiza que todos los receptores interpreten estos perfiles o muestren una tarjeta.
