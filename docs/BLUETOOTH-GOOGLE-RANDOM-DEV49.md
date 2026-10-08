# Aleatoriedad Google / Fast Pair · dev49/app31

Dev48 generaba seis tarjetas Google a partir de seis perfiles disponibles: solo existía una combinación. Aunque renovaba UUIDs NWLab, los modelos no cambiaban. Dev49 amplía el grupo a nueve perfiles disponibles, selecciona seis distintos entre 84 combinaciones y excluye la selección anterior de esa marca durante la vida de la pantalla. Mantiene las seis tarjetas y la emisión individual/conjunta.

Se añaden Sony WF-1000XM4 (C8D335), Sony WH-1000XM5 (D446A7) y Jabra Elite 5 (8B0A91), contrastados en la [tabla Fast Pair fijada a 1e423683](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/fastpair.c). Son correspondencias de investigación; la recepción de un anuncio y el aviso del sistema se verifican por separado.

Los índices originales 0–8 y sus direcciones permanecen estables; se añaden 9–11 para Google. Apple, Microsoft y Samsung conservan sus nombres y selecciones disponibles. El catálogo usa un límite de doce posiciones y descarta las posiciones sin nombre/perfil por marca. La entrada del trabajador admite índices decimales, rechaza duplicados, ceros iniciales, valores fuera de rango y más de seis modelos. supports_le_catalog_extended_models evita enviar índices nuevos a app30. El nuevo binario conserva la espera de recuperación app30, límites de diez segundos, Detener, limpieza, permisos y firma.

## Verificación

Compilación, paquete, instalación y recepción verificados; regeneración manual de Google en el iPhone pendiente de aceptación. Las pruebas C comprueban los 35 perfiles, 280 selecciones válidas, 924 combinaciones generales, IDs y direcciones, presupuesto AD e índices de varios dígitos. La regresión del catálogo recorre 25 generaciones por marca y exige que cambien los nombres cuando hay alternativas, ahora también en Google. La regresión de navegación verifica el envío de 0,1,2,9,10,11 y el rechazo del trabajador anterior.


## Entrega verificada

Fuentes `0e8e6869a21ecf9ae2a4c40dea4753b12182b164`: [app/simulador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37778084191) y [trabajador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37778084170) aprobados. Pasaron 26 comprobaciones por idioma y cuatro ciclos reales de segundo plano, conservando el PID. La comprobación UIKit del catálogo exige cambios de nombres en 25 generaciones por cada marca, incluida Google; también verifica emisión individual, envío de índices 10/11, cancelación y bloqueo del trabajador anterior.

Siete pruebas del paquete de la app y verificación de procedencia, binarios, hashes, permisos y rechazo de fuentes obsoletas del trabajador aprobadas. App SHA-256 `207fb701e90f5da7583ba7ec3edc8af40a273a5c77870c7817fd3520a277ea8d`; trabajador SHA-256 `62271908150d4b78d34d8cafea62bee8d078fcbba511eea0227e9a032be07cb2`. Dev49/app31 instalado en el iPhone XS/iOS 16.3.1 por SSH .22 con clave conocida, copias dev48/app30 comprobadas por SHA-256. Se conserva CodeDirectory me.midnightchips.harpy-reloaded. No hubo nuevos crashes relevantes en la comparación posterior a instalación y pruebas; trabajador ausente y bluetoothd running.

La laptop recibió los nueve payloads Fast Pair, incluidas las tres entradas nuevas. Pasaron dos operaciones consecutivas, una cancelación temprana del hijo propio por su shell root y una emisión posterior. Cada informe confirma retirada de sets, servicio restaurado e interfaz disponible. Corresponde a invocación root por SSH y receptor BLE pasivo; los avisos/identificación del sistema receptor requieren evidencia distinta.

Recuperación: cerrar NukeWireless e instalar conjuntamente /var/mobile/Documents/NukeWireless-app30-backup.deb y /var/mobile/Documents/NukeWireless-dev48-backup.deb desde el mismo entorno SSH. No requiere respring ni reinicio general.
