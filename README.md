# Nuke Wireless

Nuke Wireless is in development. This repository and its development artifacts are private.

## Desarrollo actual

**Estado actual:** `1.0.25+rh25.5~dev7` está instalada en el iPhone (iOS 16.3.1, Dopamine RootHide). Arranca y termina el escaneo inicial. Un diagnóstico con la misma corrección de instrucción pulsó Actualizar automáticamente: el segundo escaneo terminó con 13 equipos tras un primero de 12. La versión instalada no contiene esa pulsación automática. Bloquear todos y el desplazamiento de Info siguen pendientes de comprobación visual completa.

`dev6` resolvió el bloqueo de arranque, pero Actualizar mostraba «The scanner is not ready». RootHide carga `systemhook` como imagen dyld 0; el código buscaba ahí la función Swift del ejecutable. `dev7` usa la imagen 1, comprobada por el prólogo del ejecutable fijado por hash. Se generó mediante un parche de cuatro bytes a la biblioteca `dev6` porque GitHub Actions no inicia runners macOS por el límite de facturación de la cuenta. La fuente incluye la solución general que busca la imagen por nombre, pendiente de una nueva compilación macOS.

La rama `audit-rh25.5` conserva el trabajo de investigación, sin release ni publicación en el repositorio de paquetes. Los cambios siguientes son experimentales hasta resolver la regresión de arranque:

- Info usa una tabla con alturas calculadas, sin banner ni superposiciones de altura fija. Incluye créditos, avatar, enlaces, red actual y copia al portapapeles.
- Actualizar y deslizar ejecutan la renovación nativa de la lista; el puente observa sus callbacks y recupera el estado tras errores.
- Bloquear todos utiliza los métodos del bloqueo/desbloqueo individual. Excluye el iPhone, la puerta de enlace y direcciones inválidas; contabiliza fallos parciales.
- Ajustes avanzados mantiene el intervalo entre paquetes y permite actualizar/restaurar la tabla de fabricantes. No incluye el antiguo botón para repetir la introducción.
- La extensión dispone de textos en español e inglés según el idioma del sistema.

Consulta [el informe de auditoría](docs/AUDIT-rh25.5.md) para conocer las causas, pruebas y límites de validación.

## Arquitectura y compatibilidad

Este proyecto contiene una extensión y herramientas de adaptación; **no contiene el código Swift original completo**. Se conservan las dos bibliotecas de rutas y los auxiliares del paquete base. En el ejecutable original solo se sustituyen dos textos visibles manteniendo exactamente su longitud; sus instrucciones permanecen intactas.

Las rutas `HarpyReloaded.app`, las clases Swift `_TtC13HarpyReloaded…`, el bundle ID `me.midnightchips.harpy-reloaded` y las preferencias existentes son identificadores de compatibilidad. No deben renombrarse. `src/HarpyRootHidePaths.c`, `scripts/build_deb.py` y el parche de Aegis son material histórico: no se recompilan ni aplican al generar esta versión.

Objetivo: iOS 16.3 con Dopamine RootHide. SSID/BSSID se consultan mediante MobileWiFi sin solicitar ubicación; el acceso efectivo depende del dispositivo.

## Compilación privada

En macOS con Xcode:

```bash
bash scripts/build_extension.sh
```

Ejecuta las pruebas C y Foundation, compila para iOS arm64 y escribe la biblioteca y su manifiesto en `build/audit/`. El workflow `audit-build.yml` ejecuta lo mismo en la rama de desarrollo cuando GitHub permite iniciar runners. Solo sube un artefacto temporal dentro del repositorio privado: no crea releases, no modifica `main` y no hace commits automáticos.

La candidata instalada `dev7` se reproduce localmente desde el paquete `dev6` fijado por SHA-256:

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

Antes de empaquetar en Windows, descarga la biblioteca y `build-manifest.json` del build privado a `build/audit/`. El empaquetador rechaza una base distinta o un artefacto que no corresponda a las fuentes actuales. No ejecuta scripts del paquete. El paquete de desarrollo y su manifiesto quedan en `dist/` y están excluidos de Git.

`dev3` se instaló por SSH en iOS 16.3.1 con Dopamine RootHide, pero no llegó a la interfaz principal. La carga de la extensión y la creación del control en los registros no prueban un arranque funcional. Se restauró la base `rh25.3` y se retiró la deb de la carpeta de entrega. Véase el informe.
