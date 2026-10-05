# Bluetooth durante el escaneo Wi-Fi (dev38)

El escaneo Wi-Fi/LAN ya no bloquea el ping, las consultas del controlador ni las pruebas de anuncios BLE. Tampoco bloquea el escáner BLE de CoreBluetooth. Se retiraron cuatro dependencias artificiales de NWScanBusy; continúan la exclusión entre operaciones Bluetooth, el bloqueo durante operaciones de bloqueo Wi-Fi y las condiciones de acceso al controlador.

El escáner LAN utiliza interfaces de red y su estado/cola independiente; no comparte el transporte HCI ni el canal de cancelación del trabajador Bluetooth. Los callbacks se serializan en el hilo principal y las operaciones de radio continúan en el trabajador. Compartir el chip puede afectar rendimiento; no se promete ausencia de interferencia ni se modifican parámetros del Wi-Fi.

Mejoras de laboratorio: el informe muestra duración configurada, intervalo, tiempo de emisión medido por el trabajador, latencia de cancelación y si el escaneo Wi-Fi estaba activo al iniciar. El botón Compartir exporta el informe completo a JSON, conservando respuestas HCI y errores; el archivo temporal se elimina al cerrar la hoja. La interfaz distingue ACK del controlador y recepción RF independiente.

No se aumenta la potencia RF ni se amplían duración o tasas de emisión. Permanecen los perfiles fijos y el límite de diez segundos, Detener y recuperación independiente. Estas mejoras permiten medir y comparar resultados, sin implementar jamming, saturación ni desconexión de conexiones ajenas.

Verificación automática: fixtures del estado LAN mantienen NWScanning durante las pruebas Bluetooth y durante el ciclo real de la interfaz BLE con un central simulado. Esos fixtures no se incluyen en el binario instalado. También se comprueban el bloqueo Bluetooth, el botón Detener y la exportación disponible solo con informe y sin trabajo activo.

El usuario está ausente: no se pedirá desbloqueo ni una prueba manual. La instalación y la carga se comprobarán si SSH y el estado del dispositivo lo permiten; no se afirmará una prueba física simultánea Wi-Fi/Bluetooth sin evidencia.
