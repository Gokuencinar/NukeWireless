# Nuke Wireless: extensión de Info

Esta variante parte del paquete funcional `com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb`. Conserva sin cambios la app, `HarpyRootHidePaths.dylib`, `NukeWirelessPaths.dylib` y los auxiliares de red. Añade únicamente una biblioteca para la pestaña Info.

Info muestra los créditos **Gokuencinar · GokuEn** con el avatar incluido en el paquete base, enlaces a [GitHub](https://github.com/Gokuencinar) y [Buy Me a Coffee](https://buymeacoffee.com/gokuen), y los datos de la conexión Wi-Fi: SSID, BSSID, IPv4, puerta de enlace, máscara y primer servidor DNS. Los datos se actualizan al abrir Info. iOS puede ocultar SSID y BSSID si no autoriza el acceso a la información Wi-Fi; en ese caso se muestra «No disponible».

## Compilación

El workflow `.github/workflows/build-info.yml` compila `src/NukeWirelessInfo.m` para iOS y guarda `prebuilt/NukeWirelessInfo_ios.dylib`. Para empaquetar en Windows:

```powershell
python -m pip install -r requirements-info.txt
python scripts/build_nuke_info_deb.py 'C:\ruta\a\com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb'
```

El script comprueba el SHA-256 del paquete base (`f4b5282bf8aec2eef2a35f84f644aa3bb6e4a16230b7c7cd2789fea6da65cdbc`) y genera `dist/com.gokuencinar.nukewireless_1.0.25+rh25.1_iphoneos-arm64e.deb`. Los binarios existentes se copian byte por byte. Solo cambian los metadatos de versión, la firma/entitlements necesarios para consultar la red y los tres archivos de la extensión Info.

La compilación y el empaquetado se pueden comprobar fuera del dispositivo; la visualización de Info y el acceso a SSID/BSSID requieren prueba en el iPhone.
