# Nuke Wireless

Nuke Wireless is in development. This repository is public; development builds are not releases.

## Desarrollo actual

**Última candidata instalada:** `1.0.25+rh25.5~dev15`. Conserva el estilo WiFi confirmado de dev14 y añade un aviso visible tras copiar un dato válido de red. La decoración de carga ahora se coloca sobre la ventana inicial, sin depender de un controlador llamado SplashView; se retira al aparecer las pestañas y tiene un límite de cuatro segundos. Compilación y navegación automática correctas e instalación SSH confirmada. Pendiente confirmación física de la transición de inicio.

El usuario confirmó el resto de dev14, pero la pantalla azul de carga continuaba. Apartar su caché de SplashBoard tampoco resolvió el problema.

`dev13` fue confirmada por el usuario como funcional, incluido el ajuste de Actualizar.

**Cambio de idioma comprobado:** `1.0.25+rh25.5~dev11`. Añade **Info → Idioma** para elegir español o inglés. La selección se guarda en la app y se aplica al cerrarla desde la confirmación y volver a abrirla. No permite cerrar para cambiar el idioma mientras hay un escaneo o bloqueos activos. Incluye catálogos para la extensión, las vistas SwiftUI originales y los controles UIKit; los nombres reales de redes/equipos y sus direcciones se conservan.

Las capturas del simulador confirman las pestañas, los textos de WiFi y el contenido de Info en ambos idiomas. La prueba conserva los hosts SwiftUI y verifica traducciones de alertas, botones y campos. El núcleo original se conserva como binario: estas pruebas no equivalen a comprobar visualmente cada ruta de la aplicación en el iPhone. `dev10` es la versión anterior confirmada por el usuario: Info abre y el título «Harpy» ya no aparece.

`dev9` quedó retirada de la release pública: reemplazar el controlador de pestaña provocó una conversión de tipo fallida en SwiftUI al entrar en Info, confirmada en el registro de cierre del dispositivo.

**Última versión comprobada en el iPhone:** `1.0.25+rh25.5~dev8` (iOS 16.3.1, Dopamine RootHide). Arranca y termina el escaneo inicial. «Bloquear todos» enlaza el botón real dentro del panel heredado y encuentra la puerta de enlace mediante SystemConfiguration cuando la propiedad antigua está vacía. Una prueba diagnóstica contó 11 equipos aptos y abrió la confirmación. El usuario confirmó en el iPhone que «Bloquear todos» y «Desbloquear todos» funcionan. La observación por SSH no permitió medir por separado el efecto sobre cada equipo de la red; después de la prueba no quedaron procesos `arpoison` activos.

`dev6` resolvió el bloqueo de arranque, pero Actualizar mostraba «The scanner is not ready». RootHide carga `systemhook` como imagen dyld 0; el código buscaba ahí la función Swift del ejecutable. `dev7` fue un parche binario para ese dispositivo. Desde que el repositorio es público, GitHub Actions compiló la solución fuente que busca el ejecutable por nombre; `dev8` contiene esa compilación y la corrección de los controles masivos.

La rama `audit-rh25.5` conserva el trabajo de desarrollo. Las candidatas se distribuyen como prereleases; no se publican en el repositorio de paquetes. Los cambios siguientes forman parte de la candidata:

- Info usa una tabla con alturas calculadas, sin banner ni superposiciones de altura fija. Incluye créditos, avatar, enlaces, red actual y copia al portapapeles.
- Actualizar y deslizar ejecutan la renovación nativa de la lista; el puente observa sus callbacks y recupera el estado tras errores.
- Bloquear todos utiliza los métodos del bloqueo/desbloqueo individual. Excluye el iPhone, la puerta de enlace y direcciones inválidas; contabiliza fallos parciales.
- Ajustes avanzados mantiene el intervalo entre paquetes y permite actualizar/restaurar la tabla de fabricantes. No incluye el antiguo botón para repetir la introducción.
- Info incluye el selector de español e inglés; inicialmente usa el idioma del sistema y después conserva la elección del usuario.

Consulta [el informe de auditoría](docs/AUDIT-rh25.5.md) para conocer las causas, pruebas y límites de validación.

## Arquitectura y compatibilidad

Este proyecto contiene una extensión y herramientas de adaptación; **no contiene el código Swift original completo**. Se conservan las dos bibliotecas de rutas y los auxiliares del paquete base. En el ejecutable original solo se sustituyen dos textos visibles manteniendo exactamente su longitud; sus instrucciones permanecen intactas.

Las rutas `HarpyReloaded.app`, las clases Swift `_TtC13HarpyReloaded…`, el bundle ID `me.midnightchips.harpy-reloaded` y las preferencias existentes son identificadores de compatibilidad. No deben renombrarse. `src/HarpyRootHidePaths.c`, `scripts/build_deb.py` y el parche de Aegis son material histórico: no se recompilan ni aplican al generar esta versión.

Objetivo: iOS 16.3 con Dopamine RootHide. SSID/BSSID se consultan mediante MobileWiFi sin solicitar ubicación; el acceso efectivo depende del dispositivo.

## Compilación

En macOS con Xcode:

```bash
bash scripts/build_extension.sh
```

Ejecuta las pruebas C y Foundation, compila para iOS arm64 y escribe la biblioteca y su manifiesto en `build/audit/`. El workflow `audit-build.yml` ejecuta lo mismo en la rama de desarrollo y sube un artefacto temporal. No crea releases, no modifica `main` y no hace commits automáticos.

La antigua candidata `dev7` se reproduce localmente desde el paquete `dev6` fijado por SHA-256:

```text
python scripts/build_dev7_patch.py
python tests/test_dev7_patch.py
```

El empaquetador comprueba el hash de entrada y la instrucción exacta antes de parchear. `dev7` no equivale a una recompilación de la fuente actual; el parche solo adapta la selección de imagen dyld para este dispositivo RootHide.

En Windows o macOS con Python 3:

```text
python scripts/build_nuke_info_deb.py dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb
python tests/test_package.py
python tests/test_native_abi.py
```

Antes de empaquetar en Windows, descarga la biblioteca y `build-manifest.json` de Actions a `build/audit/`. El empaquetador rechaza una base distinta o un artefacto que no corresponda a las fuentes actuales. No ejecuta scripts del paquete. El paquete de desarrollo y su manifiesto quedan en `dist/` y están excluidos de Git.

`dev3` se instaló por SSH en iOS 16.3.1 con Dopamine RootHide, pero no llegó a la interfaz principal. La carga de la extensión y la creación del control en los registros no prueban un arranque funcional. Se restauró la base `rh25.3` y se retiró la deb de la carpeta de entrega. Véase el informe.
