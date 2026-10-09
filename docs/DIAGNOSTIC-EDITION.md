# NukeWireless Dev · 2.0.0~diagnostic1

Edición de desarrollo para recoger evidencia de compatibilidad en iOS 15–18.
Se generan paquetes separados para RootHide, rootless y rootful. Compartir una
compilación no constituye una verificación en todos esos entornos.

## Uso por los testers

1. Instalar la app y el trabajador Bluetooth de la **misma variante y versión**.
   Esta edición actualiza los paquetes existentes; no instala otra app en paralelo.
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
6. Volver y pulsar **Exportar informe JSON**. El usuario elige el destino en la
   hoja de compartir; la app no sube archivos ni contacta a nadie automáticamente.

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

## Validación de esta edición

Pendiente de compilación y pruebas de los nuevos cambios. La aceptación de
dev53/app32 se conserva como evidencia de aquella versión, no de esta edición.
No hay dispositivos disponibles para verificar físicamente iOS 15, 17, 18,
rootless o rootful. Cada tester debe enviar su entorno exacto y el informe.
