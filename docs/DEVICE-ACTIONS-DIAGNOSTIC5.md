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
original. Esto solo organiza datos de presentación: los manejadores de las
acciones, la comprobación de generación/red y las restricciones no cambian.

La regresión existente del menú comprueba filas IP/MAC, reconocimiento de un
título heredado y rechazo de una dirección ajena al snapshot. Compilación,
capturas, paquete e instalación de esta revisión pendientes.
