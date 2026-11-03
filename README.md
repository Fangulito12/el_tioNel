# el_tioNel

Panel de administración de VPS: usuarios HWID/SSH, BHTTP, V2Ray (VLESS Reality), BADVPN-UDPGW y Hysteria2.

## Instalación

Conéctate a tu VPS por SSH como root y corre:

```bash
wget -O el_tioNel-bin https://raw.githubusercontent.com/Fangulito12/el_tioNel/main/el_tioNel-bin
wget -O instalar.sh https://raw.githubusercontent.com/Fangulito12/el_tioNel/main/instalar.sh
chmod +x el_tioNel-bin instalar.sh
sudo bash instalar.sh
el_tioNel
```

Eso instala el panel en `/usr/local/sbin/el_tioNel-panel` y crea el comando `el_tioNel`, disponible desde cualquier carpeta.

## Requisitos

- VPS con Linux x86_64 (Ubuntu/Debian recomendado).
- Acceso root por SSH.

## Uso

Una vez instalado, simplemente escribe en cualquier momento:

```bash
el_tioNel
```

Desde el menú principal puedes:

- **Administrar usuarios (HWID/SSH)** — crear, renovar, bloquear y eliminar cuentas.
- **Configuración de protocolos** — BHTTP, V2Ray/Xray Reality, BADVPN-UDPGW, estado de Hysteria2.
- **Herramientas extras** — ajuste de red BBR, firewall, conexiones activas, limpiador automático de RAM/logs, y autoinicio del panel al conectar por SSH.

## Notas

- El binario (`el_tioNel-bin`) está compilado para no poder editarse ni leerse como texto.
- Si tu VPS usa otra arquitectura (por ejemplo ARM), este binario no va a funcionar; hay que compilar una versión aparte para esa arquitectura.
- Cada actualización del panel requiere volver a descargar `el_tioNel-bin` y correr `instalar.sh` de nuevo.
