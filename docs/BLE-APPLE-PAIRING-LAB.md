# Prueba Apple de proximidad

NukeWireless dev36/app20 incorpora «Apple: prueba BLE (10 s)» en Información →
Bluetooth. El usuario indicó que trabaja en un laboratorio aislado y que no
dispone de un receptor Apple para verificar la notificación.

La prueba usa una única trama de proximidad de AirPods Pro, fabricante 0x004C,
subtipo 0x07 y producto 0x200E. Se conserva la misma dirección pública y el
mismo contenido durante la prueba, con intervalo de 1 segundo y duración de
controlador de 10 segundos. «Detener» permite cancelar antes. No existe un
servicio de accesorio que permita completar un emparejamiento.

El formato de proximidad y el producto se contrastaron con
[ESP32-TOOLS Modern, commit dc59cd3](https://github.com/pepeangell5/ESP32-TOOLS-MODERN/blob/dc59cd372530d17633efd20b8a2421c3e60cfdfe/src/BLESpam.cpp)
y la trama fija de AirPods Pro del proyecto de investigación
[AppleJuice](https://github.com/ECTO-1A/AppleJuice/blob/main/app.py).
Se usa la trama fija de este último como fixture de laboratorio.

La prueba no cambia direcciones ni modelos, y no introduce subtipos de otras
funciones. El anuncio ocupa exactamente los 31 bytes permitidos por la trama
legacy. Las pruebas C comprueban límites, longitudes anidadas, fabricante,
producto y estabilidad de la trama. Los comandos HCI siguen restringidos al
conjunto existente de configuración, datos, habilitación, parada y retirada.

Los informes distinguen la aceptación del controlador de la recepción por un
escáner externo. `apple_notification_verified` permanece en falso: sin un
receptor Apple no se puede confirmar que el sistema muestre un aviso, ni su
compatibilidad con versiones concretas de iOS.

La cancelación del trabajador app19 quedó comprobada previamente en el iPhone
XS con iOS 16.3.1 y RootHide: 2,187 segundos de emisión y 0,519 segundos desde
recibir la petición hasta completar el informe y la recuperación. La prueba
Apple conserva ese mecanismo de cancelación atómica.
