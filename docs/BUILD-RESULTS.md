# Resultado de la compilación de desarrollo

## Candidata dev11 (30 de septiembre de 2026)

- Compilación y pruebas de idioma/navegación correctas en [Actions](https://github.com/Gokuencinar/NukeWireless/actions/runs/36741754443), fuente `9a14a7f`. Se revisaron las cuatro capturas de WiFi e Info en español e inglés.
- Selector persistente Info → Idioma. Actualiza las preferencias de idioma de la app; el usuario confirma cerrar y la vuelve a abrir. El cierre está condicionado a no tener escaneos ni bloqueos activos.
- Catálogos para la extensión, textos SwiftUI originales y controles UIKit (alertas, botones, títulos y campos). Los datos reales de redes/equipos conservan su contenido. Se protege la carga de recursos frente a una entrada recursiva en la traducción.
- Siete pruebas del paquete correctas. SHA-256: `117dc4e785e4dc334293f4b5b0e2f5fa0ae43e1eacf7a0e24421dbd0118363ad`.
- Instalación SSH correcta: `dpkg-query` muestra `1.0.25+rh25.5~dev11`. Se conserva dev10 en el iPhone como respaldo. El usuario confirmó que el cambio de idioma funciona perfectamente. La fixture del simulador no ejecuta el binario original.

## Candidata dev10 (30 de septiembre de 2026)

- Compilación y prueba UIKit/SwiftUI correctas en [Actions](https://github.com/Gokuencinar/NukeWireless/actions/runs/36736016724). La prueba cambia WiFi → Info → WiFi, conserva la identidad de los tres controladores, verifica el contenido opaco de Info, sus tres filas de enlaces/ajustes y la sustitución del título en UINavigationItem. Resultado: `[0, 0, 0]`.
- Siete pruebas del paquete superadas; instalado por SSH como `1.0.25+rh25.5~dev10`.
- SHA-256 del `.deb`: `6274311722abd8b315e8d8de4828c492e257b05f015894c2a6f666ec15d6ff03`.
- Corrige el cierre de Info conservando el host SwiftUI original. La pantalla nueva se monta de forma síncrona en `viewWillAppear`, cubre el host y oculta sus subviews antiguas. El título de navegación WiFi se normaliza mediante `UINavigationItem.setTitle:` y también se revisan los items existentes.
- El código de comprobación de interfaz solo se compila en la fixture del simulador; no forma parte de la biblioteca para el iPhone. El usuario confirmó que Info ya no cierra la app y que el título «Harpy» ha desaparecido. SSH también encontró el proceso activo y ningún nuevo reporte de cierre tras instalar dev10. El usuario no ha confirmado por separado el destello del banner ni el contenido de cada fila de Info.

## Candidata dev9 (retirada el 30 de septiembre de 2026)

- Compilación iOS arm64 correcta en [Actions](https://github.com/Gokuencinar/NukeWireless/actions/runs/36732810306); siete pruebas de estructura, textos, firma y procedencia del paquete superadas.
- Paquete: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev9_iphoneos-arm64e.deb`; SHA-256: `d1a76a99e2064ff8054a574e483b2d1359304f96174cec331226f4f074b88a84`.
- Nombre visible, metadatos y mensajes de bienvenida/licencia: NukeWireless. Los identificadores de clases Swift, rutas y ejecutable heredados se conservan porque forman parte de la ABI del binario original.
- Info sustituye el tercer controlador de pestaña en `viewWillAppear`, antes de dibujar la pantalla antigua; elimina la capa superpuesta que se añadía después de `viewDidAppear`. Se retiran la fila, el controlador y las traducciones de Acknowledgements; el archivo de licencias sigue incluido en el paquete.
- Tras instalarla por SSH, el usuario informó del cierre al entrar en Info y del título «Harpy» en WiFi. El crash `HarpyReloaded-2026-09-30-170820.ips` registra `swift_dynamicCastClassUnconditional` dentro de SwiftUI. Se restauró temporalmente dev8 y se convirtió la release dev9 en borrador.

## Candidata dev8 (instalada en el iPhone)

- Versión: `1.0.25+rh25.5~dev8`; compilación iOS arm64 desde fuente en [Actions](https://github.com/Gokuencinar/NukeWireless/actions/runs/36467454122), correcta.
- Se enlaza el botón ancho que está dentro del panel `UIView` con etiqueta `90122`; se conserva el botón Nombres y la geometría del panel. SystemConfiguration proporciona la puerta de enlace cuando `MCCommands.gatewayIP` devuelve cero.
- Paquete local: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev8_iphoneos-arm64e.deb`; SHA-256: `746a3f3df420a2eb7c9f955f06a99591d3f5a6c73c02619e98296ccb5d5006ab`.
- Siete pruebas del paquete y comprobación de ABI nativa: correctas.
- Prueba diagnóstica con la misma lógica: botón presente, enlazado y habilitado; el toque abrió la confirmación para 11 objetivos y un `UIAlertController`. Se cerró sin confirmar, de modo que ningún equipo fue bloqueado en esa prueba.
- Instalación final por SSH: `dpkg-query` muestra `dev8`; la app cargó la extensión y completó el escaneo inicial con 13 filas. La biblioteca instalada contiene la marca `dev8` y no contiene el código diagnóstico.
- Comprobación de uso: el usuario confirmó en el iPhone que Bloquear todos y Desbloquear todos funcionan. Tras la prueba, SSH no encontró procesos `arpoison` activos. El registro remoto no permitió verificar de forma independiente el efecto en cada equipo. Se retiró el módulo temporal de diagnóstico y se restauró la biblioteca normal de `dev8`.
- No se creó release ni se modificó `main` o el repositorio público de paquetes.

## Candidata dev7 (sustituida por dev8)

- Versión: `1.0.25+rh25.5~dev7`.
- RootHide carga `systemhook` como imagen dyld 0. Un parche de una instrucción en la biblioteca `dev6` selecciona la imagen 1 y conserva la comprobación del prólogo de la función Swift. También cambia los textos de versión sin alterar longitudes.
- Reproducción: `python scripts/build_dev7_patch.py`; tres pruebas en `tests/test_dev7_patch.py`, correctas. Entrada y biblioteca base fijadas por SHA-256.
- Paquete local: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev7_iphoneos-arm64e.deb`.
- SHA-256: `708e7a7cdbca4610b3b7fd5c8c8bf39ae1115602d5e6537e3a5c6bc9987cf184`.
- Diagnóstico en dispositivo con el mismo cambio de instrucción: escaneo 1 completo con 12 filas, botón Actualizar activado automáticamente y escaneo 2 completo con 13 filas; no hubo cierre. La biblioteca final elimina la pulsación automática y sus registros.
- Instalación final por SSH: `dpkg -i` correcto; `dpkg-query` muestra `dev7`; la biblioteca instalada contiene la instrucción y marca `dev7` esperadas, sin diagnóstico. Tras abrir la app se registró la carga de la extensión y un escaneo inicial completo con 14 filas.
- GitHub Actions no compiló la fuente nueva: el run privado `36462904448` falló antes de asignar runner por pagos recientes fallidos o límite de gasto. `dev7` es un parche binario reproducible, no una compilación de la fuente actual. La solución fuente busca el ejecutable por nombre y queda pendiente de compilación macOS.
- No se creó release ni se modificó `main` o el repositorio público de paquetes. Bloquear todos e Info no tienen aún validación completa de interacción.

## Candidata dev6 (sustituida por dev7)

- Versión: `1.0.25+rh25.5~dev6`.
- El escáner nativo conserva el hilo de inicio de la app; sus callbacks actualizan el estado y las filas del puente. La capa de interfaz deja de interceptar globalmente `viewDidLayoutSubviews` y `setContentInset:`. Solo reasigna la geometría, los títulos y los insets cuando cambian.
- CI privado: https://github.com/Gokuencinar/NukeWireless/actions/runs/36460316748 — correcto; pruebas C y Foundation y compilación iOS arm64.
- Paquete local: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev6_iphoneos-arm64e.deb`.
- SHA-256: `f3aac3eeaaf5c22653dc1d5e0728d739f93567551087290639099373220818ff`.
- Siete pruebas de paquete y prueba de ABI: correctas.
- Se instaló y el usuario confirmó que veía la interfaz y las pestañas. El escaneo inicial terminaba, pero Actualizar mostraba «The scanner is not ready» porque tomaba el índice dyld 0. `dev7` corrige esa condición. No hay release ni cambio en `main`.

## Candidata dev5 (retirada)

- Versión: `1.0.25+rh25.5~dev5`.
- Corrección concreta: el control con etiqueta `90122` es el propio botón «Bloquear todos» en la biblioteca conservada, no un panel que contenga otro botón. Ahora se enlaza directamente con la acción masiva nueva.
- Info: avatar de 40 puntos y créditos en una fila; al actualizar los datos de red se recarga solo su sección y se conserva la posición del scroll. Se retiró un hook global de `UILabel` que ya no tenía consumidores.
- CI privado: https://github.com/Gokuencinar/NukeWireless/actions/runs/36432165683 — correcto; compilación iOS arm64, pruebas C y Foundation.
- Paquete local: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev5_iphoneos-arm64e.deb`.
- SHA-256: `609381b36361bd57b9b4783029a4e9ec7ccd50937afa303fab4a09020845e09a`.
- Siete pruebas de paquete y prueba de ABI: correctas.
- Instalación SSH: `dpkg -i` con código 0; el usuario confirmó que queda en la pantalla azul. La traza del arranque confirma la carga de la extensión, instalación del hook y entrada en `scannerStarted` con delegado Wi-Fi, pero nunca se ejecuta el bloque de creación de sesión diferido al hilo principal. Se restauró `rh25.3` mediante `dpkg -i` y se verificó su versión y biblioteca instalada. **No instalar dev5.**
- Sin release ni modificación de `main`; el paquete base `rh25.3` vuelve a estar instalado.

## Candidata dev4 (sin validar en el iPhone)

- Versión: `1.0.25+rh25.5~dev4`.
- Cambio respecto a `dev3`: el escaneo inicial deja de consultar MobileWiFi de forma síncrona en el hilo principal. Es una hipótesis para el bloqueo de arranque, todavía sin confirmación en el dispositivo.
- Código compilado: `56bf8f2` en la rama privada `audit-rh25.5`.
- CI privado: https://github.com/Gokuencinar/NukeWireless/actions/runs/36430785473 — correcto; pruebas C y Foundation y compilación iOS arm64 con avisos tratados como errores.
- Paquete local: `dist/com.gokuencinar.nukewireless_1.0.25+rh25.5~dev4_iphoneos-arm64e.deb`.
- SHA-256: `c4160214f5fbc45afea2e94412af5057e1f6e94e24d3055f0fb2f90ed141e77d`.
- Siete pruebas del paquete y prueba de ABI: correctas.
- No se instaló `dev4`. El iPhone permanece con `rh25.3`, confirmado funcional. No se creó release ni se modificó `main`.

## Candidata dev3 (retirada)

**Retirada:** la deb `dev3` supera compilación y pruebas estructurales, pero la app se queda en la pantalla azul inicial. Se reinstaló `rh25.3`, que el usuario confirmó funcional. El archivo `dev3` se retiró de la carpeta de entrega y no debe instalarse.

- Versión: `1.0.25+rh25.5~dev3`.
- Código compilado: `a14ca88` en `audit-rh25.5`.
- CI privado: https://github.com/Gokuencinar/NukeWireless/actions/runs/36427121491 — `success`; pruebas C y Foundation y compilación iOS arm64 sin avisos.
- Paquete: `com.gokuencinar.nukewireless_1.0.25+rh25.5~dev3_iphoneos-arm64e.deb`.
- SHA-256: `3c450d9651b3bbead6b90cb51c599a671c990cea9084aba0eabb63536fbbca5e`.
- Siete pruebas del paquete y prueba de ABI: correctas.
- Instalación SSH en iOS 16.3.1/Dopamine RootHide: `dpkg -i` terminó con código 0 y `Status: install ok installed`; el arranque no avanzó de la pantalla inicial.
- Registro del arranque: `extension dev3 loaded` y `Wi-Fi refresh ready`; recurso `CreditsAvatar.png` presente.
- Los seis campos de red estuvieron disponibles en una ejecución diagnóstica anterior. Ninguna función de `dev3` queda validada para uso normal; consultar `AUDIT-rh25.5.md`.
- Sin release, tag, modificación de `main` ni publicación en el repositorio público de paquetes.

La candidata `dev1` publicada antes como archivo local tenía un fallo de instalación y queda retirada. `dev2` fue solo una etapa diagnóstica. Ninguna se publicó como release.
