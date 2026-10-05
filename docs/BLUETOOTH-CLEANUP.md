# Limpieza Bluetooth (dev39/app26)

Se retiran del menú y del trabajador los ensayos genéricos de emisión NWLab, datos propios de fabricante y rotación de contador denominado BT Disruptor. Eran pruebas de integración del controlador; la rotación de anuncios no interrumpía conexiones. Se eliminan sus opciones CLI, exports, constructores de paquetes, textos y fixtures específicos.

Se conservan escáner BLE, ping L2CAP, consulta de capacidades y los perfiles Windows, Apple y Android, individuales y de tres modelos. La cabecera del menú pasa de doce a nueve filas; cada botón restante conserva su comando. Se mantienen Detener, recuperación del servicio, límite de diez segundos y uso independiente del escaneo Wi-Fi. No se añaden diagnósticos ni emisiones nuevas. Los informes guardados de operaciones retiradas se ignoran al cargar el menú.

La emisión de los perfiles restantes está documentada en [BLE-WIFI-CONCURRENCY.md](BLE-WIFI-CONCURRENCY.md). El aviso del sistema en Apple/Android sigue pendiente de prueba en un receptor. La nueva regresión del simulador comprueba los seis títulos de perfil en sus nuevas filas, el bloqueo durante operaciones y el botón Detener. Las pruebas C siguen verificando formatos, modelos, direcciones y duración del controlador.

Para revertir la limpieza, reinstalar las copias de app dev38 y trabajador app25, preservando el identificador de firma de la app para Bluetooth. No es necesario reiniciar el iPhone.
