# Auditoría de Nuke Wireless — 1.0.25+rh25.5~dev1

## Alcance y base

Se trabaja sobre `main` en `ff5cb101ad405fc71e438a2b19da7caa783e25fc`, que conserva `rh25.3` tras retirar `rh25.4`. Rama de trabajo: `audit-rh25.5`. No se han creado releases ni modificado `main` o el repositorio público de paquetes.

Base: `com.gokuencinar.nukewireless_1.0.25+rh25.3_iphoneos-arm64e.deb`.
SHA-256: `83b8f4364194ecabda0e516659568e7e92af656c0cfa82222ccb596239bfc128`.

No se dispone del código Swift original completo. La auditoría combina las fuentes disponibles, metadatos Objective-C y desensamblado del ejecutable fijado por hash. No se presenta como una recuperación del proyecto original.

## Causas y cambios

| Problema | Hallazgo | Cambio implementado |
| --- | --- | --- |
| Banner y desplazamiento de Info | Superposición heredada de créditos y otra capa de red, coordenadas absolutas y ajustes globales de altura del scroll. | La pestaña Info se sustituye por una tabla con `UITableViewAutomaticDimension`, restricciones al contenido y safe areas. Se eliminan del código de la extensión las capas antiguas y los hooks globales de tamaño/gestos. No hay banner ni altura fija de página. |
| Actualizar | La rutina Swift renovaba la lista pero reutilizaba el escáner. El estado de ocupación podía depender de una cola anterior; no había una sesión que distinguiese callbacks antiguos. El método nativo `stop` espera a sus operaciones. | La renovación Swift se conserva, pero cada inicio crea un `MMLANScanner` nuevo con delegado de sesión. Inicio/parada van en una cola serial por instancia; nunca se espera a `stop` desde el hilo principal. Callbacks se entregan al hilo principal solo para la generación vigente. |
| Escaneo bloqueado tras error | Flags y callbacks sin recuperación coordinada. | Watchdog: 5 s para que comience, 45 s sin progreso y máximo 300 s. Terminar o fallar libera el estado para reintentar. El control de refresco finaliza su animación. Doble toque durante escaneo o lote no inicia otra renovación. |
| Contador/lista | El registro heredado de 64 entradas y su reinicio dependían de reconocer el dispositivo local; no representaban necesariamente la lista visible. | Diccionario de resultados de la sesión por IPv4, deduplicación y actualización de campos disponibles. Se aplica la exclusión local heredada antes de contar. La renovación nativa vacía su lista publicada. |
| Bloquear todos | Los hooks de captura buscaban `initWithDelegate:andEnableHotspot:` y `start` en el adaptador Swift `LanScanner`; esos métodos pertenecen a `MMLANScanner`. La captura usada por el flujo masivo no se completaba. | El botón usa una instantánea del escaneo actual y llama a `MCCommands.blockGivenIPWithIp:targetMac:` y `unblockIPWithIp:`, los métodos de la ruta individual. No añade otro motor de bloqueo. |
| Exclusiones y fallos del lote | El flujo dependía de su estado de escaneo independiente. | Excluye dirección propia, router, red, broadcast, multicast, MAC nula/multicast, IP fuera de subred y contexto incompleto. Procesa cada elemento y continúa después de un fallo. Comprueba procesos registrados, actualiza `isBlocking` y permite desbloquear registros conocidos aunque ya no estén en la lista nueva. |
| Concurrencia y red cambiada | No había una identidad de sesión compartida. | La confirmación guarda generación y red; si cambian, no continúa bloqueando objetivos del escaneo anterior. Los botones reflejan actividad. La tabla nativa admite 64 procesos: el lote se detiene con fallo parcial antes de desbordarla. |
| Última fila Wi-Fi tapada | El panel inferior se superponía sin reservar su área efectiva. | Inset calculado desde la geometría del panel y del scroll, descontando el inset del sistema y sin acumulación en cada layout. Se mantiene el panel y el botón Nombres. |
| Estados tras bloqueo individual | La UI añadida no recibía todas las acciones Swift. | Reconciliación periódica de los registros de procesos mientras Wi-Fi está visible; no modifica el motor individual. Un proceso vivo es evidencia de ejecución, no prueba de que el equipo remoto esté aislado. |

El puente Swift está limitado al ejecutable de la base por SHA-256 y al prólogo de la función de actualización en `0xc5a8`. No se escriben ivars Swift directamente. Los callbacks de descubrimiento siguen pasando por los hooks existentes de nombres y por el adaptador que publica la lista.

## Ajustes avanzados: inventario completo

El inventario de la pantalla original comprende las cuatro acciones siguientes; no se encontró un selector de idioma en esa pantalla.

| Opción original | Decisión | Conexión actual |
| --- | --- | --- |
| Blocking Packets | Conservada y reparada su integración. | Intervalo entre 0,2 y 5 s; conserva `packetTime` y el valor predeterminado 0,9. Se aplica a `-w` en nuevos procesos `arpoison`, tanto individuales como del lote. No altera los procesos de restauración con `-n` ni los bloqueos ya activos. |
| Update OUI Database | Reparada. | Descarga IEEE mediante HTTPS, valida respuesta, tamaño y entradas; escribe la tabla de forma atómica. El enriquecimiento de fabricantes durante el siguiente escaneo consume esa tabla. Un error conserva la anterior y libera el estado de actualización. |
| Reset and repopulate OUI lookup database | Reparada y aclarada. | Elimina únicamente la tabla descargada por la extensión y vuelve a la tabla incluida en el paquete. No borra alias ni otros ajustes. |
| Re-run Onboarding | Eliminada de la pantalla accesible. | La introducción original está vinculada a la arquitectura/validación antigua y no aporta una configuración útil a esta adaptación. No se añade un botón sin efecto. |

La pantalla nueva no conserva variables, callbacks ni textos de la opción eliminada. **Límite:** su implementación ya compilada sigue dentro del ejecutable original y no puede extirparse de forma segura sin sus fuentes. Las preferencias internas de introducción que el arranque todavía consulta se conservan por compatibilidad; no se borran a ciegas.

## Info, red y branding

- Créditos: Gokuencinar GokuEn, avatar incluido en la base, GitHub y Buy Me a Coffee.
- Red: SSID, BSSID, IPv4, puerta de enlace, máscara y DNS. Tocar un valor disponible únicamente lo copia al portapapeles; no navega a otra pantalla.
- Consulta de red fuera del hilo principal para Info. Se descartan resultados de una solicitud anterior de esa pantalla.
- No se añaden CoreLocation, solicitudes de autorización de ubicación ni claves de permiso de ubicación.
- Licencias y agradecimientos conservados con el formato real del plist original: lista de entradas `title`/`license`.
- Nombres visibles, metadatos, README y comentarios de adaptación usan Nuke Wireless. Los dos textos visibles largos del ejecutable que aún usaban el nombre anterior se sustituyen por “Welcome to Nuke Wireless!” y “Nuke Wireless uses the MIT license.”, con igual longitud de almacenamiento.
- Bundle ID, rutas, nombres de clases Swift, nombres de bibliotecas, conflictos/reemplazos del paquete y prefijos técnicos históricos de depuración se mantienen. Renombrarlos rompería enlaces, persistencia o diagnóstico del núcleo conservado. También se mantienen las atribuciones legales.
- Textos nuevos en español e inglés con selección por idioma del sistema; no se alteran `AppleLanguages` ni preferencias previas.

## Construcción y comprobaciones

1. Pruebas C ejecutadas en Windows y macOS: generaciones, reintentos, callbacks tardíos, doble finalización, límites temporales, 1.000 ciclos, exclusiones de objetivos y valores del intervalo.
2. Pruebas Foundation en macOS: parser OUI, datos vacíos/incorrectos, sustitución del intervalo y conservación de tareas de restauración y tareas ajenas.
3. Compilación iOS arm64 con mínimo 16.3 y `-Wall -Wextra -Werror`. El enlace también rechaza avisos; se ha eliminado la opción obsoleta `-undefined dynamic_lookup`.
4. Seis pruebas de paquete: cambios limitados a los archivos previstos, textos sin cambios de longitud/instrucciones, metadatos/recursos/localizaciones, scripts de firma, procedencia de la biblioteca y rechazo de base desconocida o artefacto alterado.
5. El manifiesto adjunto registra hashes de las fuentes y del resultado. El empaquetador no acepta bibliotecas antiguas con fuentes nuevas. Se retira el prebuilt obsoleto y el workflow anterior que hacía commits automáticos en `main`.
6. Test de ABI sobre los metadatos Objective-C del paquete: clase concreta del escáner, tipos de callbacks y métodos de bloqueo/desbloqueo individual coinciden con las llamadas implementadas.
7. Las dos bibliotecas de rutas, auxiliares de red, avatar, licencias y scripts de instalación permanecen idénticos a la base. Los scripts de instalación se inspeccionan como datos; no se ejecutan en el ordenador.

El hash definitivo y la ejecución privada de CI se registran en `BUILD-RESULTS.md` junto al paquete preparado.

## Pendiente de validación en dispositivo

El iPhone configurado responde, pero las credenciales SSH disponibles no permiten autenticar. No se ha instalado ni ejecutado esta candidata en el dispositivo. Los logs antiguos disponibles no prueban su funcionamiento.

Quedan pendientes: descubrimiento real y repetido en iOS 16.3/Dopamine RootHide, eficacia del bloqueo y restauración de conectividad, convivencia de los hooks con SwiftUI en ejecución, lectura efectiva de SSID/BSSID, comportamiento con cambios reales de red, aspecto/scroll con distintos tamaños y Dynamic Type. También la descarga IEEE desde el propio iPhone y la firma/inyección durante la instalación.

Los tests de lógica, compilación y estructura del paquete pasan de forma independiente a esas validaciones. No demuestran ausencia total de regresiones en el binario original. No se solicita al usuario ninguna prueba durante este trabajo.
