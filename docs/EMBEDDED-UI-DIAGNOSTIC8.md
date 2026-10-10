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
- CI pendiente: compilación iOS, navegación real del simulador en ambos idiomas,
  cuatro ciclos de segundo plano y migración/retirada dpkg de las tres variantes.
- Paquetes finales y aceptación física: pendientes.

Los tests del simulador enlazan la interfaz directamente y comprueban una única
copia cargada, la inicialización del adaptador de prueba y la ocultación del
contenido heredado explícito. El JSON de entorno incluye `ui_integration` y
`embedded_in_app` sin publicar las rutas privadas del dispositivo.

Prueba física necesaria: instalar el DEB de su esquema, abrir Información,
Bluetooth y Diagnósticos, volver desde segundo plano y repetir con la inyección
de tweaks deshabilitada únicamente para NukeWireless. La carga de esta interfaz
no prueba por sí sola el bloqueo Wi-Fi ni las funciones privadas Bluetooth.
