# Emisión de la selección del catálogo (dev43 / app27)

Bluetooth → Exploración → Catálogo aleatorio conserva las tres marcas, seis nombres por marca, veinte combinaciones y la exclusión de la última combinación. Generar y cambiar de marca siguen siendo operaciones locales. El nuevo botón **Emitir N de 3 · 10 s** transmite únicamente los perfiles disponibles de la selección mostrada. Si ninguno está disponible, queda desactivado. Las tarjetas identifican los modelos sin perfil contrastado; no se sustituyen por otros modelos ni por IDs inventados.

Al emitir se vuelve al panel Bluetooth. En curso y Detener permanecen accesibles; la selección se entrega al trabajador como índices de modelo, no como UUIDs NWLab. Estos UUIDs siguen siendo IDs locales de presentación y no determinan la dirección de radio. Última actividad muestra los nombres solicitados; la aceptación del controlador se distingue de la recepción y de un aviso del sistema. No hay emisión automática al generar, bucle continuo ni emparejamiento de un accesorio.

## Perfiles disponibles

| Marca | Modelos | Formato |
| --- | --- | --- |
| Apple | AirPods, AirPods 2, AirPods Pro, AirPods Pro 2 (fixture Lightning), AirPods Max (fixture Lightning) | Proximidad 0x004C/0x07; productos 2002, 200F, 200E, 2014, 200A |
| Google | Pixel Buds, Pixel Buds A-Series | Fast Pair FE2C; fixtures CD8256 y 000047 |
| Microsoft | Los seis nombres del catálogo | Swift Pair LE con Display Name; no identifica un accesorio original |

AirPods 4, Pixel Buds Pro, Pixel Buds Pro 2, Nest Mini y Nest Audio permanecen en el catálogo, sin emisión habilitada. No se deduce un Model ID específico a partir de «Nest Device» ni se reutiliza el perfil Sony de la antigua prueba Android.

Las correspondencias Apple proceden del [decodificador de esphome-components, revisión 0df6c5f](https://github.com/myhomeiot/esphome-components/blob/0df6c5f898fb02d4b6ec9fe82589ad29a4a70b1c/examples/ble_gateway/airpods.yaml). Los dos fixtures Google proceden de [ESP32-TOOLS Modern dc59cd3](https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BLESpam.cpp), como en app26. Son fuentes de investigación, no certificación del fabricante ni prueba de un aviso. Se conserva el framing de [Google Fast Pair](https://developers.google.com/nearby/fast-pair/specifications/service/provider) y el [Display Name de Microsoft Swift Pair](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/bluetooth-swift-pair). En los nuevos anuncios Microsoft se omite Flags, opcional para este ensayo no conectable, para incluir sin truncar los nombres de hasta 24 bytes en el presupuesto de 31 bytes.

## Implementación y compatibilidad

`NWCatalogProfiles.h` comparte disponibilidad y validación entre UI y trabajador. `NWBTLabCatalogData` construye el anuncio del modelo exacto. El comando `nwbt-run --le-catalog-test PLATFORM MODELS` acepta plataformas 0=Apple, 1=Google, 2=Microsoft y de uno a tres índices distintos separados por comas. Rechaza selección vacía, modelos sin perfil, duplicados, índices fuera de rango y argumentos malformados antes de retirar bluetoothd. No acepta datos HCI arbitrarios.

El catálogo se puede explorar con app26 o sin trabajador, pero Emitir requiere la capacidad `supports_le_catalog_test` de app27 y el guard existente iPhone11,2 / iOS 16.3.1. Se actualizan las versiones a dev43 y app27 porque ambos componentes cambian. Los tres hosts SwiftUI, firma `me.midnightchips.harpy-reloaded`, permisos, escáner BLE y recuperación Wi-Fi conservan sus fuentes.

Se reutilizan el proceso hijo, canal privado de cancelación, supervisor independiente de recuperación y limpieza de todos los handles intentados. La emisión usa de uno a tres conjuntos con identidades static-random fijas y duración de controlador de diez segundos; Microsoft usa 152,5 ms y Apple/Google 100 ms. No se modifica la potencia solicitada de app26 ni se declara una medición física.

## Validación y aceptación

Fuentes `742ff51280da5fa1fa8ffba43ee76d5fa6b6a853`: [app y simulador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37585119302) y [trabajador app27](https://github.com/Gokuencinar/NukeWireless/actions/runs/37585119415) aprobados. Las pruebas C comprueban IDs/nombres, framing, presupuesto AD, las sesenta selecciones y rechazo de argumentos. El simulador supera once comprobaciones por idioma (es/en), incluida la selección enviada, disponibilidad sin app27, navegación de regreso y cancelación. Capturas de las tres marcas y modo oscuro revisadas; la disponibilidad de emisión de esas capturas usa un trabajador simulado y no ejecuta radio. El paquete de la app supera siete comprobaciones; app27 supera inspección de procedencia, Mach-O, hashes, metadatos, permisos y rechazo de fuentes obsoletas.

Instalación del 7 de octubre de 2026 confirmada por dpkg en iPhone XS / iOS 16.3.1 / RootHide: dev43 y app27. El trabajador responde con la capacidad de catálogo y rechaza modelos sin perfil antes de acceder a la radio. La firma instalada conserva `me.midnightchips.harpy-reloaded`. La primera lectura SFTP del ejecutable falló con «Garbage packet received»; una lectura serial de 32 KiB permitió verificar la firma sin reinstalar. Apertura y emisión desde la UI pendientes de aceptación manual; recepción RF y avisos del sistema pendientes de prueba independiente.

SHA-256 app: `c0e158aeb241f6ed0a4e17819c6b50eb2a309ffacdc34b0c45497c01878933ed`. SHA-256 app27: `02e616d82bcf1ed42bf2d2df92c6d42b4d00ba161c912ebd522266d67127b8dc`.

Recuperación: copias de dev42 y app26 transferidas y verificadas en `/var/mobile/Documents/NukeWireless-dev42-backup.deb` y `/var/mobile/Documents/NukeWireless-app26-backup.deb`. Para recuperar, cerrar la app e instalar ambos paquetes desde el mismo entorno SSH del jailbreak. No se hizo respring ni reinicio general.
