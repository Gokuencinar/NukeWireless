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

La revisión de las primeras capturas detectó además la barra flotante nativa
de tres opciones y una columna de detalle vacía. En iPad se aplica el tamaño
horizontal compacto mediante traits públicos al contenedor, manteniendo una
sola navegación inferior y contenido de una columna. En iOS 15/16 se usa la
sobrescritura del padre; desde iOS 17, `traitOverrides`. La barra de presentación
también declara un ancho de ítem para evitar títulos recortados en traits regulares.

Conserva los tres hosts de SwiftUI, su delegado, la selección sincronizada,
las cuatro opciones visibles y Detener. No reemplaza el controlador raíz,
no usa clases privadas de UIKit ni cambia el transporte Bluetooth.

La regresión incluye un `UITabBarController` real cuya barra se separa antes
de instalar la presentación. También verifica que la barra recibe eventos
al volver de segundo plano. La fixture de iPad comparte las pruebas de
navegación, catálogo, menús, aspecto oscuro y cuatro ciclos reales de segundo
plano por idioma con la de iPhone.

Las cinco validaciones CI pasaron para `cee5d77f3946184795a46cc35a7ded8e824d0456`: compilación principal,
candidatos con destino iOS 15, trabajador Bluetooth, migración del instalador
y presentación en iPad horizontal. Las fixtures iPhone e iPad completaron
46 comprobaciones y cuatro ciclos reales de segundo plano por idioma
(español e inglés). Se revisaron las capturas de Wi-Fi, Bluetooth, catálogo
oscuro y retorno a Información: una sola barra inferior, títulos completos
y contenido visible. El runtime de iPad fue iPadOS 18.5; no se ejecutó
una prueba de rotación durante esta regresión.

Los DEB completos RootHide, rootless y rootful incluyen Bluetooth diagnostic7.
Pasaron integración, procedencia, firma, dependencias y rutas; el CI ejecutó
las pruebas dpkg/Linux y la revisión local cubrió los payloads finales.
Hashes, trabajos y resultados: [verificación](evidence/diagnostic18-verification.json).

## Seguimiento del iPad Pro con iPadOS 16.0

El 12 de octubre el usuario comunica que el tester obtiene el mismo resultado
en un iPad Pro con iPadOS 16.0 y Dopamine. No aporta todavía el identificador
exacto del iPad ni confirma mediante el diario qué build carga. Diagnostic18
no tiene aceptación física en ese equipo.

Se añadió una selección exclusiva de `NW_UI_TESTING` para comparar la ruta
moderna y la de `setOverrideTraitCollection:forChildViewController:` sobre la
misma fixture y runtime. La ejecución normal conserva la elección por versión
de diagnostic18; no se generó ni distribuyó un paquete nuevo con este cambio.
La API de traits se contrasta con la [documentación de Apple](https://developer.apple.com/documentation/uikit/uiviewcontroller/setoverridetraitcollection(_:forchild:)?language=objc).

La [comparación](https://github.com/Gokuencinar/NukeWireless/actions/runs/38236583154)
usa fuentes `97ba3afa11d2c192913495557d2432855f53f187` y el mismo iPad Pro
11-inch (M4) simulado con iPadOS 18.5:

- La ruta moderna pasa las 46 comprobaciones y cuatro ciclos de segundo plano
  por idioma, inglés y español.
- La ruta alternativa pasa las 20 comprobaciones iniciales, pero falla con
  código 42 al verificar el tamaño horizontal compacto tras el primer retorno
  a Wi-Fi. El PID no cambia: no es un crash en esta reproducción.
- Las capturas alternativas muestran una columna vacía ya en el arranque;
  después del retorno también aparece la barra flotante nativa. Las pruebas
  iniciales existentes no detectaban esa adaptación visual incorrecta.

Forzar la API anterior sobre iPadOS 18.5 no reproduce el runtime de iPadOS 16.0.
Por tanto, este resultado identifica una limitación de presentación y de la
validación anterior, pero no demuestra la causa de la pantalla negra física.
Además, la fixture ejecuta directamente un TabView SwiftUI: no ejecuta la
transición SplashView del ejecutable original. No se modifica ese arranque
basándose únicamente en esta comparación.

El siguiente dato útil es el `latest.json` existente en Documents /
NukeWireless-Diagnostics del iPad, recogido después del fallo. Registra la
build cargada, el identificador del modelo, iPadOS, esquema y eventos de
ciclo de vida sin exigir acceso al menú de Diagnósticos. No contiene todavía
una captura de la jerarquía de ventanas del dispositivo físico.

La compilación con destino iOS 15 no demuestra el funcionamiento en iPadOS
15/16 ni en otros jailbreaks. La corrección física permanece pendiente.
