# Punto de acceso y acciones de equipos: diagnostic3

Diagnostic3: compilación, simulador, paquete e instalación aprobados. La prueba
manual del bloqueo falló con `pf_apply`; por SSH se reprodujo `errno=16`.

Diagnostic4 obtiene el ticket `DIOCBEGINADDRS` y lo transmite en `pool_ticket`
antes de añadir cada regla. El contrato de
[XNU 8792.61.2, pf_ioctl.c](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/net/pf_ioctl.c)
rechaza con EBUSY un ticket distinto al del pool actual, también para reglas
simples de filtrado. La regresión simula un pool ya utilizado por Compartir
Internet, rechaza el ticket cero y verifica el fallo de adquisición sin modificar
reglas ajenas. Se añade `system_errno` al registro de la app. Compilación y
validación física de esta corrección pendientes. Los jobs de diagnostic4
`37988463847` y `37988463874` no llegaron a iniciarse: GitHub informó de pagos
fallidos o límite de gasto. Pasaron las seis suites C locales, traducciones,
sintaxis Python, manifiestos de fuentes y revisión de whitespace. La regresión
PF requiere macOS y todavía no se ha ejecutado para esta revisión. No se ha
reutilizado ningún binario anterior para empaquetar o instalar diagnostic4.

El iPhone XS/iOS 16.3.1 de referencia tiene `/dev/pf` pero no `/sbin/pfctl` ni
`/usr/sbin/pfctl`. El bloqueo heredado intentaba ejecutar ese comando y cargar
un `pf.conf` con una tabla IPv4 en bridge100. Iniciar ese proceso no demostraba
que se hubiese aplicado el bloqueo.

El nuevo `nw-hotspot` acepta estado, reconciliación, bloquear y desbloquear un
cliente IPv4/MAC; la limpieza de desinstalación solo admite root. Requiere root o el proceso instalado de NukeWireless bajo el
mismo bootstrap. La app no recibe permisos nuevos. Valida la red bridge, la
identidad ARP del cliente y la ABI PF antes de modificar reglas. Solo añade o
quita reglas etiquetadas `NukeWirelessHotspot:<MAC>:`; conserva las reglas y NAT
del sistema. Elimina estados del cliente seleccionado y verifica las reglas
mediante lectura posterior. Incluye IPv6 globales ya asociados al cliente en la
tabla de vecinos y reconcilia direcciones nuevas mientras se muestra el listado.
Retira las reglas propias cuando desaparece la red o ARP confirma que una IP se
ha reasignado a otra MAC; una entrada ARP ausente por sí sola no desbloquea al
cliente. Al desinstalar retira solo sus reglas. Todavía hay que comprobar el
tráfico real del receptor y la aparición de nuevas direcciones IPv6. El estado de la regla no demuestra por sí
solo que toda conexión del cliente se haya interrumpido.

Las estructuras proceden del [XNU oficial 8792.61.2](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.61.2/bsd/net/pfvar.h).
`src/hotspot/vendor/SOURCES.json` fija procedencia, hash original y cambios de
inclusiones para el SDK. No se modifican estructuras ABI. La admisión Darwin
21–24 exige que respondan los ioctl; otros dispositivos siguen sin prueba física.
La lectura de vecinos usa el empaquetado de 32 bits documentado en el
[ndp oficial de Apple](https://github.com/apple-oss-distributions/network_cmds/blob/main/ndp.tproj/ndp.c).

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

## Entrega diagnostic4

El bloqueo por facturación quedó superado al publicar el repositorio con
autorización del usuario. Trabajos aprobados:

- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/37989324581)
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37988580652)

Fuentes compiladas: `505986bcd2bb2cb612cad941adff0a181580e6f4`. Paquetes inspeccionados
(15 comprobaciones), interfaz (46 por idioma) y segundo plano (4 ciclos por
idioma) aprobados. Instalación RootHide verificada por versiones, hash/UUID del
código instalado, identidad CodeDirectory y permisos del ayudante. Sin nuevos
crashes relevantes durante esa instalación; trabajador Bluetooth sin cambios.

La operación PF con el cliente físico sigue pendiente.

Esto no sustituye la prueba del cliente cargando páginas con datos móviles
apagados: corte al bloquear y recuperación al desbloquear siguen pendientes
de aceptación manual. Tampoco acredita otras versiones de iOS o bootstraps.

## Aceptación manual posterior de diagnostic4

El usuario confirmó que el bloqueo y desbloqueo del cliente funcionan. La
siguiente revisión solo ajusta la presentación del estado y los menús de equipos.
