# Catálogo disponible y emisiones consecutivas · dev48/app29

El usuario informó de un error al finalizar una emisión que le obligaba a cerrar y abrir la app. Más tarde no pudo reproducirlo: las emisiones actuales terminan correctamente. El texto recordado era «no se había podido completar el diagnóstico Bluetooth»; no hay un informe conservado de ese fallo exacto. Los registros actuales acreditan emisiones y cancelaciones limpias en dev47/app28 con el mismo PID de la app. No se atribuye el incidente a Bluetooth apagado sin evidencia.

Existe una carrera documentada en dev44: justo tras restaurar bluetoothd, el siguiente preflight no encontró la interfaz HCI. El proceso en ejecución no demuestra que el nexus esté publicado. App29 observa el canal HCI después de restaurar el servicio, manteniendo el bloqueo y la operación ocupada hasta terminar. Abre/cierra únicamente el canal; no consume frames ni envía comandos. Acepta apertura o EBUSY del servicio restaurado. Solo reconsulta interfaces pendientes durante cinco segundos; errores de ABI, permisos, símbolos o UUID inválido no se reintentan. El preflight incorpora la misma espera y vuelve a comprobar Bluetooth apagado antes de retirar servicios. No se repite la emisión ni se reinicia la app. Una orden Detener tardía no acorta la comprobación de limpieza. La restauración del servicio espera de forma acotada su estado running. El informe distingue service_restored y controller_interface_ready; una interfaz no confirmada deja un error visible.

Por petición expresa, generar muestra seis modelos emitibles y amplía cada catálogo con tres entradas, preservando los índices anteriores. Apple tiene ocho perfiles (28 selecciones de seis); Google/Fast Pair seis (una selección); Microsoft y Samsung nueve (84 selecciones cada uno). Se excluye la última selección por marca cuando existe alternativa. Fast Pair conserva sus seis modelos y renueva UUIDs locales. No se inventan perfiles de AirPods 4, Pixel Buds Pro 2, Nest Mini o Nest Audio: quedan fuera de la generación. El trabajador sigue rechazando sus índices. No se cambia el nombre de la pestaña Google: designa el protocolo Fast Pair, con accesorios de varios fabricantes, explicado en la ayuda.

Entradas añadidas:

| Plataforma | Modelos | Identidad de anuncio |
| --- | --- | --- |
| Apple | AirPods 3, Beats Studio Buds, Beats Fit Pro | 2013, 2011, 2012 (little endian en el payload) |
| Google / Fast Pair | Sony WH-1000XM4, Bose NC 700, JBL Flip 6 | 058D08, CD8256, 821F66 |
| Microsoft / Swift Pair | Surface Earbuds, Surface Arc Mouse, Microsoft Modern Mouse | Display Name completo, sin ID de producto registrado |
| Samsung / EasySetup | Galaxy Buds2 (Purple), Galaxy Buds2 (Black), Galaxy Buds Live (Red) | 39EA48, 011716, 42C519 |

Las entradas Samsung nuevas son variantes de color, no tres familias adicionales. Se mantiene el cuerpo EasySetup investigado. Los nombres Microsoft caben completos en el presupuesto AD de 31 bytes; su anuncio sigue siendo descubrimiento de laboratorio sin emparejamiento. No se afirma que el payload replique todas las capacidades del accesorio.

Fuentes contrastadas en esta iteración: [tabla y serialización Apple](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/continuity.c#L139-L158), [tabla Fast Pair](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/fastpair.c), [tabla Samsung](https://github.com/Flipper-XFW/Xtreme-Apps/blob/1e423683d90fd89e756d4003c4fc3ed8aec53c25/ble_spam/protocols/easysetup.c#L8-L28) y [estructura Swift Pair oficial](https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/bluetooth-swift-pair). Son correspondencias de investigación y formato, no aceptación de un aviso en todos los receptores. Los productos Microsoft se contrastaron con [Surface Earbuds](https://learn.microsoft.com/en-us/surface/surface-accessories-driver-firmware-lifecycle-support), [Surface Arc Mouse](https://support.microsoft.com/en-us/surface/accessories/mouse-keyboard/use-surface-arc-mouse) y [Modern Mouse](https://www.microsoft.com/en-gb/p/microsoft-modern-mouse/91474fhcbqbf).

App29 admite entre uno y seis índices distintos. Declara supports_le_catalog_six_models para impedir que dev48 solicite seis al trabajador app28. La capacidad real de sets se consulta antes de configurar anuncios; si es insuficiente se rechaza sin una emisión parcial. Cada set conserva límite de diez segundos; todos se deshabilitan y retiran en finally. No hay rotación de direcciones, conexiones, aumento de potencia ni reintentos de radio.

Se mantienen emisión individual/conjunta, catálogo abierto, Detener accesible, diez segundos, cancelación cooperativa, recuperación independiente, firma y permisos. Los éxitos permanecen silenciosos. No se añaden avisos de diagnóstico a la navegación habitual.

## Verificación

Pendiente de compilación, paquete, instalación y prueba de emisiones consecutivas. Las pruebas C cubren las 197 selecciones válidas, los 32 perfiles y el presupuesto AD y los índices rechazados; la regresión UIKit comprueba selección disponible, cambios de marca, regeneración de IDs y varios ciclos individuales con cancelación sin cerrar el catálogo. La recepción o avisos de modelos en sistemas receptores requieren evidencia independiente.
