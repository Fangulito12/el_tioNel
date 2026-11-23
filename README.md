# el_tioNel v3.1

Panel de administración para VPS: usuarios HWID/SSH con vencimiento, BHTTP (motor en C), V2Ray/Xray Reality, BADVPN-UDPGW y **Hysteria v1** como transporte UDP/QUIC hacia el SSH del VPS.

## Instalación

```bash
bash install_el_tioNel.sh      # la primera vez instala el panel y lo abre
el_tioNel                      # después, desde cualquier carpeta
```

## Comandos

| Comando | Qué hace |
|---|---|
| `el_tioNel` | Abre el panel |
| `el_tioNel status` | Muestra el estado y sale |
| `el_tioNel users` | Menú de usuarios HWID/SSH |
| `el_tioNel hysteria` | Menú de Hysteria v1 |
| `el_tioNel hysteria-check` | **(nuevo)** Diagnóstico completo de Hysteria v1 |
| `el_tioNel udpgw` | Menú de BADVPN-UDPGW |
| `el_tioNel expire` | Borra usuarios vencidos (lo usa el cron diario) |
| `el_tioNel cleanup` | Limpia RAM/cache/logs viejos |
| `el_tioNel bhttp ...` / `xray ...` | Atajos a los administradores |

## Hysteria v1 (menú `el_tioNel hysteria`)

| Opción | |
|---|---|
| 1–9 | Instalar, ver datos, puerto, OBFS/contraseña, autenticación, rango (salto de puertos), reiniciar, detener, logs |
| **10** | **Diagnóstico completo** (servicio, puerto, config, certificado, SSH destino, firewall/NAT, kernel, logs) |
| **11** | **Puertos extra**: redirige todo el UDP de 443, 53, 123, 4500… (los que quieras, máx. 8) al puerto de Hysteria |
| **12** | **Ajuste de red UDP**: `rmem_max`/`wmem_max` a 64 MB y `netdev_max_backlog` a 65536. Reversible; nunca baja un valor que ya era mayor |
| 13 | Desinstalar |

> Cambió la numeración: ahora **Desinstalar es la 13** (antes era la 10), igual que en los demás menús.

### VPS sin acceso a GitHub

Baja el binario a mano y apúntalo con una variable de entorno:

```bash
TIONEL_HV_BIN=/ruta/hysteria-linux-amd64 el_tioNel hysteria
```

Se comprueba que sea un ELF real, pero **no** se compara contra `hashes.txt`; el panel muestra el SHA256 para que lo verifiques tú.

### Seguridad (se mantiene)

- Binario descargado solo de GitHub oficial y **verificado por SHA256**.
- El servicio corre con un usuario sin privilegios y, por iptables, **solo puede llegar al SSH local** (no es un proxy abierto). `disable_udp: true`.
- Rechaza `crisdev` como OBFS/contraseña (es público).

## Cambios de la 3.1

**Errores corregidos**
- *Monitor de usuarios conectados*: si algún usuario no tenía conexiones, `pgrep -c` + `|| echo 0` imprimía `0` dos veces, la suma fallaba con "syntax error in expression" y **el panel se cerraba**.
- *Desinstalar todo* dejaba el autoinicio en `/root/.bashrc` (cada login por SSH daba `command not found`) y el cron del limpiador.
- Doble `0` cosmético en `xray status`.
- *Reiniciar* ahora actualiza el puerto SSH permitido por el firewall del servicio; antes, si cambiabas el puerto de sshd, Hysteria dejaba de llegar al SSH sin avisar.

**Agregado** (a partir de comparar con UDP_CRIS)
- Diagnóstico de Hysteria (equivalente a `check_udp.sh`, adaptado a este panel).
- Puertos extra 443/53/123/4500.
- Ajuste de red UDP con buffers de 64 MB.
- `OOMScoreAdjust=-100` en el servicio.
- Sesiones SSH tuneladas por Hysteria en *Conexiones activas*.
- Instalación con binario local (`TIONEL_HV_BIN`).

**No se copió de UDP_CRIS** (a propósito)
- Contraseña/OBFS por defecto `crisdev` y usuarios `root:`/`admin:`/`cris:` autorizados.
- `disable_udp: false` (deja el servidor como proxy abierto) y salida libre a internet.
- Espejos de descarga (ghproxy, kkgithub…) sin verificar hash.
- `recv_window` e `idle_timeout` en el servidor: en Hysteria v1 son opciones de **cliente**; el servidor usa `recv_window_conn` y `recv_window_client`.
- `iptables-persistent`: este panel reaplica sus reglas al arrancar el servicio.

## Archivos

- `install_el_tioNel.sh` — panel completo (incluye los administradores BHTTP y Xray embebidos).
- `tionel_bhttp.c` — motor BHTTP en C (idéntico al embebido en el instalador; compila sin avisos con `-Wall -Wextra`).
