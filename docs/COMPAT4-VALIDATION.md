# Compat4 / dev53 / app32: validación del 8 de octubre de 2026

Fuentes compiladas: `1b641fc0416ae7571008ccb3a774d2c7b6bdc144`. Repositorio privado,
rama `audit-rh25.5`, sin release público.

- [iOS 15-18 compatibility candidates](https://github.com/Gokuencinar/NukeWireless/actions/runs/37835090789): aprobado.
- [Development build](https://github.com/Gokuencinar/NukeWireless/actions/runs/37835090785): aprobado.
- [Bluetooth transport inspector](https://github.com/Gokuencinar/NukeWireless/actions/runs/37835090859): aprobado.

## Comprobaciones

- App y adaptador actuales con mínimo iOS 15.0; trabajador arm64/iOS 15.0.
- Contrato de admisión, bitmap de capacidades y dominios de recuperación:
  pruebas C aprobadas localmente y en macOS. Se conserva el guard ACT/ACL.
- Simulador iPhone 16 Pro / iOS 18.5: 33 comprobaciones y cuatro ciclos reales
  de segundo plano por idioma, español e inglés, conservando el mismo proceso.
- Ocho pruebas sobre los seis paquetes: rutas de cada bootstrap, padres y
  duplicados, permisos, firma, recursos, procedencia y mínimos Mach-O reales.
- Siete pruebas adicionales del paquete de desarrollo dev53 aprobado.
- Instalación dev53/app32 en el iPhone XS de referencia: dpkg, versiones,
  CodeDirectory `me.midnightchips.harpy-reloaded`, logos, trabajador y servicio
  comprobados. No se observaron nuevos crashes relevantes en esa instalación.

Dos emisiones consecutivas y una tercera tras detener una emisión antes de diez segundos. Deshabilitación, retirada de conjuntos, servicio e interfaz restaurados en todas. Windows recibió los nueve perfiles Google/Fast Pair seleccionados. No se han verificado avisos de emparejamiento.

Son invocaciones CLI desde SSH root. La cancelación física se solicitó con
SIGTERM al hijo propio del shell, conservando la propiedad del proceso; no
equivale a tocar Detener en la app. El canal privado de cancelación conserva
sus pruebas C y la UI sus regresiones del simulador. Tras las pruebas, el
trabajador estaba inactivo, bluetoothd seguía en ejecución y no se observaron
nuevos crashes de la app, trabajador, bluetoothd o BlueTool. También se comprobó
el rechazo previo a la operación cuando Bluetooth estaba encendido.

La prueba física usa la app dev53 con su adaptador RootHide previo, no la app
compat4. No confirma el nuevo adaptador, Dopamine convencional, rootful ni la
emisión en iOS 15, 17 o 18. La aceptación manual de la UI dev53 está pendiente.
Se conservaron en el iPhone los paquetes verificados dev52 y app31 para recuperación.

## SHA-256 de los paquetes compat4

| Variante | App | Trabajador |
| --- | --- | --- |
| roothide | `13ce10b3810d5b2174779de58ffc5e9f0fef357f72694e98de87c6ffe8d096dc` | `3f8e7d9fb11e1e963899c9b5e8fa503549ada2e540ba6035e3f8a47828405eba` |
| rootless | `1f0e395bb15a1083c0cb1af881ebdb5834c3d18e94f0e7480b4ad9ebd6dde92a` | `57e36283868fe92d1faec6ee84cab0c792ebca3ba91be0f66ab50b30b1dc265c` |
| rootful | `ab6eba416c8a1b58c86a1a9e811dadeba8ee5ac356f772b0af1f9868d8e6dadc` | `b6715bab658903a5dd1e389c7784d90f4684e3c9525df4116603c5daf441ecb3` |

La app de desarrollo instalada dev53 tiene SHA-256
`2b0f7f87250aca950b54f362e80f7fea13a34a210c437628994478762370bf76`; su paquete app32 tiene
`a0145f80fc69f6786f12e093453b6732f3344dc4ee5856f0bac7fc592b07fc6f`. Las variantes compat4 llevan el mismo trabajador
compilado; los archivos deb pueden tener hashes distintos por los metadatos de
empaquetado. Cada manifiesto identifica sus bytes y fuentes exactos.

Los bundles están en `outputs/compat4` del directorio de herramientas de esta
conversación. Incluyen app, trabajador, manifiestos y LEEME. El informe
`VERIFICACION-COMPAT4.json` distingue compilación, simulador, paquete y referencia
física. La ampliación es experimental en las combinaciones sin dispositivo.
