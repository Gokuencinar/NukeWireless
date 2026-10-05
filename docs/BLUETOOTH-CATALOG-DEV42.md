# Catálogo aleatorio local (dev42)

En Bluetooth → Catálogo aleatorio se elige Apple, Google o Microsoft. La pantalla muestra tres modelos distintos de un catálogo de seis por marca. Generar tres modelos elige una nueva combinación entre las veinte posibles y evita repetir la anterior para esa marca durante la sesión. Cambiar de marca también genera una selección. Cada tarjeta tiene un UUID local nuevo; la interfaz muestra su prefijo NWLab abreviado para facilitar la lectura.

Apple incluye AirPods, AirPods 2, AirPods Pro, AirPods Pro 2, AirPods Max y AirPods 4. Google incluye Pixel Buds, Pixel Buds A-Series, Pixel Buds Pro, Pixel Buds Pro 2, Nest Mini y Nest Audio. Microsoft incluye Surface Keyboard, Surface Mouse, Surface Precision Mouse, Surface Headphones, Surface Headphones 2 y Xbox Wireless Controller. Estos nombres son etiquetas visuales de la simulación, no una afirmación de compatibilidad BLE o emparejamiento.

El catálogo se calcula dentro de la app y funciona sin el trabajador Bluetooth. No contiene datos de anuncios, identificadores de fabricante, modelos Fast Pair ni llamadas al controlador. El trabajador app26, la emisión, la potencia y sus permisos conservan su implementación anterior. Durante una operación Bluetooth se mantiene accesible Detener y se impide abrir otra pantalla desde el menú.

La pantalla usa controles nativos, texto adaptable y traducciones en español e inglés. El título se actualiza al cambiar al modo oscuro. El acceso principal está en Exploración y sus tarjetas se identifican como modelos de simulación.

## Validación

La compilación final usa el ejecutor macOS 15 y conserva el destino arm64 / iOS 16.3. Se eligió esa imagen después de que la compilación corregida permaneciese en cola con `macos-latest`.

Fuentes `6230441ee6ade462f67263e3cc30341f79acb115`: [compilación y simulador](https://github.com/Gokuencinar/NukeWireless/actions/runs/37364889097) aprobados. La prueba C recorre las veinte combinaciones, comprueba que cada una contiene tres índices únicos y que las diecinueve alternativas excluyen exactamente la combinación previa. El simulador verifica los modelos, la regeneración y las identidades para las tres marcas; cada idioma supera once comprobaciones. Se revisaron capturas de los tres catálogos y del modo oscuro. El primer intento detectó un título oscuro ilegible; la compilación final incluye la corrección.

El paquete supera siete comprobaciones de procedencia, recursos, metadatos, firma y permisos. SHA-256: `45110fd85f9323336269d8f7495886c50fb53060e72391592a857d77ff607e61`. Instalación confirmada por dpkg en el iPhone XS, iOS 16.3.1, RootHide: dev42 con app26. El identificador de firma del ejecutable instalado sigue siendo `me.midnightchips.harpy-reloaded`. No se detectaron informes de crash nuevos durante la instalación. El usuario confirmó la apertura manual en el iPhone, el cambio entre Apple, Google y Microsoft y la generación de nuevas combinaciones. La prueba visual y funcional automatizada corresponde al simulador; la aceptación en el dispositivo procede de esa confirmación del usuario.

## Recuperación

Se conserva dev41 en `/var/mobile/Documents/NukeWireless-dev41-backup.deb`, verificado por hash durante la transferencia. Para volver a esa versión, cerrar NukeWireless y ejecutar `dpkg -i /var/mobile/Documents/NukeWireless-dev41-backup.deb` desde el entorno SSH del mismo jailbreak.
