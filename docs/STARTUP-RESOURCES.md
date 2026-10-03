# Pantalla de inicio: diagnóstico del 4 de octubre de 2026

## Evidencia

- Base fijada: `rh25.3`; SHA-256 del ejecutable original
  `ea2cf47a8d473d83bbb029e211ec78b85bdb75b863f771c0b49bee4c17807d11`.
- El descriptor Swift de `SplashView` está en el offset `0x11bfbc`;
  su nombre se referencia desde `0x11bfc4` y su accessor desde `0x11bfc8`.
- Su código de dibujo construye dos nombres mediante instrucciones MOVZ/MOVK:

| Offset de archivo | Valor original | Llamada a SwiftUI | Valor nuevo |
| --- | --- | --- | --- |
| `0x2ae10` | llamada a `Color.init(_:bundle:)` | stub `0x1150c8` | llamada al getter `Color.black`, stub `0x11508c` |
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

`startup_resources.py` comprueba los opcodes, registros, desplazamientos y
payload de la imagen antes de sustituir `iconImage` por `NWBootPic`, manteniendo
su longitud de nueve bytes y el discriminador de Swift.String.

La única instrucción BL modificada es la de `0x2ae10`: pasa de la inicialización
por nombre al getter `Color.black` ya importado por el propio ejecutable.
El getter también se llama en `0x17090`, donde su resultado se recoge de `x0`.
Ambas funciones devuelven el valor de SwiftUI.Color en `x0`; el getter no recibe
argumentos, por lo que ignora los valores existentes de nombre/bundle en
`x0/x1/x2`. No se cambia el tamaño del ejecutable, la pila, la estructura Swift
ni el resto del flujo de control. El empaquetador rechaza una base diferente.

El PNG `NWBootPic.png` es una copia exacta del `NukeWirelessIcon.png` de la base.
`Assets.car` permanece idéntico. Se descartó un intento de añadir un color al
catálogo porque la lectura con Apple assetutil no lo validó; no se instaló
ningún paquete de ese intento. La solución final usa el negro nativo y no modifica
el catálogo, ni añade hooks o dependencias.

El build inspecciona el PNG con sips; el empaquetador compara su hash con la base
y el artefacto de CI. El storyboard oscuro para la pantalla de inicio de iOS sigue
incluido. Se retiran las coberturas, hooks de visibilidad de UIWindow, temporizador
de arranque y registro C de dev16/dev17.

La inspección del paquete y el estado de instalación se registran en
`BUILD-RESULTS.md`. La eliminación visual del destello requiere observación en
el iPhone; el simulador de navegación existente no ejecuta este binario original.
