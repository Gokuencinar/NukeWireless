# Candidatas de compatibilidad iOS 15–18

La referencia funcional sigue siendo dev18; dev19 está instalada y sus funciones
nuevas están pendientes de comprobación. Este port genera **candidatas
experimentales**, no una afirmación de funcionamiento en dispositivos que no
se han probado. El único dispositivo disponible es iOS 16.3.1 con Dopamine
RootHide; no se instala automáticamente este port sobre él.

## Variantes

| Paquete | Arquitectura Debian | Ubicación de la app | Bibliotecas inyectadas | Entorno previsto |
| --- | --- | --- | --- | --- |
| RootHide | iphoneos-arm64e | /Applications/HarpyReloaded.app | /usr/lib/TweakInject | Dopamine RootHide y Relaxin con bootstrap RootHide |
| Rootless | iphoneos-arm64 | /var/jb/Applications/HarpyReloaded.app | /var/jb/Library/MobileSubstrate/DynamicLibraries | Dopamine convencional |
| Rootful | iphoneos-arm | /Applications/HarpyReloaded.app | /Library/MobileSubstrate/DynamicLibraries | Jailbreak rootful que soporte el dispositivo/iOS |

Las tres variantes conservan `com.gokuencinar.nukewireless`, el bundle ID,
las preferencias y los identificadores privados del ejecutable. Se instala
solo la variante correspondiente al bootstrap. Las arquitecturas Debian no
son arquitecturas Mach-O: la app conservada y sus extensiones son **arm64**,
también en el paquete RootHide. No hay soporte para procesos de 32 bits.

Objetivo de compilación y dependencia de instalación: iOS 15.0–18.x. Eso no
crea un jailbreak para cada modelo/versión. Hay que comprobar primero la
matriz real del jailbreak; RootHide es un esquema de bootstrap, no una versión
de iOS. Relaxin usa la candidata RootHide solo en sus instalaciones RootHide.

## Qué cambia

- La extensión de interfaz se recompila con mínimo iOS 15.0 y avisos
  de disponibilidad tratados como errores. Conserva idioma, Info, copia,
  Actualizar, bloqueo masivo y diseño.
- `compat1` corresponde a dev18; `compat2` incorpora el panel de búsqueda,
  filtros, ordenación y los colores de dev19. Sus funciones nuevas se limitan
  a presentación y preferencias, según [DEVICE-BROWSER.md](DEVICE-BROWSER.md).
- `src/compat/NWLegacyPaths.c` recupera el adaptador del commit
  `29614397b9b3744f65bfa00aefaa734c3477b9d0` del checkout histórico. El hash de
  su prebuilt coincide **exactamente** con `NukeWirelessPaths.dylib` de rh25.3:
  `33244c638df562b6a16899a82e0fb7045fc96713ac276f4069037941c403db78`.
  Hash SHA-256 de la fuente recuperada, con LF:
  `39352e26eaf6e1d2e08fd661757683e69e884fbc108c506768f17f0f200ebcc8`.
- Se recompila ese adaptador para iOS 15. No se reduce simplemente el campo
  de versión mínima de las antiguas bibliotecas compiladas para iOS 16.3.
- Las candidatas emplean **un solo adaptador**: retiran la segunda copia,
  `HarpyRootHidePaths.dylib`, que también requiere 16.3 y sobreescribe los
  mismos métodos. Este cambio necesita comprobación funcional propia.
- La raíz de recursos se deriva de la ubicación real de la app. `/Applications`
  equivale a raíz sin prefijo; se evita añadir `/var/jb` dos veces al procesar
  argumentos. Las rutas Apple y los datos del usuario no se prefijan.
- Antes de intervenir en el desbloqueo Swift se verifican los bytes de las
  entradas del ejecutable fijado. El filtro y el guard interno seleccionan
  únicamente `me.midnightchips.harpy-reloaded`.
- Aegis conserva la validación del **camino completo del proceso padre** y
  exige que app y auxiliar estén en la misma raíz. Se adapta el control ya
  presente en arm64e a arm64, con offsets e instrucciones verificados y hash
  del binario original obligatorio. No se permite un padre arbitrario.
- El puente opcional antiguo de `libjailbreak` comprueba ahora las dos
  direcciones devueltas por `dlsym` antes de invocarlas. Si una implementación
  nueva no exporta esos símbolos, el auxiliar no llama a una dirección nula.
- Los auxiliares se empaquetan con su slice arm64. Las firmas se renuevan al
  instalar. Los enlaces `.roothidepatch` y `rootless-compat` se conservan
  exclusivamente en RootHide; los otros paquetes usan `mobilesubstrate`.
- El constructor inspecciona mínimos de iOS y dependencias enlazadas de cada
  Mach-O empaquetado. Rechaza artefactos antiguos, fuentes distintas y binarios
  que requieran iOS superior a 15.

## Construcción reproducible

En macOS con Xcode:

```bash
bash scripts/build_compat.sh
python3 scripts/build_compat_debs.py \
  dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb \
  --artifact build/audit
```

El workflow `compat-build.yml` compila y conserva un artefacto temporal;
no instala, publica releases ni modifica un repositorio de paquetes. La base
rh25.3 se necesita localmente y está fijada por SHA-256. Cada `.deb` tiene un
manifiesto adjunto y `compatibility.json` con `runtime_verified: false`.

## Qué falta demostrar

Todavía no se han observado arranque, carga de la extensión, dos escaneos,
bloqueo/desbloqueo, lectura de SSID/BSSID ni restauración de red en iOS 15,
17 o 18. Foundation/NSTask, MobileWiFi y las restricciones de ejecución de
auxiliares pueden variar entre sistemas y bootstraps. Sus símbolos y métodos
en las versiones nuevas requieren observación, además de un build correcto.
El núcleo Swift original se conserva en binario: este repositorio no contiene
su fuente completa ni puede garantizar sus llamadas privadas en otro iOS.

Antes de distribuir una variante como estable: instalar en su dispositivo de
destino, comprobar arranque y escaneo, autorizar un ciclo de bloqueo/desbloqueo
y verificar que no queden auxiliares activos. Para volver atrás en el iPhone
actual, reinstalar la deb dev18 conservada mediante `dpkg -i` y abrir la app.
No instalar una variante de otro esquema ni forzar su arquitectura.

## Referencias contrastadas el 4 de octubre de 2026

- [Theos: rootless, prefijos y arquitecturas de paquete](https://theos.dev/docs/rootless).
- [RootHide: port de aplicaciones y requisitos de firma](https://github.com/roothide/Developer).
- [Dopamine: soporte actual por dispositivo/iOS](https://ellekit.space/dopamine/).
- [Relaxin: proyecto oficial](https://github.com/owngoal-dev/Relaxin).
- Referencia local del usuario: BandLock 1.0/1.2, variantes Dopamine,
  RootHide y Rootful. Sus descripciones también distinguen iOS experimentales;
  compartir empaquetado no demuestra las APIs de red de NukeWireless.
