# Barra principal al volver del segundo plano · dev47/app28

El usuario mostró una captura de Punto de acceso tras dejar la app unos segundos en segundo plano: las cuatro opciones de la extensión y las tres opciones nativas aparecen superpuestas. La barra de presentación de dev46 estaba anidada en la barra nativa; reconstruir o reordenar sus controles permite colocarlos por encima. La captura acredita la superposición, no la secuencia interna exacta de UIKit del teléfono.

Dev47 coloca la misma barra de presentación como vista hermana de la barra nativa, con fondo opaco, geometría ligada a sus bordes y prioridad de dibujo. La barra nativa conserva su función de layout y la selección programática SwiftUI; sus controles quedan sin interacción ni exposición duplicada a VoiceOver. Las notificaciones públicas de activación de app/escena reafirman orden, apariencia y selección, con una reconciliación acotada al siguiente turno de UIKit. No se añade mantenimiento periódico ni hooks de clases privadas.

Se conservan los tres hosts y su delegado, sin añadir controladores al array SwiftUI. La navegación Bluetooth, catálogo individual/conjunto, Detener, recuperación Wi-Fi, firma y permisos se mantienen. El trabajador app28 y los perfiles de radio no cambian.

La revisión de las primeras capturas reveló además un título Wi-Fi oscuro sobre fondo oscuro tras cambiar de apariencia. El estilo de navegación conserva ahora el color dinámico de etiqueta, en vez de resolverlo una sola vez al crear la barra. La regresión de retorno en Wi-Fi comprueba los colores de título normal y grande en el tema actual.

## Verificación prevista

El simulador conserva las dieciocho comprobaciones de dev46 y añade preparación/retorno de cuatro pestañas, con 26 comprobaciones por idioma. El script abre Ajustes durante tres segundos y vuelve al mismo proceso sin terminarlo. Comprueba notificación real de segundo plano, PID conservado, hosts/delegado/selección intactos, misma navegación del catálogo Bluetooth, geometría, fondo opaco, capa, interacción y accesibilidad. Antes de cada ciclo añade contenido nativo y lo reordena para desafiar el aislamiento visual sin depender de clases privadas. Captura cada retorno, incluyendo Punto de acceso en oscuro como en el informe del usuario.

Compilación, paquete, instalación y aceptación manual del retorno en el iPhone pendientes.
