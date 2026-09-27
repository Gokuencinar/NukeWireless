# Nuke Wireless: Info y actualización Wi-Fi

Esta variante parte del paquete funcional `com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb`. Conserva sin cambios el ejecutable de la app, `HarpyRootHidePaths.dylib`, `NukeWirelessPaths.dylib` y los auxiliares de red. Añade una biblioteca para Info y el botón «Actualizar» de Wi-Fi.

Info muestra los créditos **Gokuencinar GokuEn** con el avatar incluido en el paquete base, enlaces a [GitHub](https://github.com/Gokuencinar) y [Buy Me a Coffee](https://buymeacoffee.com/gokuen), y celdas para SSID, BSSID, IPv4, puerta de enlace, máscara y primer servidor DNS. Al tocar una celda se copia su valor. Para mostrar SSID/BSSID, iOS solicita permiso de ubicación al abrir Info; si se deniega, la celda indica que falta autorización. El botón «Actualizar» de Wi-Fi llama al mismo reescaneo del gesto de deslizar.

## Compilación

El workflow `.github/workflows/build-info.yml` compila `src/NukeWirelessInfo.m` para iOS y guarda `prebuilt/NukeWirelessInfo_ios.dylib`. Para empaquetar en Windows:

```powershell
python -m pip install -r requirements-info.txt
python scripts/build_nuke_info_deb.py 'C:\ruta\a\com.gokuencinar.nukewireless_1.0.25+rh25_iphoneos-arm64e.deb'
```

El script comprueba el SHA-256 del paquete base (`f4b5282bf8aec2eef2a35f84f644aa3bb6e4a16230b7c7cd2789fea6da65cdbc`) y genera `dist/com.gokuencinar.nukewireless_1.0.25+rh25.2_iphoneos-arm64e.deb`. Los binarios existentes se copian byte por byte. Cambian los metadatos de versión, el texto de permiso de ubicación en `Info.plist`, la firma/entitlements necesarios para consultar la red y los tres archivos de la extensión.

La compilación y el empaquetado se pueden comprobar fuera del dispositivo; la visualización de Info y el acceso a SSID/BSSID requieren prueba en el iPhone.
