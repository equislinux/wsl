# Importar y usar X Linux en WSL

Esta guia explica como convertir el tarball generado por `build-rootfs.sh` en
una distribucion X Linux funcional bajo Windows Subsystem for Linux (WSL).
X Linux para WSL es headless: sin GUI, sin Hyprland/compositor. Usa `systemd` y
se maneja desde la terminal.

## Requisitos

- Windows 11 (o Windows 10 con actualizaciones recientes) con WSL habilitado.
  Instalalo desde una consola de PowerShell elevada:

  ```powershell
  wsl --install
  ```

- WSL desde Microsoft Store (no la version integrada) para tener soporte de
  `systemd`. Comprueba la version:

  ```powershell
  wsl --version
  ```

  La version debe ser 0.67.6 o superior. Actualiza con `wsl --update` si hace
  falta.
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

## 2. Importar la distribucion

Abre PowerShell e importa el tarball. El formato del comando es
`wsl --import <Nombre> <Ubicacion> <Tarball>`:

```powershell
cd $HOME\Downloads
wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz
```

Opciones:

- `--version 2` fuerza WSL 2 (por defecto cuando WSL 2 es la version por
  defecto): `wsl --import x C:\WSL\x .\x-wsl-rootfs.tar.gz --version 2`
- Comprueba que la distribucion esta registrada:

  ```powershell
  wsl --list --verbose
  ```

- Convierte X Linux en tu distribucion por defecto (opcional):

  ```powershell
  wsl --set-default x
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

Nota: WSL tarda unos 8 segundos tras cerrar la ultima instancia en recoger un
cambio de configuracion; `wsl --shutdown` fuerza el reinicio.

## 4. Configurar tu usuario

El aprovisionamiento de usuario (paquetes, shell, entorno) lo gestiona
[xlnux/wsl-scripts](https://github.com/xlnux/wsl-scripts). Hasta entonces, un
usuario manual se crea asi, desde dentro de la distribucion (como root):

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
para Windows 11. Tras editarlo, ejecuta `wsl --shutdown`.

## Solucion de problemas

- `wsl --import` falla: verifica el checksum del tarball primero
  (`sha256sum`), asegurate de que la carpeta destino no contenga ya una
  distribucion registrada con el mismo nombre y ejecuta el comando desde una
  consola elevada si Windows bloquea la operacion de ficheros.
- La instancia arranca pero falta `systemd`: confirma que `wsl --version` es
  reciente (0.67.6+), que `/etc/wsl.conf` contiene `[boot] systemd=true` y
  reinicia con `wsl --shutdown`.
- Errores de usuario por defecto: WSL se niega a iniciar una sesion con un
  usuario inexistente. Manten `default=root` o apuntalo a un usuario que hayas
  creado.
- `pacman` se queja de las claves tras importar: ejecuta
  `pacman-key --init && pacman-key --populate archlinux` como root dentro de la
  distribucion.
