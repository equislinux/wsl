# Arquitectura

Este documento explica como se ensambla la experiencia de X Linux en WSL entre
los repositorios de la organizacion [xlnux](https://github.com/xlnux) y como
cada pieza se corresponde con la documentacion oficial de WSL
(https://learn.microsoft.com/windows/wsl). Es la contrapartida de
`docs/architecture.md` del repositorio `xlnux/wsl-scripts`, vista desde el lado
de la distro/importacion.

## Flujo completo

X Linux para WSL es headless (solo terminal). Dos repositorios mas el host
Windows producen una distribucion corriendo y aprovisionada:

```
  xlnux/wsl                  xlnux/wsl            xlnux/wsl-scripts
  (host Arch)                (host Windows)       (dentro de la distro)
  ----------------           ----------------     ----------------
  1. build-rootfs.sh         2. install.ps1       3. install.sh (root)
     pacstrap de un rootfs      wsl --import         fase de sistema:
     Arch minimo, con un         --version 2          locale, keymap,
     /etc/wsl.conf inicial       (WSL 2)              zona horaria,
     (systemd activo, [user]     wsl --set-default    herramientas,
     default=root, [time])                            usuario con sudo;
                                                      fija [user] default
                                  4. exit, relanza       5. install.sh (usuario)
                                                                  fase de usuario:
        out/x-wsl-rootfs.tar.gz                        shell, env, carpetas
```

`wsl` es el repositorio de la *distro*: produce el rootfs importable y aloja
el importador del lado Windows. `wsl-scripts` es el repositorio del *setup*:
corre dentro de la distribucion importada y configura el sistema y el usuario.
Cada repositorio es independiente, con su propio origin y publicacion en
`main`.

## Estructura del repositorio

| Fichero                 | Funcion                                                  |
|-------------------------|----------------------------------------------------------|
| `build-rootfs.sh`       | Genera `<name>-wsl-rootfs.tar.gz` con pacstrap en Arch.  |
| `install.ps1`           | Importador Windows: comprueba WSL, importa como WSL 2, fija default, imprime guia de `.wslconfig`. |
| `templates/wsl.conf`    | Config por distro incluida en el rootfs como `/etc/wsl.conf`. |
| `templates/.wslconfig`  | Ejemplo de config global WSL 2 del host (nunca obligatorio). |
| `docs/en|es/`           | Guias de arquitectura e importacion/uso.                 |
| `out/`                  | Artefactos de build (git-ignored).                       |

## Correspondencia con la documentacion oficial de WSL

El rootfs incluye `/etc/wsl.conf` (generado desde `templates/wsl.conf`) para
que una distribucion recien importada se comporte como un sistema moderno
gestionado por systemd. Cada clave usada se corresponde con la referencia
oficial de ajustes (https://learn.microsoft.com/en-us/windows/wsl/wsl-config):

| Ajuste en `/etc/wsl.conf`          | Seccion / clave oficial              | Notas |
|------------------------------------|--------------------------------------|-------|
| `[boot] systemd=true`              | [Systemd support](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#systemd-support) | Requiere la build de WSL de Microsoft Store y Windows 11 (o Server 2022). |
| `[user] default=root` inicial      | [User settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#user-settings) | Las distribuciones importadas arrancan como root hasta fijar aqui un usuario real. `wsl-scripts` lo cambia al usuario creado. |
| `[interop] enabled / appendWindowsPath` | [Interop settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#interop-settings) | Mantiene la interop con Windows (`.exe`, PATH de Windows). |
| `[network] generateHosts / generateResolvConf` | [Network settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#network-settings) | WSL gestiona `/etc/hosts` y `/etc/resolv.conf`. |
| `[time] useWindowsTimezone=true`   | [Time settings](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#time-settings) | El reloj y la zona horaria de la instancia siguen a Windows. |

El `templates/.wslconfig` del lado host documenta los ajustes globales de la
VM WSL 2 (`memory`, `processors`, `guiApplications=false` para una distro
headless, y las claves `[experimental]` `autoMemoryReclaim` / `sparseVhd`),
todas descritas en los
[ajustes de .wslconfig](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#wslconfig).
WSL no tiene `.wslconfig` por defecto; hay que crearlo en `%UserProfile%`, por
eso `install.ps1` solo imprime guia y nunca sobrescribe uno existente. Tras
editar cualquiera de los dos ficheros, WSL debe reiniciarse para recoger el
cambio (la "regla de los 8 segundos"); `wsl --shutdown` lo fuerza.

## Por que importa el usuario por defecto

WSL inicia la sesion como el usuario indicado por `[user] default` en
`/etc/wsl.conf`. Para las distribuciones de la Store ese valor es el usuario
del primer arranque; para una distribucion **importada** no hay asistente de
primer arranque ni launcher de Windows, asi que:

- el valor debe existir ya en la distribucion, o WSL se niega a arrancar (por
  eso el rootfs trae `default=root`);
- solo se puede cambiar via `/etc/wsl.conf`; el comando de launcher
  `config --default-user` **no** funciona con distribuciones importadas (ver
  "Change the default user for a distribution" en los
  [comandos basicos de WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)).

`build-rootfs.sh` mantiene `default=root` a proposito: una importacion nueva
debe arrancar. La fase de sistema de `wsl-scripts` crea despues un usuario real
y reescribe solo el valor `[user] default`.

## Semantica de importacion

`install.ps1` usa el comando oficial de importacion actual:

```
wsl --import <Nombre> <UbicacionInstalacion> <Fichero> --version 2
```

`--version 2` fija la distribucion nueva a WSL 2 sin depender del default de la
maquina. `<UbicacionInstalacion>` es una carpeta de Windows que albergara el
VHD de la distribucion (`ext4.vhdx`); el importador usa por defecto una ruta
por usuario para no requerir permisos de administrador. Los pasos equivalentes
de `install.ps1` son los comandos manuales de `docs/en/import.md`. En caso de
exito ejecuta `wsl --set-default <Nombre>` (opcional) e imprime los siguientes
pasos para el setup de `xlnux/wsl-scripts`.

## Notas de build

`build-rootfs.sh` corre en Arch y produce un tar plano propiedad de root (sin
ACLs, sin xattrs, owners numericos). WSL aporta su propio kernel y su red, asi
que los paquetes `linux`, `linux-firmware`, `networkmanager` y `openssh` se
excluyen a proposito. El resultado es un sistema headless que arranca con
systemd al importarse; el aprovisionamiento de usuario queda en manos de
`xlnux/wsl-scripts`.

## Modelo de ejecucion

- `build-rootfs.sh` respeta `X_DRY=1` (imprime el plan sin tocar el sistema; no
  requiere root) y por lo demas esta pensado para ejecutarse con root en Arch.
- Ni el build ni la importacion dependen de infraestructura externa mas alla de
  los mirrors de Arch y los canales de distribucion online de WSL.

Ver `docs/en/import.md` para el paseo paso a paso y los requisitos.
