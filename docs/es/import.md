# Importar y usar X Linux en WSL

Esta guia explica como convertir el tarball generado por `build-rootfs.sh` en
una distribucion X Linux funcional bajo Windows Subsystem for Linux (WSL).
X Linux para WSL es headless: sin GUI, sin Hyprland/compositor. Usa `systemd` y
se maneja desde la terminal.

La via mas rapida es el importador PowerShell incluido `install.ps1`; los
comandos manuales se listan junto a el. Las referencias oficiales son los
comandos basicos de WSL (https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
y la guia de configuracion (https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

## Requisitos

- Windows 11 (o Windows Server 2022) con WSL habilitado. El soporte de
  `[boot] systemd` que activa el rootfs necesita Windows 11/Server 2022 y la
  build de WSL de Microsoft Store. En Windows 10 el rootfs se importa y
  arranca, pero systemd no esta disponible.
- WSL desde Microsoft Store (no la version integrada). Instala WSL sin una
  distribucion incluida desde una consola de PowerShell elevada:

  ```powershell
  wsl --install --no-distribution
  ```

  Comprueba la version y actualiza si hace falta:

  ```powershell
  wsl --version
  wsl --update
  ```

  Si `wsl --version` no se reconoce, estas en la version integrada; instala la
  build de Store (https://apps.microsoft.com/detail/9P9TQF7MRM4R).
- El tarball del rootfs de este repositorio. Generalo en un host Arch con
  `sudo ./build-rootfs.sh`, o descarga un `out/x-wsl-rootfs.tar.gz`
  publicado.

## 1. Generar el rootfs

En un host Arch Linux (o basado en Arch), desde este repositorio:

```bash
sudo ./build-rootfs.sh
```

Esto produce `out/x-wsl-rootfs.tar.gz` (mas un fichero de checksums `.sha256`).
Puedes ver los comandos exactos sin tocar el sistema primero:

```bash
X_DRY=1 ./build-rootfs.sh
```

Copia el tarball a una ruta legible por Windows, por ejemplo
`C:\Users\<tu-usuario>\Downloads\x-wsl-rootfs.tar.gz`.

## 2. Importar la distribucion (recomendado)

Abre PowerShell en este repositorio y ejecuta el importador. Comprueba WSL
(build de Store), importa el rootfs como WSL 2, convierte `x` en la
distribucion por defecto e imprime la guia de `.wslconfig` del host y los
siguientes pasos:

```powershell
.\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz
```

Si PowerShell bloquea la ejecucion de scripts en tu maquina, lanzalo con un
bypass explicito:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Rootfs .\out\x-wsl-rootfs.tar.gz
```

Opciones: `-Name` (default `x`), `-InstallDir` (default una ruta por usuario
bajo `%LOCALAPPDATA%`), `-NoDefault` (saltar `wsl --set-default`) y
`-CreateWslConfig` (crear un `%UserProfile%\.wslconfig` inicial si no existe;
nunca sobrescribe uno existente). Ejecuta `Get-Help .\install.ps1` para mas
detalle.

### Alternativa manual

```powershell
cd $HOME\Downloads
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2
wsl --set-default x
```

- `--version 2` fuerza WSL 2 sin depender del default de la maquina.
- `<UbicacionInstalacion>` (`C:\WSL\x`) es la carpeta de Windows que albergara
  el VHD de la distribucion; usa cualquier carpeta, idealmente fuera del
  directorio del tarball.
- Comprueba que la distribucion esta registrada:

  ```powershell
  wsl --list --verbose
  ```

## 3. Arrancar la distribucion

```powershell
wsl -d x
```

La primera sesion se abre como **root**: las distribuciones importadas arrancan
siempre como root hasta que se configura un usuario por defecto. El
`/etc/wsl.conf` incluido ya activa `systemd`; comprueba que esta corriendo:

```bash
ps -p 1 -o comm=
# imprime: systemd

systemctl is-system-running
# imprime: running (o degrading hasta configurar los servicios de usuario)
```

Si `systemd` no es el PID 1, reinicia WSL tras revisar `/etc/wsl.conf`:

```powershell
wsl --shutdown
```

WSL tarda unos 8 segundos tras cerrar la ultima instancia en recoger un cambio
de configuracion; `wsl --shutdown` fuerza el reinicio.

## 4. Configurar tu usuario

El aprovisionamiento de usuario lo gestiona
[xlnux/wsl-scripts](https://github.com/xlnux/wsl-scripts). Clonalo donde puedan
leerlo tanto root como el futuro usuario y ejecuta el instalador guiado (dos
partes):

```bash
git clone https://github.com/xlnux/wsl-scripts /opt/x-wsl-scripts
cd /opt/x-wsl-scripts
./install.sh            # Parte 1 (sistema), como root
```

La fase de sistema pregunta por locale, keymap, zona horaria, usuario, shell y
politica de sudo, y luego fija el usuario creado como usuario por defecto de
las nuevas sesiones en `/etc/wsl.conf` (las distribuciones importadas no tienen
launcher de Windows, asi que `/etc/wsl.conf` es la unica via soportada para
cambiar el usuario por defecto). Al terminar, sal de la sesion y relanza para
que WSL aplique el nuevo default:

```powershell
wsl --terminate x
wsl -d x
```

La nueva sesion se abre con tu usuario. Ejecuta el instalador una segunda vez
para la fase de usuario (shell, entorno, carpetas):

```bash
cd /opt/x-wsl-scripts
./install.sh            # Parte 2 (usuario), como tu usuario
```

Si prefieres no usar el instalador, un usuario manual se crea asi, desde dentro
de la distribucion (como root):

```bash
useradd -m -G wheel -s /usr/bin/zsh <usuario>
passwd <usuario>
```

Arch Linux no otorga sudo al grupo `wheel` por defecto. Descomenta la linea de
wheel con `EDITOR=nano visudo` (la linea `%wheel ALL=(ALL:ALL) ALL`) o anade un
drop-in:

```bash
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
```

Despues, haz que ese usuario sea el de las nuevas sesiones de WSL editando
`/etc/wsl.conf` y fijando la seccion `[user]`:

```ini
[user]
default=<usuario>
```

Aplicalo reiniciando la instancia:

```powershell
wsl --terminate x
wsl -d x
```

Tu siguiente sesion se abrira como `<usuario>`. Las plantillas `wsl.conf` y
`.wslconfig` en `templates/` documentan todas las opciones usadas aqui.

## 5. Opcional: ajustes WSL 2 en el host

Crea `%UserProfile%\.wslconfig` (es decir, `C:\Users\<tu-usuario>\.wslconfig`)
a partir de `templates/.wslconfig` y adaptalo a tu hardware. Limita la memoria
y los procesadores de la VM, mantiene WSLg (soporte de GUI) desactivado porque
X Linux para WSL no tiene GUI, y habilita `autoMemoryReclaim` y `sparseVhd`
para Windows 11. No existe un `.wslconfig` por defecto; el importador solo
imprime guia y nunca sobrescribe uno existente (usa `install.ps1
-CreateWslConfig` para crear uno inicial si no hay). Windows tambien ofrece una
aplicacion "WSL Settings" que edita los mismos ajustes. Tras editar, ejecuta
`wsl --shutdown`.

## Solucion de problemas

- `wsl --import` falla: verifica el checksum del tarball primero
  (`sha256sum`), asegurate de que la carpeta destino no contenga ya una
  distribucion registrada con el mismo nombre (`wsl --unregister x` elimina
  una) y ejecuta el comando desde una consola elevada si Windows bloquea la
  operacion de ficheros.
- La instancia arranca pero falta `systemd`: confirma que `wsl --version`
  funciona (build de Store), que el host es Windows 11/Server 2022, que
  `/etc/wsl.conf` contiene `[boot] systemd=true` y reinicia con
  `wsl --shutdown`.
- Errores de usuario por defecto: WSL se niega a iniciar una sesion con un
  usuario inexistente. Manten `default=root` o apuntalo a un usuario que hayas
  creado.
- `pacman` se queja de las claves tras importar: ejecuta
  `pacman-key --init && pacman-key --populate archlinux` como root dentro de la
  distribucion.
