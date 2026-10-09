# Candidatas de compatibilidad iOS 15–18: compat4

Edición actual para testers: [NukeWireless Dev 2.0.0~diagnostic1](DIAGNOSTIC-EDITION.md).
Las validaciones históricas de dev53/compat4 no equivalen a aceptación de esta edición.

Preparadas desde las fuentes de **dev53**, con el trabajador **app32**.
Dev53/app32 está instalado y verificado en iPhone XS / iOS 16.3.1 / Dopamine
RootHide; la última aceptación manual de interfaz corresponde a dev52/app31.
Las candidatas compat4 no se han instalado: su adaptador recompilado y los
otros bootstraps requieren validación física propia. El usuario no dispone de
dispositivos adicionales. Las entregas anteriores conservan sus informes;
no reutilizar artefactos antiguos para estas fuentes.

El mínimo de build 15.0 y la dependencia `< 19.0` delimitan el rango experimental.
La emisión ya admite sistemas que cumplan el contrato Skywalk observado, sin
whitelist XS/16.3.1. Esto no acredita funcionamiento en cada chip o versión menor.
Véase [port y fuentes primarias de ABI](BLUETOOTH-SKYWALK-PORT.md).

## Paquetes separados

| Variante | Arquitectura Debian | App | Inyección | Entorno previsto |
| --- | --- | --- | --- | --- |
| RootHide | iphoneos-arm64e | /Applications/HarpyReloaded.app | /usr/lib/TweakInject | Bootstrap RootHide |
| Dopamine rootless | iphoneos-arm64 | /var/jb/Applications/HarpyReloaded.app | /var/jb/Library/MobileSubstrate/DynamicLibraries | Dopamine convencional |
| Rootful | iphoneos-arm | /Applications/HarpyReloaded.app | /Library/MobileSubstrate/DynamicLibraries | Jailbreak rootful compatible con el equipo/iOS |

Solo instalar la variante del bootstrap real. Todas contienen Mach-O **arm64**;
la etiqueta Debian RootHide no convierte la app en arm64e. Conservan los IDs
de paquete y el bundle ID `me.midnightchips.harpy-reloaded` para preferencias,
datos y permiso Bluetooth. El script de firma fija también ese identificador
en el CodeDirectory; se corrige la omisión de las candidatas antiguas.

La app tiene versión `1.0.25+rh25.6~compat4`, CFBundleVersion `25.6.4` y manifiesto
que identifica el núcleo dev53. El marcador compilado del núcleo sigue siendo
`NWBuild-rh25.5-dev53`. El trabajador pasa a app32 porque sus fuentes y política de admisión cambian.
No se atribuye la validación del núcleo de desarrollo al adaptador compat4.

## Adaptación actual

- Un solo listado de fuentes: `build_compat.sh` reutiliza `build_extension.sh`
  con `NW_MIN_IOS=15.0`. Incluye `NWMainTabs` y `NWBluetoothCatalog`, ausentes
  del build histórico. El build de desarrollo habitual conserva mínimo 16.3.
- La compilación trata los usos de API sin guard de disponibilidad como error.
  El mismo parámetro permite compilar la regresión del simulador con mínimo 15.
  Su `runtime.json` identifica el iOS realmente ejecutado: no equivale a probar
  todos los sistemas desde el deployment target.
- Se conservan las cuatro pestañas, catálogo de seis modelos, emisión individual
  o de todos, Detener, final silencioso, logos alineados, créditos GokuEn y
  acciones Wi-Fi desde resultados de búsqueda.
- El adaptador de rutas recuperado se recompila para iOS 15. Se retira la copia
  `HarpyRootHidePaths.dylib`, que requiere 16.3 y sobrescribe los mismos métodos.
  Esa sustitución requiere una aceptación física propia.
- Las rutas se derivan de la app y auxiliares instalados. El mismo esquema se
  aplica a `nwbt-run`, `nwbt-inspect`, biblioteca y sus scripts de firma.
  RootHide mantiene sus enlaces `.roothidepatch` y `rootless-compat`; las otras
  variantes no los llevan.
- Aegis conserva la comprobación del camino completo del padre en la misma
  raíz. El port arm64 verifica hash, offsets e instrucciones de la base antes
  de adaptar la whitelist y proteger los símbolos opcionales de libjailbreak.
  No se reduce artificialmente el deployment target de binarios antiguos.
- Cada Mach-O se inspecciona: arquitectura, mínimo de iOS y dependencias. Los
  manifiestos rechazan fuentes o hashes distintos. Las pruebas inspeccionan
  los tres esquemas, firma, recursos, padres, duplicados y rechazos de artefactos.

## Bluetooth y funciones privadas

El catálogo visual y el escáner CoreBluetooth no dependen de que esté admitida
la emisión nativa. `--status` comprueba símbolos, firmas y descriptor HCI Skywalk.
Antes de configurar anuncios se comprueban respuestas y comandos soportados del
controlador. Se conservan límites, Detener, final silencioso y recuperación del
dominio real de bluetoothd. No se añaden permisos ni controladores alternativos.

El diagnóstico ACT y ACL antiguo mantiene la whitelist exacta y hash originales.
Un equipo sin HCI Skywalk sigue sin emisión nativa. Solo la referencia RootHide
tiene instalación física de app32; Dopamine convencional, rootful y los otros
iOS necesitan pruebas propias. La respuesta HCI, recepción externa y aviso del
receptor son evidencias distintas.

El núcleo Swift original se conserva como binario, sin su fuente completa.
Foundation/NSTask, MobileWiFi y los auxiliares pueden variar. Wi-Fi, escaneo BLE,
emisión y apariencia necesitan evidencias separadas.

## Construcción y comprobaciones

En macOS con Xcode:

```bash
bash scripts/build_compat.sh
NW_MIN_IOS=15.0 bash scripts/test_ui_simulator.sh
python3 scripts/build_compat_debs.py \
  dist/com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb \
  --artifact build/audit
python3 scripts/build_bluetooth_deb.py --artifact build/bluetooth --scheme all
python3 tests/test_compat_package.py --artifact build
```

`compat-build.yml` compila ambas bibliotecas, auxiliar Bluetooth y regresión de
navegación/segundo plano en español e inglés con macOS 15. Conserva artefactos
privados temporales; no publica releases ni instala en dispositivos. La base
rh25.3 se necesita localmente y está fijada por SHA-256. Los paquetes de app
salen en `dist/compat4`; los auxiliares en `dist/bluetooth`.

Cada candidata incluye `compatibility.json` y un manifiesto externo con
`runtime_verified: false`. Consultar el informe de esta entrega para el resultado
real de CI y paquete; no confundir estas instrucciones con pruebas ejecutadas.

## Validación física pendiente y recuperación

Antes de declarar estable una combinación: arranque, carga de extensión,
permisos, dos escaneos, SSID/BSSID, menú Wi-Fi y nombres; bloqueo/desbloqueo
solo en red y equipos propios autorizados. Para el transporte Bluetooth:
terminación, Detener, repetición y restauración, más recepción externa cuando
se pretenda acreditar un anuncio. Comprobar que no quedan auxiliares activos.

No instalar otra arquitectura con `--force`. Para recuperar el dispositivo
actual, reinstalar el paquete **dev52 verificado** y su trabajador app31 desde
el mismo bootstrap; no usar la instrucción histórica de recuperar dev18.
No son necesarios resprings ni reinicios generales por rutina.

## Fuentes primarias consultadas el 8 de octubre de 2026

- [Theos: rootless](https://theos.dev/docs/rootless).
- [RootHide: adaptación y firma](https://github.com/roothide/Developer).
- [Dopamine: soporte por chip y versión](https://github.com/opa334/Dopamine).

La existencia de un jailbreak para un iOS no demuestra compatibilidad de las
API privadas de NukeWireless. Rootful describe un esquema de instalación,
no un jailbreak disponible para cualquier dispositivo/iOS.
