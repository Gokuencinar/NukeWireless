# Nuke Wireless

Nuke Wireless is in development. This repository is public; development builds are not releases.

## Desarrollo actual

**2.0.0~diagnostic6+bundle3: corrección de rutas del instalador rootless.**
Elimina las entradas de directorio con componentes `.` que registraban
`/var/jb/.` y bloqueaban la desinstalación en Dopamine. No distribuir los DEB
rootless anteriores bundle1/bundle2. Se conserva la política sin límites de iOS
del instalador. Compilación y validación de esta revisión en curso; la reparación
del registro antiguo se describe en [recuperación rootless](docs/ROOTLESS-PACKAGE-RECOVERY.md).

**2.0.0~diagnostic6+bundle2: revisión del instalador sin límites de iOS.**
Retira las dependencias `firmware` y `MinimumOSVersion` del DEB unificado de
las tres variantes. Conserva el mínimo compilado real iOS 15.0, los binarios de diagnostic6/Bluetooth diagnostic1 y
las comprobaciones de compatibilidad en ejecución. No acredita funcionamiento
en sistemas nuevos ni corrige el crash externo del catálogo aún sin informe.
Los tres DEB pasaron la inspección local. En Linux pasaron instalación nueva,
migración, propiedad, retirada e instalación sin proveedor `firmware` sin ignorar
dependencias. Esas pruebas dpkg cubrían rootful, no la retirada rootless;
el fallo de rutas rootless se detectó después. Instalación física de bundle2 pendiente.
Véase [empaquetado unificado](docs/UNIFIED-INSTALLER.md).

**2.0.0~diagnostic6+bundle1: compilada, validada e instalada en RootHide.**
Corrige la lectura de identidad del router usada por el bloqueo Wi-Fi: cabecera
Darwin de 92 bytes, alineación de cuatro bytes y coincidencia de IP/interfaz.
El usuario confirmó el corte y recuperación del tráfico en la referencia RootHide.
Pasaron siete suites C locales, 46 comprobaciones UI y cuatro ciclos de segundo
plano por idioma, 15 comprobaciones de los paquetes y las pruebas del instalador.
Fuentes compiladas: `6f30ff2beb9d4109905b44c662de989e88ab2bf0`.
Véase [evidencia y límites del arreglo](docs/WIFI-BLOCK-DIAGNOSTIC6.md).

**Instalador único diagnostic6+bundle1:** reúne app y componente Bluetooth en
un DEB por variante, conservando los permisos. Sustituye el paquete Bluetooth
separado al actualizar. Migración dpkg en Linux e instalación física en
iPhone XS / iOS 16.3.1 / RootHide verificadas; otros entornos pendientes.
Véase [empaquetado unificado](docs/UNIFIED-INSTALLER.md).

**2.0.0~diagnostic5: compilada, validada e instalada en RootHide.**
El cliente bloqueado del punto de acceso muestra una mano roja. La hoja de
acciones organiza nombre/fabricante/estado y direcciones IP/MAC; conserva los
manejadores y abre a altura completa. Pasaron 46 comprobaciones del simulador
por idioma, cuatro ciclos de segundo plano por idioma y 15 de paquete.
Fuentes compiladas: `4f2f7c76ce2c570e882ca0cb6a5e9d5bbaea59ac`. Confirmación visual manual pendiente.
Detalles en [DEVICE-ACTIONS-DIAGNOSTIC5.md](docs/DEVICE-ACTIONS-DIAGNOSTIC5.md).

**2.0.0~diagnostic4: compilada, validada e instalada en la referencia RootHide.**
Obtiene el ticket de direcciones PF antes de añadir cada regla y registra
`system_errno` en el diagnóstico. Diagnostic3 falló con `pf_apply`, reproducido
por SSH con `errno=16`. GitHub Actions pudo ejecutar ambos trabajos tras hacer
público el repositorio por autorización del usuario. Pasaron las pruebas PF,
46 comprobaciones UI por idioma y cuatro ciclos de segundo plano por idioma,
además de las 15 comprobaciones de paquete. Fuentes compiladas: `505986bcd2bb2cb612cad941adff0a181580e6f4`.

El usuario confirmó que el bloqueo y desbloqueo del cliente funcionan en diagnostic4.
El trabajador Bluetooth conserva `2.0.0~diagnostic1`.
Las otras variantes/iOS siguen sin aceptación física.

**2.0.0~diagnostic3:** nuevo listado del punto de acceso sin
duplicados por IP, recarga y hoja de acciones compartida con Wi-Fi. El bloqueo
de clientes utiliza un ayudante PF limitado y comprueba las reglas aplicadas:
en la referencia no existe el `pfctl` que invocaba el código heredado.
Compilación, paquete e instalación aprobados; bloqueo físico fallido. Detalles en
[HOTSPOT-DIAGNOSTIC3.md](docs/HOTSPOT-DIAGNOSTIC3.md).

**NukeWireless Dev · 2.0.0~diagnostic2, compilada, validada e instalada en RootHide:** corrige el retorno desde
Diagnósticos → emisión: Atrás queda disponible, Ayuda pasa a la derecha y volver
a tocar Información regresa a su menú cuando no hay una operación activa.
Conserva Detener y el trabajador `2.0.0~diagnostic1`.

**NukeWireless Dev · 2.0.0~diagnostic1, compilada, empaquetada e instalada en la referencia RootHide:** edición específica para
testers con pruebas independientes y registro persistente/exportable en
**Información → Diagnósticos**. Incluye entorno/instalación, Wi-Fi, BLE,
controlador y emisión con recuperación. Hay variantes RootHide,
rootless y rootful; no declara aceptación en todos los iOS o iPhones.
Véase [guía de diagnóstico y nombres internos](docs/DIAGNOSTIC-EDITION.md).

**Entrega anterior: dev53/app32 y compat4:** la emisión Bluetooth
usa admisión por contrato Skywalk en iOS 15–18 y recuperación del dominio observado
de bluetoothd. Se retira la whitelist XS/16.3.1 de las emisiones; ACT/ACL conserva
su guard. CI, simulador iOS 18.5 y los seis paquetes de tres bootstraps aprobados.
Dev53/app32 se verificó instalada y firmada en la referencia RootHide; los otros iOS,
bootstraps y el adaptador compat4 requieren validación física.
Pruebas de emisión consecutiva, cancelación por CLI y recepción de nueve perfiles Fast Pair aprobadas.
Véanse [port Bluetooth](docs/BLUETOOTH-SKYWALK-PORT.md),
[validación compat4](docs/COMPAT4-VALIDATION.md) y
[compatibilidad y límites actuales](docs/COMPATIBILITY.md).

**Compat3, entrega anterior compilada y empaquetada:** candidatas desde dev52 para iOS 15–18 en
RootHide, Dopamine rootless y rootful. CI y ocho pruebas de los seis paquetes
aprobados; interfaz en simulador iOS 18.5, 33 checks y cuatro ciclos de segundo
plano por idioma. Las nuevas combinaciones siguen sin validación física y la
emisión conservaba el guard iPhone XS / iOS 16.3.1. Dev52 era la versión instalada.
Véanse [compatibilidad y límites](docs/COMPATIBILITY.md) y
[validación compat3](docs/COMPAT3-VALIDATION.md).

**Dev52 instalado / app31 sin cambios:** logos del selector Bluetooth alineados
por columnas y créditos solo GokuEn. Conserva el Samsung ampliado y las acciones
Wi-Fi de dev51. Compilación, simulador (33 comprobaciones por idioma), siete
pruebas de paquete, instalación y firma verificadas; el usuario confirma la UI
y las acciones Wi-Fi el 8 de octubre de 2026.
Véase [alineación y créditos](docs/BRAND-ALIGNMENT-CREDITS-DEV52.md).

**Dev51 instalado / trabajador app31 sin cambios:** tocar un resultado de Equipos
abre las acciones Wi-Fi de bloquear/desbloquear, cambiar o quitar el nombre
personalizado y copiar IP, manteniendo la búsqueda. Logo Samsung ampliado.
Compilación, simulador (33 checks por idioma), siete pruebas de paquete,
instalación y firma verificadas; estas acciones fueron confirmadas después en dev52.
Véase [acciones desde la búsqueda](docs/WIFI-SEARCH-ACTIONS-DEV51.md).

**Dev50 instalado / trabajador app31 sin cambios:** las emisiones se concentran en
Dispositivos aleatorios: generar seis modelos, emitir uno desde su tarjeta o emitir todos.
Se retiran los botones repetidos del menú y se añaden logos de las plataformas,
con colores dinámicos y selector adaptable. Escáner BLE, Detener, catálogo abierto
y final silencioso conservados. Compilación, simulador, siete pruebas de paquete,
instalación y firma verificadas; el usuario confirma que todo funciona correctamente.
Véase [Bluetooth simplificado](docs/BLUETOOTH-SIMPLIFIED-DEV50.md).

**Dev49 instalado / trabajador app31:** Google/Fast Pair pasa de seis a nueve perfiles disponibles;
Generar elige seis modelos entre 84 selecciones, sin repetir la anterior.
Añade Sony WF-1000XM4, Sony WH-1000XM5 y Jabra Elite 5.
Compilación, simulador, paquete, instalación y recepción de los nueve perfiles
verificados; regeneración manual en el iPhone pendiente. Véase [aleatoriedad Google](docs/BLUETOOTH-GOOGLE-RANDOM-DEV49.md).

**Dev48 instalado / trabajador app30:** el catálogo genera seis modelos con perfiles disponibles
y añade doce entradas entre Apple, Fast Pair, Microsoft y Samsung. La restauración verifica que la interfaz HCI
está publicada antes de liberar la operación; la espera de disponibilidad está acotada,
sin repetir anuncios. Compilación, paquete, instalación y recepción de 26 identidades
verificados; cinco emisiones consecutivas, cancelación temprana y emisión posterior
comprobadas por SSH. El usuario confirma que la repetición desde el catálogo funciona,
con seis tarjetas disponibles, Detener y final silencioso. Véase
[emisiones consecutivas](docs/BLUETOOTH-REPEAT-DEV48.md).

**Dev47 instalado / trabajador app28:** la barra de cuatro opciones se separa del contenido
de la barra nativa para evitar iconos y textos superpuestos al volver del segundo plano.
Mantiene los tres hosts y el delegado SwiftUI, la pestaña y la navegación Bluetooth.
Compilación, 26 checks por idioma con cuatro ciclos reales de segundo plano,
paquete e instalación verificados; aceptación manual pendiente. Véase [restauración de pestañas](docs/MAIN-TABS-FOREGROUND-DEV47.md).

**Dev46 instalado / trabajador app28:** los modelos generados con perfil disponible
permiten emisión individual de 10 s al tocar su tarjeta; Emitir conserva la selección completa.
Ambas opciones mantienen el catálogo y Detener accesible, sin resultados
de éxito. Compilación, simulador (18 comprobaciones por idioma), siete checks
de paquete e instalación verificados. El usuario confirma emisión individual,
catálogo abierto, Detener y final sin resultado. Radio y trabajador sin cambios.
Véase [emisión individual](docs/BLUETOOTH-INDIVIDUAL-DEV46.md).

**Dev45 instalado / trabajador app28:** Emitir mantiene el catálogo, con Detener en la
misma pantalla y la barra superior. Los resultados correctos quedan ocultos;
los fallos y restauraciones incompletas siguen visibles. Menos texto repetido,
ayuda accesible y sin desplazamientos automáticos. Compilación, simulador
(dieciséis comprobaciones por idioma), siete checks de paquete e instalación
verificados; aceptación manual pendiente. Trabajador y perfiles de radio sin cambios.
Véase [usabilidad Bluetooth](docs/BLUETOOTH-USABILITY-DEV45.md).

**Dev44 instalado / trabajador app28:** el catálogo añade Samsung (Galaxy Buds, Live,
Buds2 y Buds2 Pro, con variantes de color), muestra la identidad del protocolo
y conserva una dirección estable por modelo entre generaciones. Corrige IDs
Google incorrectos de dev43 y añade Pixel Buds Pro. Emisión acotada con Detener;
compilación, simulador (doce comprobaciones por idioma), paquete e instalación
verificados. El usuario confirma que Windows muestra Surface Headphones;
iPhone/iPad y Android siguen pendientes de aceptación específica. Véase [identidad de modelos](docs/BLUETOOTH-CATALOG-IDENTITY-DEV44.md).

**Dev43 instalado / trabajador app27:** el catálogo añade **Emitir N de 3 · 10 s**,
usando los perfiles disponibles de los modelos seleccionados y regresando al
panel Bluetooth para conservar Detener. Los modelos sin correspondencia
contrastada se indican y no se sustituyen. Requiere el nuevo trabajador app27;
compilación, simulador (once comprobaciones por idioma), paquete e instalación
verificados. El usuario informa que la emisión no muestra error; Detener,
restauración y reconocimiento en el receptor siguen sin aceptación específica. Véase [emisión del catálogo](docs/BLUETOOTH-CATALOG-EMISSION-DEV43.md).

**Dev42 instalado / trabajador app26:** Bluetooth añade Catálogo aleatorio,
con Apple, Google y Microsoft. Cada marca tiene seis modelos; se generan tres
distintos por pulsación, con una combinación diferente de la anterior y nuevas
identidades locales NWLab. Es una simulación visual dentro de la app. Compilación,
simulador y paquete verificados; el usuario confirma el catálogo y la regeneración
con las tres marcas en el iPhone. Véase [catálogo local](docs/BLUETOOTH-CATALOG-DEV42.md).

**Dev41 instalado / trabajador app26:** Bluetooth organiza sus acciones en
Exploración, Windows, Apple y Android. Cada plataforma muestra los modos de uno
y tres dispositivos, sus modelos y la duración de 10 s. Añade ayuda en la barra
superior, acciones desactivadas atenuadas y contraste corregido al cambiar al
modo oscuro. Compilación, simulador y paquete verificados; falta confirmar la
apertura manual en el iPhone. Véase [interfaz Bluetooth](docs/BLUETOOTH-UI-DEV41.md).

**Dev40 instalado / trabajador app26:** barra principal con Wi-Fi, Punto de acceso,
Bluetooth e Información. El ping se retira de la interfaz. Bluetooth conserva
escáner BLE, capacidades y los seis perfiles de anuncios, con Detener. Wi-Fi
añade un único reintento automático tras un resultado vacío o fallido, esperando
una interfaz válida y la finalización de la cola anterior. El aislamiento de
clientes en algunas redes universitarias puede impedir descubrir otros equipos;
no se ha comprobado la configuración de la red eduroam del usuario. Compilación,
regresiones del simulador y paquete verificados; falta confirmar la apertura y
el escaneo en frío en el iPhone. Véase
[pestaña Bluetooth y recuperación Wi-Fi](docs/BLUETOOTH-TAB-AND-WIFI-RECOVERY.md)
para los detalles y el alcance de la validación.

### Historial de candidatas

**Nueva candidata dev25 / app10:** en **Información → Bluetooth** la cantidad
y el intervalo se escriben en campos numéricos, con teclado y botón **Hecho**.
Intervalo en milisegundos enteros (1000–5000 ms), incluido por ejemplo 1500 ms;
de 1 a 20 pings y `cantidad × intervalo <= 20000 ms`. Una combinación inválida
muestra un aviso sin comenzar el diagnóstico. Se migran los ajustes anteriores
en segundos. Confirmación y resultados muestran ms. Candidata sin instalación
ni prueba funcional en el dispositivo.

**Candidata anterior dev24 / app9:** en **Información → Bluetooth** permite elegir
el número de pings (1–20) y el intervalo (1–5 segundos). La combinación se limita
a una ventana de 20 segundos; al aumentar el intervalo se ajusta el máximo de
pings. Preferencias persistentes, confirmación con las opciones elegidas y
resultados con número solicitado e intervalo. Estas opciones todavía no están
comprobadas en el dispositivo; la instalación confirmada sigue siendo dev23/app8.

**Última candidata instalada:** `1.0.25+rh25.5~dev23`, con **Información → Bluetooth**
para cinco pings clásicos, cancelación y resultados. El módulo separado
`NukeWireless Bluetooth Bridge` (`0.0.3~app8`) gestiona permisos y recuperación
del servicio. Ambos paquetes están confirmados por `dpkg` en el iPhone.
El usuario confirmó cinco respuestas desde el botón en dev23/app8. El registro
del helper confirma el llamante mobile, los cinco ecos, el cierre de conexión
y la restauración automática. La causa del error previo era exigir «ocupado»
en una comprobación donde la app abría correctamente el canal. Dev23 guarda
los resultados y los muestra al terminar. La copia de dev19 se conserva para
reversión; los binarios originales de red y rutas mantienen sus hashes.

**Bluetooth nativo en investigación:** se ha compilado e instalado una biblioteca
independiente de inspección en el iPhone XS con iOS 16.3.1 y Dopamine RootHide.
**L2ping comprobado por SSH:** cinco ecos reales respondidos por los auriculares
del usuario mediante HCI/ACL Skywalk, con cierre de conexión y restauración del
servicio Bluetooth. Dev22 incorpora la interfaz y un runner autónomo, cuyo caso
de destino apagado y recuperación tras cancelación/SIGKILL se comprobaron por
SSH. El supervisor `app5` también completó cinco ecos reales con los auriculares
encendidos y restauró el servicio automáticamente. El botón de dev23/app8 también completó cinco respuestas y restauración
automática, confirmadas por el usuario y el registro del helper. Solo se
comprobó iPhone XS / iOS 16.3.1 / Dopamine RootHide. Véase
[evidencias, fuentes y límites](docs/BLUETOOTH-L2PING.md).

**Nueva interfaz candidata dev19 / compat2:** panel **Equipos** desde la lupa de Wi-Fi,
con búsqueda, filtros y ordenación de los resultados existentes. **Información →
Color de acento** permite elegir cian, violeta o verde al momento. Los controles
de escaneo y bloqueo permanecen en la lista original. Véase [uso, alcance y
límites de comprobación](docs/DEVICE-BROWSER.md).

**Port iOS 15–18 en desarrollo:** se preparan variantes separadas RootHide/Relaxin, Dopamine rootless y rootful. Son candidatas experimentales; no hay dispositivos con iOS 15, 17 o 18 disponibles para confirmarlas. Véase [compatibilidad, procedencia y construcción](docs/COMPATIBILITY.md).

El usuario confirmó el resto de dev14, pero la pantalla azul de carga continuaba. Apartar su caché de SplashBoard tampoco resolvió el problema.

`dev13` fue confirmada por el usuario como funcional, incluido el ajuste de Actualizar.

**Cambio de idioma comprobado:** `1.0.25+rh25.5~dev11`. Añade **Info → Idioma** para elegir español o inglés. La selección se guarda en la app y se aplica al cerrarla desde la confirmación y volver a abrirla. No permite cerrar para cambiar el idioma mientras hay un escaneo o bloqueos activos. Incluye catálogos para la extensión, las vistas SwiftUI originales y los controles UIKit; los nombres reales de redes/equipos y sus direcciones se conservan.

Las capturas del simulador confirman las pestañas, los textos de WiFi y el contenido de Info en ambos idiomas. La prueba conserva los hosts SwiftUI y verifica traducciones de alertas, botones y campos. El núcleo original se conserva como binario: estas pruebas no equivalen a comprobar visualmente cada ruta de la aplicación en el iPhone. `dev10` es la versión anterior confirmada por el usuario: Info abre y el título «Harpy» ya no aparece.

`dev9` quedó retirada de la release pública: reemplazar el controlador de pestaña provocó una conversión de tipo fallida en SwiftUI al entrar en Info, confirmada en el registro de cierre del dispositivo.

**Última versión comprobada en el iPhone:** `1.0.25+rh25.5~dev8` (iOS 16.3.1, Dopamine RootHide). Arranca y termina el escaneo inicial. «Bloquear todos» enlaza el botón real dentro del panel heredado y encuentra la puerta de enlace mediante SystemConfiguration cuando la propiedad antigua está vacía. Una prueba diagnóstica contó 11 equipos aptos y abrió la confirmación. El usuario confirmó en el iPhone que «Bloquear todos» y «Desbloquear todos» funcionan. La observación por SSH no permitió medir por separado el efecto sobre cada equipo de la red; después de la prueba no quedaron procesos `arpoison` activos.

`dev6` resolvió el bloqueo de arranque, pero Actualizar mostraba «The scanner is not ready». RootHide carga `systemhook` como imagen dyld 0; el código buscaba ahí la función Swift del ejecutable. `dev7` fue un parche binario para ese dispositivo. Durante la etapa pública del repositorio, GitHub Actions compiló la solución fuente que busca el ejecutable por nombre; `dev8` contiene esa compilación y la corrección de los controles masivos.

La rama `audit-rh25.5` conserva el trabajo de desarrollo. Las candidatas se distribuyen como prereleases; no se publican en el repositorio de paquetes. Los cambios siguientes forman parte de la candidata:

- Info usa una tabla con alturas calculadas, sin banner ni superposiciones de altura fija. Incluye créditos, avatar, enlaces, red actual y copia al portapapeles.
- Actualizar y deslizar ejecutan la renovación nativa de la lista; el puente observa sus callbacks y recupera el estado tras errores.
- Bloquear todos utiliza los métodos del bloqueo/desbloqueo individual. Excluye el iPhone, la puerta de enlace y direcciones inválidas; contabiliza fallos parciales.
- Ajustes avanzados mantiene el intervalo entre paquetes y permite actualizar/restaurar la tabla de fabricantes. No incluye el antiguo botón para repetir la introducción.
- Info incluye el selector de español e inglés; inicialmente usa el idioma del sistema y después conserva la elección del usuario.

Consulta [el informe de auditoría](docs/AUDIT-rh25.5.md) para conocer las causas, pruebas y límites de validación.

## Arquitectura y compatibilidad

Este proyecto contiene una extensión y herramientas de adaptación; **no contiene el código Swift original completo**. Se conservan las dos bibliotecas de rutas y los auxiliares del paquete base. En el ejecutable original solo se sustituyen dos textos visibles manteniendo exactamente su longitud; dev18 también sustituye la llamada de color y el nombre de imagen de SplashView con guardas del binario fijado.

Las rutas `HarpyReloaded.app`, las clases Swift `_TtC13HarpyReloaded…`, el bundle ID `me.midnightchips.harpy-reloaded` y las preferencias existentes son identificadores de compatibilidad. No deben renombrarse. `src/NWBootstrapPathsHistorical.c`, `scripts/build_deb.py` y el parche de Aegis son material histórico: no se recompilan ni aplican al generar esta versión.

Versión instalada comprobada: iOS 16.3.1 con Dopamine RootHide. Las variantes nuevas apuntan a iOS 15–18 y siguen pendientes de validación funcional. SSID/BSSID se consultan mediante MobileWiFi sin solicitar ubicación; el acceso efectivo depende del dispositivo.

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
