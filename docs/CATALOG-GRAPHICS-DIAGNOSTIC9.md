# Catálogo: candidata de mitigación gráfica diagnostic9

## Evidencia

Un tester con iPhone 8 Plus (`iPhone10,2`), iOS 16.7.4 / 20H240 y Dopamine
rootless informa de un cierre al abrir el catálogo, antes de pulsar emitir.
Los informes de diagnostic7 y diagnostic8 muestran `EXC_BAD_ACCESS / SIGSEGV`,
PC cero, en el hilo principal. La secuencia relevante es:

```
UIImageView _handlePendingImageLayout:
_UIImageCGImageContent renditionApplyingEffect:
UIImage _imageWithStylePresets:tintColor:traitCollection:
CUICatalog imageByStylingImage:...
CUIShapeEffectStack sharedCIContext
CIContext contextWithOptions:
CI::GLContext::GLContext(...)
<null>
```

El diagnóstico actual confirma build 20008 y ambas bibliotecas integradas,
una sola copia de cada una. No es el problema anterior de la interfaz sin cargar.
El `.ips` diagnostic8 recibido aún enumera Liquid Glass y otros tweaks. El tester
informa de la misma salida con toda la inyección desactivada, conservando Bluetooth,
pero no dispone de otro `.ips` de esa ejecución. Esa observación no demuestra la
misma pila ni permite culpar a un tweak concreto.

La prueba del controlador falla por separado en `skywalk_registry`, antes de
abrir el canal o enviar comandos. Esta candidata no corrige ese transporte.

## Hipótesis y cambio

La pila identifica el procesado de un bitmap con efectos, pero no el nombre de
la imagen ni por qué CoreImage acaba llamando a una dirección nula. El catálogo
rasterizaba logotipos PDF como `AlwaysTemplate` y los entregaba a
`UIButtonConfiguration`. Es una fuente concreta de estilizado diferido que
podemos retirar sin hooks privados ni cambiar el comportamiento de emisión.

Diagnostic9 rasteriza los mismos PDF en un `CGBitmapContext`, aplica el color
resuelto con composición SourceIn y entrega imágenes `AlwaysOriginal`.
Los selectores usan un botón custom con UIImageView y UILabel, sin una imagen
de UIButtonConfiguration. Conserva la columna de 64 puntos, el tamaño de Samsung,
las marcas, accesibilidad, texto adaptable, estado seleccionado y pulsación.
La caché distingue color resuelto, escala y relleno; el cambio de apariencia
reconstruye la presentación. No se fuerza un renderer global de CoreImage.

El diario añade `catalog_ui: view_loaded / appeared`, con el identificador
`cg-bitmap-original-v1`. `appeared` registra el callback de UIKit, no acredita
que la GPU haya completado un frame ni una recepción de radio.

Es una **mitigación candidata**, no una causa raíz ni solución física confirmadas.
Bluetooth permanece en `2.0.0~diagnostic2`; no cambian sus fuentes ni permisos.

## Validación y aceptación

Las pruebas UI comprueban logos con alfa, color ya aplicado, escala 1x/2x/3x,
tema claro/oscuro, caché y ausencia de imágenes configuradas/template en los
selectores. Se conserva la regresión de generación, reproducción individual,
emisión conjunta y Detener con el backend simulado. Esto no reproduce el driver
gráfico de un A11 ni acredita emisión en ese dispositivo.

Fuentes compiladas: `57a6e91d504e28df08110efcc61a740d50866771`.

- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/38088747679): aprobado.
- [Compatibilidad con destino iOS 15](https://github.com/Gokuencinar/NukeWireless/actions/runs/38088747594): aprobado.
- [Migración dpkg Linux](https://github.com/Gokuencinar/NukeWireless/actions/runs/38088747704): aprobado.
- 46 comprobaciones UI y cuatro ciclos reales de segundo plano por idioma,
  español e inglés, en ambas compilaciones. Incluyen los bitmaps ya coloreados.
- Core: 7 comprobaciones; candidatos: 8; unificados: 6 locales y 3 exclusivas
  de Linux en CI; loader: 3; rutas/whitelist: 3. Todas aprobadas.
- Capturas claro/oscuro revisadas, con marcas orientadas y alineadas.

Los tres DEB unificados y manifiestos están en `outputs/diagnostic9-unified`
del directorio de esta conversación. El informe de investigación conserva una
comparación sin identificadores personales de las tres trazas. No se ha instalado
esta candidata en un dispositivo ni publicado en el repositorio APT.

Pendiente: instalar la variante rootless en el iPhone 8 Plus, abrir/cerrar el
catálogo repetidamente y cambiar de marca y tema. La aceptación del catálogo y
la disponibilidad de radio son pruebas separadas.

Referencia pública de renderingMode:
https://developer.apple.com/documentation/uikit/uiimage/renderingmode-swift.enum/alwaysoriginal
