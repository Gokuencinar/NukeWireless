# Diagnostic18: presentación estable de las pestañas en iPad

Base: diagnostic17; conserva Bluetooth diagnostic7 y el desbloqueo Wi-Fi de
diagnostic16. Solo cambia la presentación de las pestañas y sus regresiones.

El usuario aportó un [GIF](https://jumpshare.com/s/WOVuDaWlCNJ7Eb8jcJEk)
de un iPad con Dopamine: contenido negro sin controles. Indica diagnostic10
o anterior, sin versión exacta confirmada. No se atribuye el problema al jailbreak
ni se interpreta la grabación como un crash demostrado del dispositivo.

## Reproducción propia

El [trabajo comparativo](https://github.com/Gokuencinar/NukeWireless/actions/runs/38196065043)
compiló las fuentes de diagnostic10 (`9210fb0`) y diagnostic17 con la misma
fixture SwiftUI universal y un iPad simulado en horizontal. Ambos abortaron
al arrancar: `NSLayoutConstraint setActive:` → `NWPrepareMainTabs` → `installUI`.
No llegaron a ejecutar una operación Bluetooth ni las comprobaciones iniciales.
El runtime exacto, hashes de los informes y frames están en la evidencia adjunta.

La barra nativa no estaba en la jerarquía común al activar restricciones de
nuestra barra contra sus anchors. Esa suposición es inválida durante la
adaptación de UIKit en iPad. Esto confirma un fallo propio de presentación,
pero no demuestra que sea la única causa de la pantalla negra en el iPad físico
del tester, cuyo iPadOS y paquete exactos no se han comprobado en esta entrega.

## Cambio y comprobación

La barra visible siempre se ancla a su padre estable, `tab.view`. Copia la
geometría nativa solo si esa barra está adjunta y ocupa el borde inferior;
si no, usa el borde inferior y el área segura de su propio padre. No activa
restricciones entre jerarquías separadas. Recalcula al cambiar layout/área segura
y en la recuperación de primer plano. Bluetooth termina encima de la barra
visible incluso cuando UIKit no aporta una barra inferior nativa.

Conserva los tres hosts de SwiftUI, su delegado, la selección sincronizada,
las cuatro opciones visibles y Detener. No reemplaza el controlador raíz,
no usa clases privadas de UIKit ni cambia el transporte Bluetooth.

La regresión incluye un `UITabBarController` real cuya barra se separa antes
de instalar la presentación. También verifica que la barra recibe eventos
al volver de segundo plano. La fixture de iPad comparte las pruebas de
navegación, catálogo, menús, aspecto oscuro y cuatro ciclos reales de segundo
plano por idioma con la de iPhone.

Compilación, pruebas y paquetes de diagnostic18 pendientes al escribir este
apartado. La aceptación del iPad físico permanece pendiente.
