# Validación compat3 — 8 de octubre de 2026

Candidatas `1.0.25+rh25.6~compat3`, basadas en la interfaz dev52 y trabajador
`0.0.3~app31`. Fuentes compiladas: `f32f084b561a5ffbd08530a41019d1c2b7341a6e`. La referencia
instalada y aceptada sigue siendo dev52/app31 en iPhone XS / iOS 16.3.1 / RootHide.

## Resultado comprobado

- [CI de compatibilidad](https://github.com/Gokuencinar/NukeWireless/actions/runs/37830781937): **success**.
  App actual y adaptador compilados arm64, mínimo 15.0, disponibilidad estricta.
  Trabajador app31 recompilado con su guard nativo intacto.
- [CI habitual](https://github.com/Gokuencinar/NukeWireless/actions/runs/37830781597): **success**.
  La configuración de desarrollo conserva mínimo 16.3.
- Simulador **iPhone 16 Pro / iOS 18.5**, binarios de regresión con mínimo 15.0:
  **33 comprobaciones por idioma**, español e inglés; cuatro ciclos reales de
  segundo plano por idioma, conservando el proceso. Capturas Bluetooth y
  catálogo oscuro revisadas. Esta app de pruebas no sustituye la carga de la
  extensión sobre el núcleo Swift original en dispositivo.
- Tres paquetes de app y tres del trabajador inspeccionados: **ocho pruebas
  aprobadas**, sin omisiones. Rutas, identidad, recursos, mínimos Mach-O,
  restricciones del trabajador, hashes, padres y rechazo de artefactos distintos.
- Repositorio verificado **privado** antes de subir fuentes y al descargar CI.
  No se ha publicado una release ni desplegado esta candidata.

## Paquetes generados

| Esquema | Componente | SHA-256 |
| --- | --- | --- |
| roothide | App compat3 | `195e70db7e3cc6aaab2c548d0b1159918b9aa2c50a4bb92c914c292de8265cc6` |
| roothide | Bluetooth app31 | `faf6367bb8f1cd0197644e63a73cb54c5a138ff47ee3068ed0d502fa4fe08c4a` |
| rootless | App compat3 | `4544ec6f96a1ffb180ccd9b22eda68233a2c2956fe9011d825c056a0f4b15371` |
| rootless | Bluetooth app31 | `a3beb6e1e2eb5434daba929170ec52840bfd11e80eb1a8f08bc852dc8afaac33` |
| rootful | App compat3 | `f126602e09b3bcc46a5b7612d143e196e7235dfc487ff7e122913f697f9bd66b` |
| rootful | Bluetooth app31 | `545fcf3e1d9328b6941067f9773d18e3ac46640ddafce0dff597ac196422a13c` |

Cada app incluye su manifiesto y `compatibility.json`; cada trabajador incorpora
su manifiesto. Se entregan ZIP separados con los dos paquetes del mismo esquema
junto con procedencia e instrucciones. Los archivos están en `outputs/compat3`
del directorio de esta conversación, fuera del repositorio fuente.

## Límites y pendientes

**No se acredita compatibilidad funcional completa iOS 15–18.** No hay otros
dispositivos físicos disponibles para validar iOS 15/17/18, Dopamine convencional
o rootful. Los paquetes son instalables según sus metadatos; sus funciones Wi-Fi,
CoreBluetooth, carga de extensión y permisos requieren observación propia.

La emisión nativa continúa restringida a **iPhone11,2 / iOS 16.3.1**, con guard
adicional de la biblioteca privada inspeccionada; solo RootHide tiene validación
funcional previa. No se habilita radio en otro iOS mediante una reducción del
mínimo de compilación. Dopamine/rootful tampoco tienen prueba de emisión o
restauración, incluso con ese dispositivo/version.

Los auxiliares originales y el núcleo Swift se conservan con guards de hashes.
No hay fuente completa de ese núcleo. La candidata sustituye dos adaptadores
históricos por uno recompilado: su comportamiento físico queda pendiente.

El iPhone actual conserva dev52/app31 y sus datos. Esta entrega no requiere
respring, cambio de bootstrap ni forzar arquitecturas. Ver
[compatibilidad, build y recuperación](COMPATIBILITY.md).
