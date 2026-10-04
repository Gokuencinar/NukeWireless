# Lecturas de capacidades LE (app13 / dev28)

`nwbt-run --le-capabilities` es un diagnóstico limitado al operador root o al
proceso padre exacto de la app instalada (el mismo control de identidad del ping).
Se encuentra en NukeWireless > Info > Bluetooth > Consultar capacidades BLE.
No requiere rellenar la dirección ni las opciones del ping. Está limitado al
iPhone XS con iOS 16.3.1 y al transporte cuyo código ya valida el módulo.
Requiere Bluetooth apagado en Ajustes. Usa el bloqueo y el proceso independiente
de recuperación del ping; retira temporalmente bluetoothd y lo restaura al acabar.

Consulta solamente Read Local Version (0x1001), Read Local Supported Commands
(0x1002), Read Local Supported Features (0x1003), LE Read Local Supported Features
(0x2003) y LE Read Supported States (0x201c). No acepta opcodes externos.
No abre ACL, conecta accesorios, habilita anuncios, escanea, cambia direcciones,
reinicia el controlador ni modifica firmware. Las lecturas están limitadas a
dos segundos por comando y doce segundos en conjunto; la recuperación tiene
su propio plazo y sobrevive a la terminación del trabajador.

El JSON conserva estado HCI, opcode, tipo de evento y datos de retorno hexadecimales
sin direcciones de accesorios. Sólo `capabilities_verified: true` confirma las cinco
respuestas completas correctas. Un rechazo HCI queda registrado y no equivale a
soporte de emisión; un timeout o respuesta malformada detiene las siguientes lecturas.
El bitmap de comandos es evidencia declarada por el controlador, no una prueba de
que un anuncio haya sido emitido o recibido por otro dispositivo.

Las pruebas C cubren longitudes truncadas, opcode distinto, crédito de comandos,
Command Status frente a Command Complete, rechazos y exclusión de comandos de escritura.
La CI compila las pruebas y los tres binarios. Una compilación correcta no verifica
el transporte real: hace falta guardar el resultado del iPhone y comprobar
`service_restored: true` antes de pasar a una prueba de publicidad BLE.

La app guarda el último resultado, permite cancelar y cancela al pasar a segundo
plano. Distingue respuestas verificadas, consultas rechazadas y soporte declarado
de anuncios. El botón sólo se habilita con el nuevo indicador
`supports_le_capability_app`; app12 anuncia lecturas pero sólo admite al operador root.
La regresión de UI verifica este caso, resultados, bloqueo mientras está ocupado y
textos en español e inglés sin abrir el transporte del simulador.

Referencias de protocolo: Bluetooth Core, HCI Functional Specification;
https://raw.githubusercontent.com/bluez/bluez/master/lib/bluetooth/hci.h
