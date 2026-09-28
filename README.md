# Nuke Wireless

Nuke Wireless is in development. This repository and its development artifacts are private.

## Desarrollo actual

**Estado actual:** `1.0.25+rh25.3` está restaurada en el iPhone y el usuario confirmó que abre con normalidad. La candidata `1.0.25+rh25.5~dev3` queda **retirada**: se instala y carga la extensión, pero la app permanece en la pantalla azul inicial. No debe distribuirse ni instalarse. Las candidatas `dev1` y `dev2` también están retiradas.

La rama `audit-rh25.5` conserva el trabajo de investigación, sin release ni publicación en el repositorio de paquetes. Los cambios siguientes son experimentales hasta resolver la regresión de arranque:

- Info usa una tabla con alturas calculadas, sin banner ni superposiciones de altura fija. Incluye créditos, avatar, enlaces, red actual y copia al portapapeles.
- Actualizar y deslizar ejecutan la renovación nativa de la lista con una nueva instancia del escáner por sesión, descarte de callbacks antiguos y recuperación tras errores.
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

Ejecuta las pruebas C y Foundation, compila para iOS arm64 y escribe la biblioteca y su manifiesto en `build/audit/`. El workflow `audit-build.yml` ejecuta lo mismo en la rama de desarrollo. Solo sube un artefacto temporal dentro del repositorio privado: no crea releases, no modifica `main` y no hace commits automáticos.

En Windows o macOS con Python 3:

```text
python scripts/build_nuke_info_deb.py dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb
python tests/test_package.py
python tests/test_native_abi.py
```

Antes de empaquetar en Windows, descarga la biblioteca y `build-manifest.json` del build privado a `build/audit/`. El empaquetador rechaza una base distinta o un artefacto que no corresponda a las fuentes actuales. No ejecuta scripts del paquete. El paquete de desarrollo y su manifiesto quedan en `dist/` y están excluidos de Git.

`dev3` se instaló por SSH en iOS 16.3.1 con Dopamine RootHide, pero no llegó a la interfaz principal. La carga de la extensión y la creación del control en los registros no prueban un arranque funcional. Se restauró la base `rh25.3` y se retiró la deb de la carpeta de entrega. Véase el informe.
