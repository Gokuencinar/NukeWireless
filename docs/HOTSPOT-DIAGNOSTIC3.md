# Punto de acceso y acciones de equipos: diagnostic3

Estado: fuentes preparadas; compilación y validación física pendientes.

El iPhone XS/iOS 16.3.1 de referencia tiene `/dev/pf` pero no `/sbin/pfctl` ni
`/usr/sbin/pfctl`. El bloqueo heredado intentaba ejecutar ese comando y cargar
un `pf.conf` con una tabla IPv4 en bridge100. Iniciar ese proceso no demostraba
que se hubiese aplicado el bloqueo.

El nuevo `nw-hotspot` acepta únicamente estado, bloquear y desbloquear un
cliente IPv4/MAC. Requiere root o el proceso instalado de NukeWireless bajo el
mismo bootstrap. La app no recibe permisos nuevos. Valida la red bridge, la
identidad ARP del cliente y la ABI PF antes de modificar reglas. Solo añade o
quita reglas etiquetadas `NukeWirelessHotspot:<MAC>:`; conserva las reglas y NAT
del sistema. Elimina estados del cliente seleccionado y verifica las reglas
mediante lectura posterior. Incluye IPv6 globales ya asociados al cliente en la
tabla de vecinos; todavía hay que comprobar el tráfico real del receptor y la
aparición de nuevas direcciones IPv6. El estado de la regla no demuestra por sí
solo que toda conexión del cliente se haya interrumpido.

Las estructuras proceden del [XNU oficial 8792.61.2](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/net/pfvar.h).
`src/hotspot/vendor/SOURCES.json` fija procedencia, hash original y cambios de
inclusiones para el SDK. No se modifican estructuras ABI. La admisión Darwin
21–24 exige que respondan los ioctl; otros dispositivos siguen sin prueba física.

El listado UIKit se contiene dentro del host SwiftUI original de Punto de acceso
y conserva el escáner y delegado nativos. Cada IP produce una única fila. La IP
local se reconoce mediante interfaces y no puede bloquearse. Recarga y arrastre
esperan a que termine la cola nativa y las acciones incompatibles. Los nombres
personalizados siguen usando MMDevice, sin un almacén alternativo.

La hoja de acciones usa datos del equipo, iconos y acciones atenuadas cuando no
están disponibles. Conserva los manejadores públicos de los menús reconocidos
de Wi-Fi/buscador y del punto de acceso, incluido renombrar desde una búsqueda.
Mantiene texto adaptable, VoiceOver y apariencia clara/oscura. No cambia radio,
trabajador Bluetooth, firma de la app ni identidad de sus tres hosts SwiftUI.

Pruebas previstas: operaciones PF con ioctl simulado sin tocar el firewall del
host, duplicado local/IP, tokens obsoletos, menú y navegación reales del
simulador en ambos idiomas, paquete y cliente físico `172.20.10.2`.
