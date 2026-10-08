# Barra principal al volver del segundo plano · dev47/app28

El usuario mostró una captura de Punto de acceso tras dejar la app unos segundos en segundo plano: las cuatro opciones de la extensión y las tres opciones nativas aparecen superpuestas. La barra de presentación de dev46 estaba anidada en la barra nativa; reconstruir o reordenar sus controles permite colocarlos por encima. La captura acredita la superposición, no la secuencia interna exacta de UIKit del teléfono.

Dev47 coloca la misma barra de presentación como vista hermana de la barra nativa, con fondo opaco, geometría ligada a sus bordes y prioridad de dibujo. La barra nativa conserva su función de layout y la selección programática SwiftUI; sus controles quedan sin interacción ni exposición duplicada a VoiceOver. Las notificaciones públicas de activación de app/escena reafirman orden, apariencia y selección, con una reconciliación acotada al siguiente turno de UIKit. No se añade mantenimiento periódico ni hooks de clases privadas.

Se conservan los tres hosts y su delegado, sin añadir controladores al array SwiftUI. La navegación Bluetooth, catálogo individual/conjunto, Detener, recuperación Wi-Fi, firma y permisos se mantienen. El trabajador app28 y los perfiles de radio no cambian.

La revisión de las primeras capturas reveló además un título Wi-Fi oscuro sobre fondo oscuro tras cambiar de apariencia. El estilo de navegación conserva ahora el color dinámico de etiqueta, en vez de resolverlo una sola vez al crear la barra. La regresión de retorno en Wi-Fi comprueba los colores de título normal y grande en el tema actual.

## Verificación

El simulador conserva las dieciocho comprobaciones de dev46 y añade preparación/retorno de cuatro pestañas, con 26 comprobaciones por idioma. El script abre Ajustes durante tres segundos y vuelve al mismo proceso sin terminarlo. Comprueba notificación real de segundo plano, PID conservado, hosts/delegado/selección intactos, misma navegación del catálogo Bluetooth, geometría, fondo opaco, capa, interacción y accesibilidad. Antes de cada ciclo añade contenido nativo y lo reordena para desafiar el aislamiento visual sin depender de clases privadas. Captura cada retorno, incluyendo Punto de acceso en oscuro como en el informe del usuario.

Compilación, paquete e instalación verificados. Aceptación manual del retorno en el iPhone pendiente.

## Entrega verificada

Fuentes `d79b22a0114296fa5a7137c7aeb51618480be2d9`, [CI aprobado](https://github.com/Gokuencinar/NukeWireless/actions/runs/37597696357). Veintiséis comprobaciones por idioma (es/en): dieciocho regresiones previas y preparación/retorno de cuatro pestañas. En cada idioma se observaron cuatro entradas reales en segundo plano, con el mismo PID y selección al regresar desde Ajustes. Se revisaron las capturas de retorno en Wi-Fi, Punto de acceso oscuro, catálogo Bluetooth e Información, además de las regresiones del catálogo. Esta evidencia procede del simulador y no sustituye la aceptación manual del teléfono.

Paquete `1.0.25+rh25.5~dev47`, SHA-256 `08d0b31917d799a231bb6a9c0f53b959c08928f898d8d3b6fb6e0df32ab394d2`, validado con siete comprobaciones y procedencia coincidente con las fuentes. app28 conserva los hashes de paquete y fuentes, sin recompilar ni reinstalar. Dpkg confirma dev47/app28 en iPhone11,2/iOS 16.3.1, clave SSH conocida en 192.168.1.22, capacidad del trabajador y CodeDirectory `me.midnightchips.harpy-reloaded` verificados. No se observaron nuevos informes de crash relevantes durante la instalación.

Recuperación: cerrar NukeWireless e instalar `/var/mobile/Documents/NukeWireless-dev46-backup.deb` desde el entorno SSH del mismo jailbreak. Copia y paquete nuevo comprobados por SHA-256 en el teléfono antes de instalar. app28 se mantiene. No requiere respring ni reinicio general.
