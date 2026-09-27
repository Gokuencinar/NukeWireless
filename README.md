# Harpy Reloaded para Dopamine 2 RootHide

Adaptación de Harpy Reloaded para iPhone XS con iOS 16.3.1 y Dopamine 2 RootHide. La versión visible probada es **1.0.24** (`1.0.24+rh24` en el gestor de paquetes).

## Estado comprobado

- La app abre y muestra los menús.
- En una red Wi-Fi de prueba, «Block device» corta Internet al equipo seleccionado y «Desbloquear» lo devuelve sin cerrar Harpy.
- Info conserva «Advanced Settings» y la versión; los apartados «Credits», «Acknowledgements» y «Special Thanks» quedan ocultos en esa pantalla.
- El escaneo conserva una sola entrada del iPhone y evita su duplicado sin nombre.
- Si un equipo no publica su nombre, aparece como «Equipo .N». La marca se obtiene del prefijo MAC mediante una copia local de la [lista pública MA-L de IEEE](https://standards.ieee.org/products-programs/regauth/). Una dirección MAC privada puede mostrar «Private MAC».
- En Wi-Fi, «Bloquear todos» requiere una segunda pulsación de confirmación en 10 segundos. En la prueba con 15 equipos, todos perdieron la conexión y «Desbloquear todos» la restauró sin cerrar la app. El router y el propio iPhone quedan excluidos. El botón de desbloqueo detiene los bloqueos que inició el botón conjunto.

El bloqueo usa ARP. Esta adaptación no ofrece desautenticación Wi-Fi. Úsala únicamente con dispositivos y redes que administras.

## Qué contiene este repositorio

- `src/HarpyRootHidePaths.c`: adaptación de rutas y del proceso de bloqueo/desbloqueo.
- `patches/aegis_parent_check.s` y `scripts/patch_aegis.py`: adaptación del auxiliar Aegis a la ruta variable de RootHide.
- `prebuilt/HarpyRootHidePaths_ios.dylib`: compilación de la biblioteca anterior para arm64.
- `scripts/build_deb.py`: reconstrucción del paquete a partir de una copia original obtenida por el usuario.
- `scripts/update_oui.py`: crea la tabla local de fabricantes desde `oui.csv` de IEEE.

El `.deb` original y los binarios de terceros no se incluyen aquí. Conservan los derechos de sus respectivos autores. Para generar el paquete necesitas tu propia copia de `xyz.cypwn.harpy-reloaded_1.0.1k_iphoneos-arm64.deb`.

## Reconstrucción en Windows

Necesitas Python 3, `keystone-engine`, el `.deb` original, el [CSV MA-L de IEEE](https://standards-oui.ieee.org/oui/oui.csv) y acceso a `ldid` en el iPhone para instalar el paquete generado.

```powershell
python -m pip install keystone-engine
$env:HARPY_SOURCE_DEB = 'C:\ruta\a\xyz.cypwn.harpy-reloaded_1.0.1k_iphoneos-arm64.deb'
python scripts/update_oui.py C:\ruta\a\oui.csv
python scripts/patch_aegis.py
python scripts/build_deb.py
```

El paquete aparece en `dist/`. La instalación requiere Dopamine 2 RootHide y las dependencias que indica el propio paquete (`rootless-compat`, `ellekit`, `arpoison`, `network-cmds` y `ldid`).

## Alcance

La biblioteca enlaza con puntos concretos de Harpy Reloaded 1.0.1k; no se ha validado con otra compilación de la app, otro modelo de iPhone ni otra versión de iOS. La marca indica el titular registrado del prefijo MAC y puede diferir de la marca comercial del dispositivo.

