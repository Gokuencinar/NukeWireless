# Diagnostic19: recuperación y registro de presentación en iPad

Parte de diagnostic18; conserva el backend Wi-Fi de diagnostic16 y Bluetooth
diagnostic7. No cambia emisión, cancelación, restauración ni firma de la app.

## Cambios

- La búsqueda de las tres pestañas originales recorre también los hijos del
  controlador raíz. Tiene límites de 12 niveles y 64 controladores; no fuerza
  la carga de vistas ni reemplaza hosts o delegado SwiftUI.
- La guarda de instalación se activa antes de cambiar los traits. Información
  y Punto de acceso conservan sus propias guardas y su navegación contenida.
- En iOS 15/16, el tamaño compacto se aplica explícitamente a cada host original,
  además del override sobre el tab cuando tiene padre. El efecto físico sigue
  pendiente de comprobar; no se interpreta la API antigua sobre 18.5 como 16.0.
- Se reconcilia la presentación en cuatro momentos acotados del arranque y en
  las primeras cuatro activaciones. Solo se actúa sobre ventanas clave de esta
  app cuando está activa. No se reinicia el proceso ni se cambia la raíz.

## Datos incorporados al DEB

`NukeWirelessResources.bundle/Diagnostics/iPadPresentationReview.json` contiene
el identificador de la revisión, conclusiones verificadas y fuentes de Apple.
Se incluye en los hashes de procedencia y en la inspección del paquete.

El diario existente añade `ui_review` y `ui_presentation`. Las capturas guardan
ventanas visibles, clases y contención, tamaños, tamaño horizontal efectivo
de controladores y vistas, orientaciones admitidas, overrides del padre, estado del contenedor dividido,
selección y presencia de las dos barras. Registran el estado resumido de las
pestañas antes de reconciliar y la jerarquía posterior.

Límites por proceso: 12 capturas, dos ventanas y 12 nodos en total por captura,
profundidad máxima de ocho y payload ajustado a 7600 bytes. Las observaciones
UIKit se realizan en el hilo principal y la escritura usa la cola existente.
No se recogen textos de pantalla, SSID, IP, MAC ni direcciones de memoria.

Los datos se exportan desde Información → Diagnósticos. Si la interfaz falla,
el mismo diario se guarda automáticamente como `NukeWireless-Diagnostics/latest.json`
en Documents de la app y puede recuperarse desde Archivos cuando esté disponible.
No se añaden pantallas técnicas ni permisos nuevos.

## Validación de la entrega

La regresión añade búsqueda real en una jerarquía UIKit, comprobación del recurso
incluido y exportación de la estructura sin truncamiento. El iPad se prueba con
arranque vertical y horizontal, rotaciones y cuatro ciclos de segundo plano
por idioma. Las pruebas se ejecutan sobre el runtime instalado en CI.

La ruta normal del runtime es obligatoria. El experimento `legacy-traits` queda
disponible mediante workflow_dispatch con selección explícita; no demuestra
compatibilidad con un runtime anterior y no sustituye la prueba de iPadOS 16.

Las cinco validaciones CI pasaron para las fuentes `f5d6337b3d628056ce9135b960497501ba714865`.
Las pruebas de interfaz completaron 47 comprobaciones y cuatro ciclos reales
entre segundo plano y primer plano por idioma (español e inglés), tanto en
el iPhone simulado como en cada orientación inicial del iPad. En el iPad
se comprobaron además las rotaciones y los registros estructurados.
Los runtimes exactos, trabajos, hashes y paquetes están en
[el registro de entrega](evidence/ipad-presentation-diagnostic19-delivery.json).

Se generaron y verificaron los DEB unificados RootHide, Dopamine/rootless y
rootful, versión `2.0.0~diagnostic19+bundle1`, con Bluetooth diagnostic7 incluido.
Incluyen el recurso de revisión byte por byte. Pasaron las inspecciones de
paquete, identidad, procedencia, carga de la biblioteca integrada y disposición
de archivos. Las pruebas aisladas de dpkg cubren los tres esquemas.

La aceptación física del iPad Pro con iPadOS 16.0 y Dopamine sigue pendiente.
El simulador de CI no reproduce ese runtime ni verifica las interfaces de radio
del iPad físico. La versión se entrega como candidata de diagnóstico; no se
considera resuelto el fallo del tester hasta comprobarla allí.
