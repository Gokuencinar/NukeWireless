# Aleatoriedad Google / Fast Pair · dev49/app31

Dev48 generaba seis tarjetas Google a partir de seis perfiles disponibles: solo existía una combinación. Aunque renovaba UUIDs NWLab, los modelos no cambiaban. Dev49 añade nueve perfiles disponibles en total, selecciona seis distintos entre 84 combinaciones y excluye la selección anterior de esa marca durante la vida de la pantalla. Mantiene las seis tarjetas y la emisión individual/conjunta.

Se añaden Sony WF-1000XM4 (C8D335), Sony WH-1000XM5 (D446A7) y Jabra Elite 5 (8B0A91), contrastados en la [tabla Fast Pair fijada a 1e423683](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/fastpair.c). Son correspondencias de investigación; la recepción de un anuncio y el aviso del sistema se verifican por separado.

Los índices originales 0–8 y sus direcciones permanecen estables; se añaden 9–11 para Google. Apple, Microsoft y Samsung conservan sus nombres y selecciones disponibles. El catálogo usa un límite de doce posiciones y descarta las posiciones sin nombre/perfil por marca. La entrada del trabajador admite índices decimales, rechaza duplicados, ceros iniciales, valores fuera de rango y más de seis modelos. supports_le_catalog_extended_models evita enviar índices nuevos a app30. El nuevo binario conserva la espera de recuperación app30, límites de diez segundos, Detener, limpieza, permisos y firma.

## Verificación

Pendiente de compilación, paquete e instalación. Las pruebas C comprueban los 35 perfiles, 280 selecciones válidas, 924 combinaciones generales, IDs y direcciones, presupuesto AD e índices de varios dígitos. La regresión del catálogo recorre 25 generaciones por marca y exige que cambien los nombres cuando hay alternativas, ahora también en Google. La regresión de navegación verifica el envío de 0,1,2,9,10,11 y el rechazo del trabajador anterior.
