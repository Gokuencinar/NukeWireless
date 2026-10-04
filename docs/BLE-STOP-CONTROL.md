# Detener una prueba Bluetooth desde NukeWireless

La versión dev35/app19 añade «Detener» a la barra superior de Información → Bluetooth
mientras hay una operación en curso. Las pruebas BLE conservan su límite de
10 segundos y también pueden terminar antes mediante este botón.

Al pulsarlo, la app solicita la cancelación del trabajador actual mediante
un socket privado heredado como entrada estándar. El botón pasa a
«Deteniendo…» y se desactiva hasta que termina la
recuperación. La app mantiene bloqueados los nuevos diagnósticos durante ese
intervalo. También solicita la misma cancelación al entrar en segundo plano.

El trabajador app19 observa ese canal en un hilo independiente y activa
directamente un indicador atómico compartido con el bucle de radio, usando su
ruta existente de cancelación y limpieza. La app no
necesita permiso para señalar un proceso que ya ha cambiado a root. El cierre
del canal (incluido el cierre de la app) también solicita la cancelación.
No se aceptan PID externos ni comandos de radio a través de este canal.
El informe registra el tiempo efectivo de emisión y el tiempo entre recibir la
petición de parada y terminar la recuperación; la duración configurada de 10
segundos no se presenta como duración efectiva.

El trabajador abandona el bucle de anuncios, desactiva su
conjunto de anuncios, lo retira y deja que el proceso independiente de
recuperación restaure bluetoothd. Una cancelación solicitada antes de crear el
trabajador se conserva y se entrega cuando aparece el proceso.

La app solo muestra «Emisión detenida y Bluetooth restaurado» si el informe
confirma la desactivación, la retirada del conjunto y la recuperación del
servicio. Una confirmación incompleta no se presenta como una parada verificada.

Detener la emisión evita nuevos anuncios de esta prueba; no retira las
notificaciones que el receptor ya haya mostrado ni controla otros emisores.

La compilación de simulador prueba los estados del botón, la cancelación antes
del inicio del trabajador y la diferencia entre una limpieza confirmada y una
confirmación incompleta, en español e inglés. Las pruebas del canal comprueban
una solicitud pendiente al iniciarlo, un cierre de la app, una finalización
normal y el uso de entrada estándar convencional desde CLI.
La prueba física se documentará
por separado después de instalar el paquete.
