# Interfaz integrada · diagnostic8

Un tester con iPhone 13 Pro Max / iOS 16.3.1 / RootHide mostró la pantalla Info
heredada de diagnostic6: tres pestañas, créditos antiguos y «Don't pirate!».
La captura es compatible con una extensión sin cargar; no establece si la causa
es una blacklist, el inyector, la instalación o la inicialización.

## Cambio

La app incorpora `Frameworks/NukeWirelessInfo.dylib` y
`Frameworks/NukeWirelessPaths.dylib`. Su ejecutable tiene dos dependencias
`LC_LOAD_DYLIB` obligatorias con rutas relativas a su propio bundle. La carga
de la interfaz actual deja de depender de la inyección de tweaks del bootstrap.
Si falta una biblioteca obligatoria, dyld rechaza el lanzamiento; no abre las
pantallas antiguas como alternativa. No se añade una pantalla de error propia
antes de dyld ni se promete recuperar automáticamente una instalación dañada.

Se retiran las copias y filtros externos de ambas bibliotecas. dpkg elimina
los archivos que poseían las versiones anteriores al actualizar. No se borran
directorios de inyección de otros paquetes ni preferencias del usuario.
El adaptador se inicializa una sola vez antes de envolver sus métodos, con
independencia del orden de los constructores. La firma mantiene
`me.midnightchips.harpy-reloaded` y se firman primero las bibliotecas integradas.

Los tres hosts SwiftUI y el delegado originales permanecen: el motor heredado
los necesita. La pantalla Info vigente sigue contenida en su host. No se ha
reescrito ni eliminado físicamente todo el código Swift del ejecutable base;
se elimina la vía de arranque sin interfaz actual. Los créditos/licencias
históricos del código conservado no se suprimen de sus archivos legales.

Versión de la app: `2.0.0~diagnostic8`, build `20008`; instalador unificado:
`2.0.0~diagnostic8+bundle1`. Bluetooth sigue en `2.0.0~diagnostic2`: no cambian
sus fuentes, protocolos, permisos ni controles de compatibilidad.

## Validación

- Local: pruebas del ejecutable SHA-fijado, dependencias obligatorias, rechazo
  de dependencias débiles/duplicadas y conservación del cuerpo nativo.
- CI aprobada: compilación iOS, 46 comprobaciones de navegación por idioma y
  cuatro ciclos reales de segundo plano por idioma. Migración/retirada dpkg
  aislada aprobada en las tres variantes, incluida la actualización desde
  diagnostic7 con bibliotecas externas.
- Tres DEB finales inspeccionados: 7 pruebas del core, 8 de candidatos, 6 comprobaciones
  ejecutables del instalador, 3 del enlace integrado y 3 de rutas/whitelist.
  Las 3 pruebas dpkg omitidas en Windows pasaron en Linux.
- Aceptación física en el dispositivo del tester: pendiente.

Los tests del simulador enlazan la interfaz directamente y comprueban una única
copia cargada, la inicialización del adaptador de prueba y la ocultación del
contenido heredado explícito. El JSON de entorno incluye `ui_integration` y
`embedded_in_app` sin publicar las rutas privadas del dispositivo.

Prueba física necesaria: instalar el DEB de su esquema, abrir Información,
Bluetooth y Diagnósticos, volver desde segundo plano y repetir con la inyección
de tweaks deshabilitada únicamente para NukeWireless. La carga de esta interfaz
no prueba por sí sola el bloqueo Wi-Fi ni las funciones privadas Bluetooth.

Fuentes compiladas: `1196dcf2` (commit completo en cada manifiesto).

- [CI de compatibilidad](https://github.com/Gokuencinar/NukeWireless/actions/runs/38071471679)
- [CI de desarrollo](https://github.com/Gokuencinar/NukeWireless/actions/runs/38071471666)
- [CI de migración](https://github.com/Gokuencinar/NukeWireless/actions/runs/38071471691)

Los DEB finales están en `outputs/diagnostic8-unified` del directorio de esta
conversación, con manifiestos y `VERIFICACION-DIAGNOSTIC8.json`. No se han
instalado en el dispositivo ni publicado en GokuEnREPO como parte de esta entrega.
