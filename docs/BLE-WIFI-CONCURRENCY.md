# Bluetooth durante Wi-Fi y anuncios de varios modelos (dev38/app22)

Se eliminaron cuatro restricciones de NWScanBusy para permitir ping, consultas, anuncios y escáner BLE mientras continúa el escaneo LAN. Se conserva la exclusión Bluetooth y durante bloqueos.

Tres modos separados de 10 segundos: Windows anuncia NWLab Keyboard, NWLab Mouse y NWLab Audio; Apple anuncia AirPods Pro (200E), AirPods Pro 2 Lightning (2014) y AirPods Max (200A); Android anuncia Pixel Buds (CD8256), Pixel Buds A (000047) y Sony WH-1000XM4 (140045). Cada modo utiliza tres conjuntos activos con direcciones static-random distintas y fijas; no alterna perfiles ni rota identidades durante el ensayo. Son anuncios de descubrimiento, sin emparejamiento real.

El controlador se consulta mediante LE Read Number of Supported Advertising Sets antes de configurar. Con menos de tres conjuntos, se rechaza la prueba sin emisión ni alternancia encubierta. Se solicitan +20 dBm, máximo del parámetro estándar HCI; el valor realmente elegido queda en el registro interno. Cadencia 100 ms por conjunto, límite de controlador 10 s y Detener conservados. Se desactivan y retiran todos los conjuntos en la recuperación.

No se añaden pantallas de diagnóstico ni exportación. Fixtures de Wi-Fi activo y framing de las tres identidades verifican el cambio en el simulador y C. Los avisos Apple/Android quedan sin verificar si no hay receptores. AirPods 4 no se etiqueta con un identificador no contrastado.

Fuentes: ESP32-TOOLS Modern dc59cd372530d17633efd20b8a2421c3e60cfdfe (Model IDs Google), AppleJuice app.py y myhomeiot/esphome-components examples/ble_gateway/airpods.yaml (200E/2014/200A), Bluetooth Core HCI LE Set Extended Advertising Parameters, Set Advertising Set Random Address y Read Number of Supported Advertising Sets.
