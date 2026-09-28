# Resultado de la compilación privada

**Retirada:** la deb `dev3` supera compilación y pruebas estructurales, pero la app se queda en la pantalla azul inicial. Se reinstaló `rh25.3`, que el usuario confirmó funcional. El archivo `dev3` se retiró de la carpeta de entrega y no debe instalarse.

- Versión: `1.0.25+rh25.5~dev3`.
- Código compilado: `a14ca88` en `audit-rh25.5`.
- CI privado: https://github.com/Gokuencinar/NukeWireless/actions/runs/36427121491 — `success`; pruebas C y Foundation y compilación iOS arm64 sin avisos.
- Paquete: `com.gokuencinar.nukewireless_1.0.25+rh25.5~dev3_iphoneos-arm64e.deb`.
- SHA-256: `3c450d9651b3bbead6b90cb51c599a671c990cea9084aba0eabb63536fbbca5e`.
- Siete pruebas del paquete y prueba de ABI: correctas.
- Instalación SSH en iOS 16.3.1/Dopamine RootHide: `dpkg -i` terminó con código 0 y `Status: install ok installed`; el arranque no avanzó de la pantalla inicial.
- Registro del arranque: `extension dev3 loaded` y `Wi-Fi refresh ready`; recurso `CreditsAvatar.png` presente.
- Los seis campos de red estuvieron disponibles en una ejecución diagnóstica anterior. Ninguna función de `dev3` queda validada para uso normal; consultar `AUDIT-rh25.5.md`.
- Sin release, tag, modificación de `main` ni publicación en el repositorio público de paquetes.

La candidata `dev1` publicada antes como archivo local tenía un fallo de instalación y queda retirada. `dev2` fue solo una etapa diagnóstica. Ninguna se publicó como release.
