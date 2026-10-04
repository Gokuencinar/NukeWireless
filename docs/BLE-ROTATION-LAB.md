# BT Disruptor: prueba de rotación BLE (dev32 / app16)

El usuario eligió una prueba de diez segundos de rotación de anuncios. Esta
implementación actualiza los datos de un anuncio de laboratorio, manteniendo
la dirección del iPhone y el intervalo de un segundo. No reproduce la rotación
de MAC, suplantación de objetivos ni intervalos de 20–40 ms de Modern.

La app muestra «BT Disruptor: anuncios (10 s)» en Información → Bluetooth.
Bluetooth debe estar apagado desde Ajustes. El helper acepta únicamente
`--le-rotation-test`, sin parámetros externos. Conserva guardas del iPhone XS
con iOS 16.3.1, exclusión mutua, cancelación y recuperación independiente.

El anuncio no conectable contiene flags, UUID
`7AD172A1-6D8C-4D0A-9BEA-8D8F3B5C9C22` y fabricante `0xFFFF`. Los seis bytes
del fabricante son `4E57526F01` más un contador `00`–`09`. El paquete AD ocupa
31 bytes. La secuencia cero se configura antes de activar el anuncio; después
se actualiza una vez por segundo con `0x2037`, sin reiniciar el temporizador
de diez segundos del controlador. Si una respuesta tarda, no se acumulan
actualizaciones ni se envían ráfagas para recuperar el tiempo perdido.

El informe registra `acknowledged_sequences` y `acknowledged_sequence_count`.
Esos contadores indican valores aceptados por HCI; no cuentan paquetes emitidos
ni recibidos. Para verificar la rotación por radio, la laptop debe registrar al
menos dos valores distintos con el UUID y marcador exactos. El informe nativo
mantiene `transmission_verified=false`, pues no tiene un receptor independiente.
La limpieza desactiva y elimina el set antes de restaurar bluetoothd.

Revisión de Modern en commit `dc59cd372530d17633efd20b8a2421c3e60cfdfe`:
`updateL2CAPStormData` escribe datos de fabricante y no genera ecos L2CAP;
`updateConnectFloodData` escribe anuncios y no inicia conexiones BLE. El bucle
actualiza datos cada 50 ms y solicita rotación de MAC cada segundo. No hay una
prueba de desconexión de auriculares en esa implementación.

Fuentes:
- https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BTDisruptor.cpp
- Bluetooth Core, vol. 4, parte E, 7.8.54: LE Set Extended Advertising Data.

Estado inicial: implementación preparada; compilación, instalación y recepción
de la nueva secuencia pendientes. Dev31/app15 ya verificaron anuncios fijos.

Para revertir después de instalar, reinstalar los paquetes dev31/app15
conservados en `/var/mobile/Documents/NukeWireless-dev31-backup.deb` y
`/var/mobile/Documents/NukeWireless-Bluetooth-app15-backup.deb`.
