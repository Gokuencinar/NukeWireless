# Nuke Wireless

Adaptación RootHide para iOS 16 que amplía las herramientas Wi-Fi: muestra los dispositivos de la red local, permite guardar nombres para ellos y ofrece controles para bloquearlos mediante ARP.

La app presenta la marca **Nuke Wireless**, un icono propio y créditos para **Gokuencinar · GokuEn** en la pestaña Info.

## Funciones

- Lista de dispositivos conectados a la red Wi-Fi y sus direcciones IP/MAC.
- Bloqueo y desbloqueo de un dispositivo, con confirmación para la acción conjunta.
- Alias guardados por dirección MAC y resolución local de nombres cuando está disponible.
- Actualización de la lista al deslizar hacia abajo.
- Aviso cuando la interfaz Wi-Fi tiene IPv6; el bloqueo ARP solo cubre IPv4.
- No ofrece desautenticación Wi-Fi. Utilízalo únicamente en redes y dispositivos que administras.

## Créditos

**Gokuencinar · GokuEn**. La pestaña Info muestra el mismo avatar de perfil que se usa en BandLock.

## Contenido del repositorio

- `src/NukeWirelessPaths.c`: adaptación RootHide, controles de red y créditos.
- `patches/aegis_parent_check.s` y `scripts/patch_aegis.py`: parche del auxiliar para la ruta variable de RootHide.
- `prebuilt/NukeWirelessPaths_ios.dylib`: biblioteca iOS arm64 generada por el workflow de macOS para la rama de Nuke Wireless.
- `assets/NukeWirelessIcon.png`: icono de la app.
- `assets/CreditsAvatar.jpg`: avatar de perfil usado también en BandLock.
- `scripts/build_deb.py`: reconstrucción del paquete a partir del paquete original proporcionado por el usuario.
- `scripts/update_oui.py`: genera la tabla local de fabricantes a partir del CSV MA-L de IEEE.

## Reconstrucción

Necesitas Python 3, `keystone-engine`, el paquete original de la app, el CSV MA-L de IEEE y acceso a `ldid` en el iPhone para instalar el paquete generado.

```powershell
python -m pip install keystone-engine
$env:NUKE_WIRELESS_SOURCE_DEB = 'C:\ruta\al\paquete-original.deb'
python scripts/update_oui.py C:\ruta\a\oui.csv
python scripts/patch_aegis.py
python scripts/build_deb.py
```

El paquete aparece en `dist/` como `com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb`. Declara el conflicto y reemplazo del paquete anterior para evitar que ambas variantes instalen la misma app a la vez.

## Compatibilidad técnica

Esta adaptación inyecta código en una app de terceros y enlaza con sus clases privadas, su identificador de bundle y las rutas de sus ejecutables. Esos identificadores heredados se conservan donde son necesarios para que la integración funcione; el nombre visible de la app, el paquete y los recursos propios usan **Nuke Wireless**. La integración de la versión 1.0.25 necesita validación en el dispositivo.

La compilación de la biblioteca requiere macOS y el SDK de iOS configurado en el workflow de GitHub Actions. El `.deb` de origen tampoco está incluido; debes aportar una copia que tengas derecho a modificar.

