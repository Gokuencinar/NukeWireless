# NukeWireless Dev · 2.0.0~diagnostic6

Edición de desarrollo para recoger evidencia de compatibilidad en iOS 15–18.
Se generan paquetes separados para RootHide, rootless y rootful. Compartir una
compilación no constituye una verificación en todos esos entornos.

## Uso por los testers

1. Cerrar NukeWireless e instalar **un único DEB** `2.0.0~diagnostic6+bundle2`
   de la variante correcta: RootHide, Dopamine/rootless o rootful. Incluye la app
   diagnostic6 y el trabajador Bluetooth diagnostic1. Diagnostic6 corrige la
   lectura de identidad del router; el usuario confirmó bloqueo y desbloqueo
   en el iPhone XS / iOS 16.3.1 / RootHide.
   Esta edición actualiza los paquetes existentes; no instala otra app en paralelo.
   Bundle2 retira los límites de iOS del instalador y del Info.plist; conserva el
   mínimo compilado iOS 15.0 y los controles en ejecución. No acredita compatibilidad
   fuera de los entornos probados, ni apertura de la app en sistemas anteriores.
   El gestor puede proponer retirar el paquete Bluetooth separado, sustituido por
   el integrado. No instalar ambos formatos a la vez. Véase
   [empaquetado unificado y recuperación](UNIFIED-INSTALLER.md).
2. Abrir **Información → Diagnósticos → Comprobar entorno e instalación**.
3. Ejecutar por separado las pruebas Wi-Fi y BLE. BLE abre el escáner habitual;
   pulsar su botón de explorar y esperar o detenerlo. Un resultado vacío puede
   deberse al entorno de red o a la ausencia de anuncios alcanzables.
4. Para **Probar controlador Bluetooth**, apagar Bluetooth en **Ajustes**. La
   prueba exclusiva hace las lecturas locales ya existentes, conserva Detener
   y restaura el servicio. No emite anuncios ni crea conexiones.
5. Para probar emisión, abrir su opción, entrar al catálogo y emitir uno o todos.
   Mantener el receptor preparado; añadir después su modelo, versión de sistema,
   modelo emitido y resultado mediante **Añadir observación del receptor**.
   Atrás vuelve a Diagnósticos; tocar de nuevo Información vuelve a su menú.
   Durante una operación activa se mantiene Detener y se bloquea ese retorno.
6. Volver y pulsar **Exportar informe JSON**. El usuario elige el destino en la
   hoja de compartir; la app no sube archivos ni contacta a nadie automáticamente.

Si una prueba falla, anotar el error y exportar el informe antes de reintentar,
cerrar la app o cambiar el estado de Bluetooth.

El registro se conserva al volver a abrir la app. Los archivos están en su
directorio Documents/NukeWireless-Diagnostics, accesible mediante Archivos. Se
conservan `latest.json` y los cinco últimos informes exportados. Si no puede
abrirse la app, recuperar ese directorio por el acceso al contenedor del mismo
dispositivo; no hay una ruta absoluta universal entre los bootstraps. Un fallo
anterior a la carga de la extensión requiere además el informe de crash del
proceso, revisado antes de compartirlo. No se recopilan crashes de otras apps.

## Evidencia del informe

- Entorno: modelo de iPhone, iOS/build, UID, versión/esquema/commit del paquete,
  UUID de imágenes Mach-O del producto y presencia de interfaces sin direcciones.
- Instalación Bluetooth: versión del trabajador, propietario/permisos del runner,
  biblioteca, símbolos Skywalk, firmas concretas de BluetoothManager, descriptor
  HCI y estado observado de los dos dominios permitidos de bluetoothd.
- Wi-Fi: hooks, estado, generación, cola, preparación IPv4/subred, filas, reintentos
  y estado nativo final. No cambia el alcance ni la política de recuperación.
- BLE: autorización, estado del manager, solicitud/inicio observado, callbacks y
  número de dispositivos; no exporta nombres, MAC o UUID de periféricos.
- Controlador/emisión: error y etapa, respuestas locales, capacidades, proceso,
  cancelación y comprobaciones de limpieza/restauración. El éxito permanece
  discreto en la interfaz habitual y queda disponible en el registro.

Estados: `running`, `captured`, `passed`, `empty`, `blocked`, `failed`, `partial`,
`cancelled`, `not_run`, `interrupted`, `user_report`. `captured` es una observación,
no una aceptación. `passed` se refiere únicamente a esa prueba local. Al abrir
una nueva sesión, una operación pendiente se registra como `interrupted` con
causa desconocida; no se declara un crash ni una restauración por inferencia.
Recepción de radio y avisos del sistema requieren observación externa separada.

El trabajador incorpora `nwbt-run --diagnostics`, una consulta de solo lectura
con el mismo control de procedencia/privilegios. No construye BluetoothManager,
abre canales, envía HCI, retira servicios ni ejecuta comandos arbitrarios.

Registro limitado a 64 eventos, detalles acotados, JSON menor de 1 MiB y escritura
atómica. Se omiten claves sensibles y se redactan MAC, IPv4, IPv6, UUID de
periféricos y rutas privadas. Los UUID Mach-O del producto se conservan para
identificar la compilación. Las notas libres requieren revisión humana: no se
pueden reconocer automáticamente todos los nombres personales o secretos.
**Borrar registro** conserva los informes exportados y el historial de equipos.

## Nombres heredados

La marca visible y la versión son NukeWireless Dev. Las constantes de enlace con
el ejecutable Swift original están centralizadas en `src/NWLegacyABI.h`.
Su bundle ID/firma, ejecutable, directorio de app, clases Swift, rutas de helpers
y claves de preferencias se conservan porque no están disponibles las fuentes
del ejecutable original. Renombrarlas literalmente rompe hooks, permisos BLE,
admisión del trabajador o datos del usuario.

El adaptador actual se llama `src/compat/NWBootstrapPaths.c`; la fuente retirada
se llama `src/NWBootstrapPathsHistorical.c`. Las referencias del empaquetador a
archivos/paquetes originales identifican entradas fijadas por hash o eliminan
componentes antiguos. Los binarios baseline/prebuilt, fixtures de ABI, historial,
licencias y documentación de procedencia conservan esos nombres deliberadamente.
No se han editado binarios arbitrariamente ni falseado su procedencia.

## Punto de acceso y acciones en diagnostic3

El punto de acceso agrupa equipos por IP y ofrece recarga y arrastre. Sus
acciones y las del buscador Wi-Fi se presentan en una hoja con iconos. Los
nombres personalizados conservan el almacén nativo. El propio iPhone no se
puede bloquear. Véase [el cambio y sus límites](HOTSPOT-DIAGNOSTIC3.md).

Para comprobar el acceso del cliente, conectar el segundo iPhone a Compartir
Internet y desactivar temporalmente **sus datos móviles**: así no sustituye la
conexión bloqueada por su red móvil. Confirmar primero que carga una página
nueva; bloquear, volver a comprobar y desbloquear para verificar recuperación.
El cliente puede seguir asociado a Wi-Fi aunque no pueda acceder a Internet.
Registrar IP mostrada, texto del error y resultado; el estado de una regla PF
por sí solo no demuestra el corte del tráfico. La prueba física está pendiente.

## Corrección de navegación en diagnostic2

La entrada de emisión desde Diagnósticos utilizaba el menú Bluetooth con Ayuda
en el margen izquierdo, ocultando el botón Atrás nativo. Ayuda ocupa ahora el
margen derecho y cede su lugar a Detener durante una operación. Volver a tocar
Información regresa a su raíz cuando no hay una operación Bluetooth ni una
presentación modal. Se conservan los tres hosts y el delegado de SwiftUI.

La regresión recorre la ruta real Información → Diagnósticos → emisión, comprueba
Atrás y la reselección de Información, y simula estados activo/deteniendo para
verificar que Detener sigue accesible. Fuentes compiladas: `2543f0fca94d7b274bbc3b0402f4a1f9f6352a32`.

- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/37945116263): aprobado.
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37945116207): aprobado.
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/37945119372): aprobado.

Simulador iOS 18.5: 42 comprobaciones por idioma (español e inglés), incluyendo
la ruta desde Información, Atrás, reselección y estados activo/deteniendo, más
cuatro ciclos reales de segundo plano por idioma. Capturas de emisión, regreso
a Diagnósticos y menú Información revisadas. Ocho pruebas de los paquetes de
las tres variantes y siete del paquete intermedio aprobadas.

App diagnostic2 instalada por SSH en iPhone XS / iOS 16.3.1 / RootHide. Versión,
commit, firma, UUID/hash de código y permisos verificados. Se mantiene el
trabajador diagnostic1 instalado anteriormente, con sus dos imágenes intactas.
La consulta de solo lectura funciona sin HCI ni cambiar el PID de bluetoothd;
no hay nuevos crashes relevantes ni trabajador retenido. Pendiente aceptación
manual de este arreglo de navegación en la app. Los demás iOS y bootstraps
siguen sin verificación física. Copia de recuperación adicional:
`/var/mobile/Documents/NukeWireless-diagnostic1-backup.deb` (app).

## Validación anterior: diagnostic1

Fuentes compiladas: `8b610e805ddf9c5485862592cc74c018e8e8684e`. Compilaciones aprobadas:

- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/37937898633): aprobado.
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37937898613): aprobado.
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/37937899941): aprobado.

Pruebas Foundation del registro aprobadas: redacción, UUID Mach-O, sesión
interrumpida, límites, estado pendiente, exportación, retención y borrado.
Seis suites C locales aprobadas; MinGW es de 32 bits y se usaron dobles SSE
para evitar la precisión extendida x87 en las aserciones exactas existentes.
Simulador iOS 18.5: 35 comprobaciones y cuatro ciclos reales de segundo plano
por idioma, español e inglés. Capturas de diagnóstico claro/oscuro revisadas;
las filas admiten títulos multilínea con contenido nativo de UIKit.
Ocho pruebas de los seis paquetes y siete del paquete intermedio aprobadas.

La variante RootHide está instalada en iPhone XS / iOS 16.3.1. Se verificaron
versiones, esquema, commit, UUID y hash de la sección de código de cuatro
componentes después de firmarlos, identidad CodeDirectory del ejecutable y
permisos del trabajador. `--diagnostics` devuelve la información esperada sin
abrir canal ni enviar HCI; bluetoothd conserva su PID. No hay nuevos crashes
relevantes ni trabajador retenido tras esta comprobación. Esto no acredita
todavía la navegación/exportación manual de la app ni recepción de radio en
esta edición. La aceptación de dev53/app32 corresponde a la versión anterior.

Recuperación conservada en el mismo iPhone:
`/var/mobile/Documents/NukeWireless-dev53-backup.deb` y
`/var/mobile/Documents/NukeWireless-app32-backup.deb`, ambos verificados por hash.
Cerrar la app antes de reinstalarlos mediante el mismo entorno del jailbreak;
no hace falta un reinicio general por rutina.

No hay dispositivos disponibles para verificar físicamente iOS 15, 17, 18,
rootless o rootful. Cada tester debe enviar su entorno exacto y el informe.
