# Pantalla de inicio: diagnóstico del 4 de octubre de 2026

## Evidencia

- Base fijada: `rh25.3`; SHA-256 del ejecutable original
  `ea2cf47a8d473d83bbb029e211ec78b85bdb75b863f771c0b49bee4c17807d11`.
- El descriptor Swift de `SplashView` está en el offset `0x11bfbc`;
  su nombre se referencia desde `0x11bfc4` y su accessor desde `0x11bfc8`.
- Su código de dibujo construye dos nombres mediante instrucciones MOVZ/MOVK:

| Offset de archivo | Valor original | Llamada a SwiftUI | Valor nuevo |
| --- | --- | --- | --- |
| `0x2adf0` | `AccentColor`, 11 bytes | `Color.init(_:bundle:)` en `0x2ae10` | `NWBootColor`, 11 bytes |
| `0x2ae1c` | `iconImage`, 9 bytes | `Image.init(_:bundle:)` en `0x2ae38` | `NWBootPic`, 9 bytes |

- Ambas llamadas pasan `nil` como bundle. El modo de imagen posterior carga
  `Image.TemplateRenderingMode.original`; conserva los colores del nuevo PNG.
- `Assets.car` original contiene `AccentColor` con componentes RGBA
  `(0.1410000026, 0.4309999943, 0.9139999747, 1.0)`, coincidentes con el azul
  mostrado. También contiene la imagen lógica `iconImage`.
- Los registros de dev16/dev17 muestran que la extensión sí colocaba su vista
  de cobertura en un `UIHostingController<ModifiedContent<AnyView,...>>` y la
  retiraba al detectar las pestañas. El usuario seguía viendo el destello.
  Estos registros no prueban el orden de composición de todos los fotogramas.
- Cambiar el storyboard y apartar las cachés del bundle (incluida la ruta real
  de RootHide) tampoco eliminó el destello según el usuario.

## Corrección de dev18

`startup_resources.py` comprueba cada opcode, registro, desplazamiento y payload
original antes de sustituir los inmediatos que forman esos dos nombres. Conserva
las longitudes y discriminadores de Swift.String, el tamaño del ejecutable, las
llamadas, el flujo de control y el código del escáner. No modifica estructuras Swift
ni interfiere en la creación de las pestañas.

El PNG `NWBootPic.png` es una copia exacta del `NukeWirelessIcon.png` de la base.
Se añade `NWBootColor` con RGBA `(0.01, 0.02, 0.075, 1)` al catálogo original:
clona el formato de su color existente, asigna un identificador libre y actualiza
los dos árboles BOM y el contador de renditions. Todos los recursos originales,
incluido el color de acento utilizado por otras pantallas, se conservan.

El build inspecciona el catálogo con Apple `assetutil`; el empaquetador comprueba
los hashes de esos recursos frente al artefacto de CI. El storyboard oscuro para
la pantalla de inicio de iOS sigue incluido. Se retiran las coberturas, hooks de
visibilidad de UIWindow, temporizador de arranque y registro C de dev16/dev17.

La inspección del paquete y el estado de instalación se registran en
`BUILD-RESULTS.md`. La eliminación visual del destello requiere observación en
el iPhone; el simulador de navegación existente no ejecuta este binario original.
