# Acciones de equipos y estado del punto de acceso: diagnostic5

El usuario confirmó el bloqueo y desbloqueo del punto de acceso en diagnostic4.
Diagnostic5 cambia la presentación: mano roja para el cliente bloqueado; los
otros iconos conservan el acento. No cambia reglas PF ni el trabajador Bluetooth.

La hoja de acciones reconocida muestra nombre, fabricante y estado en la
cabecera, e IP y MAC como filas identificadas en una sección de direcciones.
El dispositivo local se presenta con el texto traducido «Este iPhone». Se abre
en el tamaño grande de la hoja, que conserva desplazamiento, tamaño medio,
cierre, texto adaptable, VoiceOver y modo oscuro.

Los menús de Equipos y Punto de acceso adjuntan una copia de presentación del
equipo. Para menús heredados reconocidos se busca una IP exacta y única en el
snapshot Wi-Fi; si no existe una coincidencia inequívoca se conserva el texto
original. Se reconocen los menús UIKit de ambos estilos cuando contienen las
acciones esperadas y todos sus manejadores están capturados; los diálogos con
campos de texto mantienen su presentación. Esto solo organiza datos de presentación: los manejadores de las
acciones, la comprobación de generación/red y las restricciones no cambian.

La regresión existente del menú comprueba filas IP/MAC, reconocimiento de un
título heredado y rechazo de una dirección ajena al snapshot. La verificación de compilación, capturas, paquete e instalación se detalla debajo.

## Verificación de la entrega

Fuentes compiladas: `4f2f7c76ce2c570e882ca0cb6a5e9d5bbaea59ac`. Ambos trabajos aprobados:

- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/37991460042)
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37991459957)

Simulador: 46 comprobaciones por idioma y cuatro ciclos reales de segundo
plano por idioma. Menús y cambio de nombre con la búsqueda activa aprobados;
capturas de menús en modo oscuro y listado en claro revisadas. Paquete: 15 comprobaciones
aprobadas. Instalación RootHide en iPhone XS/iOS 16.3.1 verificada por versiones,
UUID/hash del código instalado, firma y permisos; sin nuevos crashes relevantes
durante la instalación. Trabajador Bluetooth sin cambios y comprobación de
diagnóstico sin abrir radio ni cambiar el PID de bluetoothd.

La aceptación visual manual de la mano roja y del menú Wi-Fi queda pendiente.
El usuario confirmó el bloqueo del cliente en diagnostic4; el código PF no
cambia en esta revisión. Las otras variantes e iOS no tienen aceptación física.
Recuperación: `/var/mobile/Documents/NukeWireless-diagnostic4-backup.deb`,
verificada por hash antes de instalar. No se realizó reinicio general.
