#!/usr/bin/env bash
# el_tioNel - panel de administracion de VPS: usuarios HWID/SSH, BHTTP, V2Ray (VLESS Reality), BADVPN-UDPGW y estado de Hysteria2.
# Uso:  bash install_el_tioNel.sh        (la primera vez: instala el panel y lo abre)
#       el_tioNel                         (despues, desde cualquier carpeta)
# ===== FIRMA_EL_TIONEL_INICIO =====
# Panel: el_tioNel
# Creado por: el_tioNel
# No modificar ni borrar este bloque: se usa para comprobar que el panel
# no fue alterado (por ejemplo, para cambiarle el nombre).
# ===== FIRMA_EL_TIONEL_FIN =====

set -u

BRAND="el_tioNel"
PANEL_VERSION="3.0"
SIGNATURE_HASH="4dd04f82206489e290924281267bef53fec179fff49f13c453132c4c2a166b5c"
verify_signature(){
  local src hash
  src="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")"
  [ -r "$src" ] || return 0   # no se pudo leer el propio archivo (p.ej. ya compilado): no bloquea
  local s e
  s="$(grep -n -m1 '^# ===== FIRMA_EL_TIONEL_INICIO =====$' "$src" 2>/dev/null | cut -d: -f1)"
  e="$(grep -n -m1 '^# ===== FIRMA_EL_TIONEL_FIN =====$' "$src" 2>/dev/null | cut -d: -f1)"
  [ -n "$s" ] && [ -n "$e" ] && [ "$e" -ge "$s" ] || { printf '\033[1;31m✘\033[0m %s\n' "El panel $BRAND fue modificado (falta la firma). No se abre." >&2; exit 1; }
  hash="$(sed -n "${s},${e}p" "$src" 2>/dev/null | sha256sum | cut -d' ' -f1)"
  if [ "$hash" != "$SIGNATURE_HASH" ]; then
    printf '\033[1;31m✘\033[0m %s\n' "El panel $BRAND fue modificado (firma invalida). No se abre." >&2
    exit 1
  fi
}
ROOT="${TIONEL_ROOT:-}"                    # solo para pruebas
SBIN="$ROOT/usr/local/sbin"; UBIN="$ROOT/usr/local/bin"
PANEL_DEST="$SBIN/${BRAND}-panel";        PANEL_LINK="$UBIN/$BRAND"
BH_MGR="$SBIN/${BRAND}-bhttp-manager";    BH_LINK="$UBIN/${BRAND}-bhttp"
XR_MGR="$SBIN/${BRAND}-xray-manager";     XR_LINK="$UBIN/${BRAND}-xray"
BH_APP="$ROOT/opt/${BRAND}-bhttp/${BRAND}-bhttp-server.py"
BH_PORTS="$ROOT/etc/${BRAND}-bhttp/ports"
BH_TUNE="$ROOT/etc/sysctl.d/99-${BRAND}-bhttp.conf"
XR_BIN="$ROOT/opt/${BRAND}-xray/${BRAND}-xray"
XR_STATE="$ROOT/etc/${BRAND}-xray/state"

# ---- aspecto: UTF-8 si la terminal lo soporta, ASCII si no
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1;; *) UTF=0;; esac
[ -n "${TIONEL_ASCII:-}" ] && UTF=0
if [ -t 1 ] || [ -n "${TIONEL_COLOR:-}" ]; then
  C_B='\033[1;36m'; C_G='\033[1;32m'; C_R='\033[1;31m'; C_Y='\033[1;33m'; C_D='\033[2m'; C_O='\033[0m'
else C_B=''; C_G=''; C_R=''; C_Y=''; C_D=''; C_O=''; fi
if [ "$UTF" -eq 1 ]; then
  TL='╔'; TR='╗'; BL='╚'; BRR='╝'; HZ='═'; VT='║'; DOT='●'; CIR='○'; SEPC='─'
else TL='+'; TR='+'; BL='+'; BRR='+'; HZ='='; VT='|'; DOT='*'; CIR='o'; SEPC='-'; fi
rep_char(){ local i out=""; for ((i = 0; i < $2; i++)); do out+="$1"; done; printf '%s' "$out"; }   # repite un caracter (tambien de varios bytes)
ok(){ printf '%b✔%b %s\n' "$C_G" "$C_O" "$*"; }
info(){ printf '%bℹ%b %s\n' "$C_B" "$C_O" "$*"; }
warn(){ printf '%b⚠%b %s\n' "$C_Y" "$C_O" "$*"; }
fail(){ printf '%b✘%b %s\n' "$C_R" "$C_O" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
need_root(){ [ -n "${TIONEL_TEST:-}" ] && return 0; [ "$(id -u)" -eq 0 ] || { fail "Ejecuta como root."; exit 1; }; }
ask(){ local __v="$1"; IFS= read -r -p "$2" "$__v" || eval "$__v=''"; }
pause(){ [ -t 0 ] || return 0; echo; local _; ask _ "Presiona ENTER para continuar..."; }
confirm_word(){ [ -n "${TIONEL_YES:-}" ] && return 0; local c; ask c "$2 Escribe $1 para confirmar: "; [ "$c" = "$1" ]; }
listening(){ ss -lnt 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {f=1} END{exit !f}'; }

# ---- los administradores van dentro de este mismo archivo
emit_bhttp_manager(){
cat <<'EMBED_BHTTP_MANAGER_EOF'
#!/usr/bin/env bash
# el_tioNel BHTTP - administrador (lo usa el panel "el_tioNel", pero tambien funciona solo).
# Uso:  el_tioNel-bhttp                (abre el menu)
#       el_tioNel-bhttp install --port 8080
set -u

# ---- Nombre que se ve en el VPS (servicio, carpetas, comando, procesos). ----
# Si algun dia quieres otro nombre, cambia SOLO esta linea ANTES de instalar.
BRAND="el_tioNel"
NAME="${BRAND}-bhttp"
CMD="$NAME"

MANAGER_VERSION="1.3"
ROOT="${BHTTP_ROOT:-}"                       # solo para pruebas; en uso normal queda vacio
APP_DIR="$ROOT/opt/$NAME"
SERVER="$APP_DIR/${NAME}-server.py"
CSRC="$APP_DIR/${NAME}-fast.c"          # motor en C (se compila en este VPS)
CBIN="$APP_DIR/${NAME}-fast"
LAUNCHER="$ROOT/usr/local/bin/${NAME}-server"   # enlace a python3: asi el proceso se ve con tu nombre
CONF_DIR="$ROOT/etc/$NAME"
CONFIG="$CONF_DIR/config"
PORTS_FILE="$CONF_DIR/ports"
FW_FILE="$CONF_DIR/firewall-added"
SYSCTL_PREV="$CONF_DIR/sysctl.prev"
TLS_DIR="$CONF_DIR/tls"
SYSCTL_FILE="$ROOT/etc/sysctl.d/99-${NAME}.conf"
UNIT_FILE="$ROOT/etc/systemd/system/${NAME}@.service"
SELF_DEST="$ROOT/usr/local/sbin/${NAME}-manager"
BIN_LINK="$ROOT/usr/local/bin/$CMD"
CFG_KEYS="BACKEND POLL_WAIT_MS MAX_SESSIONS MAX_PER_IP IDLE TLS_ARGS ENGINE"

if [ -t 1 ]; then C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_INF='\033[1;36m'; C_WRN='\033[1;33m'; C_OFF='\033[0m'
else C_OK=''; C_ERR=''; C_INF=''; C_WRN=''; C_OFF=''; fi
# ---- diseno (igual que el panel el_tioNel)
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF=1;; *) UI_UTF=0;; esac
if [ "$UI_UTF" -eq 1 ]; then HZ='═'; else HZ='='; fi
if [ -t 1 ]; then RD='\033[1;31m'; WH='\033[1;37m'; GY='\033[0;37m'; OR='\033[38;5;208m'; GN='\033[1;32m'; BGR='\033[41;1;37m'
else RD=''; WH=''; GY=''; OR=''; GN=''; BGR=''; fi
W=54
calc_w(){ local c; c="$(tput cols 2>/dev/null || echo 54)"; [[ "$c" =~ ^[0-9]+$ ]] || c=54
  [ "$c" -gt 54 ] && c=54; [ "$c" -lt 40 ] && c=40; W="$c"; }
rep_char(){ local i out=""; for ((i = 0; i < $2; i++)); do out+="$1"; done; printf '%s' "$out"; }
hl(){ printf '%b%s%b\n' "$RD" "$(rep_char "$HZ" "$W")" "$C_OFF"; }
dash(){ printf '%b%s%b\n' "$RD" "$(rep_char "-" "$W")" "$C_OFF"; }
title(){ local t="$1" pad; pad=$(( (W - ${#t}) / 2 )); [ "$pad" -lt 0 ] && pad=0
  hl; printf '%*s%b%s%b\n' "$pad" "" "$GY" "$t" "$C_OFF"; hl; }
item(){ local col="${3:-$WH}"; printf ' %b[%s]%b>%b %b%s%b\n' "$GY" "$1" "$RD" "$C_OFF" "$col" "$2" "$C_OFF"; }
tag(){ case "$1" in on) printf '%b%s%b' "$GN" "[ON]" "$C_OFF";; off) printf '%b%s%b' "$RD" "[OFF]" "$C_OFF";; *) printf '%b%s%b' "$GY" "[--]" "$C_OFF";; esac; }
line(){ printf ' %b%-15s%b %s\n' "$GY" "$1" "$WH" "$2"; printf '%b' "$C_OFF"; }
back(){ hl; printf ' %b[0]%b %b %s %b\n' "$GY" "$C_OFF" "$BGR" "${1:-Volver}" "$C_OFF"; hl; }
ask_op(){ ask "$1" "$(printf '\n%b Ingresa una Opcion: %b' "$GY" "$C_OFF")"; }
ok(){ printf '%b✔%b %s\n' "$C_OK" "$C_OFF" "$*"; }
info(){ printf '%bℹ%b %s\n' "$C_INF" "$C_OFF" "$*"; }
warn(){ printf '%b⚠%b %s\n' "$C_WRN" "$C_OFF" "$*"; }
fail(){ printf '%b✘%b %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
need_root(){
  [ -n "${BHTTP_TEST:-}" ] && return 0
  [ "$(id -u)" -eq 0 ] || { fail "Ejecuta como root (sudo)."; exit 1; }
}
ask(){ local __v="$1"; IFS= read -r -p "$2" "$__v" || eval "$__v=''"; }
pause(){ [ -t 0 ] || return 0; echo; local _; ask _ "Presiona ENTER para continuar..."; }
confirm_word(){            # confirm_word PALABRA "mensaje"
  [ -n "${BHTTP_YES:-}" ] && return 0
  local c; ask c "$2 Escribe $1 para confirmar: "; [ "$c" = "$1" ]
}
valid_port(){ [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_num(){ [[ "${2:-}" =~ ^[0-9]+$ ]] && [ "$2" -ge "$1" ] && [ "$2" -le "$3" ]; }   # valid_num min valor max

# ---------------------------------------------------------------- configuracion
mem_mb(){ awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 1024; }
auto_sessions(){                 # techo de sesiones segun la RAM del VPS
  local m; m="$(mem_mb)"; [[ "$m" =~ ^[0-9]+$ ]] || m=1024
  if   [ "$m" -lt 768 ];  then echo 512
  elif [ "$m" -lt 1536 ]; then echo 1024
  elif [ "$m" -lt 3072 ]; then echo 2048
  elif [ "$m" -lt 6144 ]; then echo 4096
  else echo 8192; fi
}
cfg_default(){
  case "$1" in
    BACKEND) echo "127.0.0.1:22";; POLL_WAIT_MS) echo 800;; MAX_SESSIONS) auto_sessions;;
    MAX_PER_IP) echo 256;; IDLE) echo 120;; ENGINE) echo c;;
  esac
}
cfg_upgrade_limits(){            # sube los limites viejos por defecto (1024 / 64) sin tocar los que tu cambiaste
  local auto cur; auto="$(auto_sessions)"
  cur="$(cfg_get MAX_SESSIONS)"; [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
  if [ "$cur" -eq 1024 ] && [ "$auto" -gt 1024 ]; then cfg_set MAX_SESSIONS "$auto"; fi
  cur="$(cfg_get MAX_PER_IP)"; [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
  if [ "$cur" -eq 64 ]; then cfg_set MAX_PER_IP 256; fi
}
cfg_get(){
  local v; v="$(grep -m1 "^$1=" "$CONFIG" 2>/dev/null | cut -d= -f2-)"
  if [ -n "$v" ]; then printf '%s' "$v"; else cfg_default "$1"; fi
}
cfg_set(){
  local k="$1" v="$2" key out=""
  for key in $CFG_KEYS; do
    if [ "$key" = "$k" ]; then out+="$key=$v"$'\n'; else out+="$key=$(cfg_get "$key")"$'\n'; fi
  done
  mkdir -p "$CONF_DIR"; printf '%s' "$out" > "$CONFIG"; chmod 644 "$CONFIG"
}
cfg_init(){ [ -f "$CONFIG" ] || cfg_set BACKEND "$(cfg_default BACKEND)"; }
backend_port(){ cfg_get BACKEND | awk -F: '{print $NF}'; }

# ---------------------------------------------------------------- puertos
ports_list(){ [ -f "$PORTS_FILE" ] && grep -E '^[0-9]+$' "$PORTS_FILE" | sort -n -u || true; }
ports_has(){ ports_list | grep -qx "$1"; }
ports_add(){ mkdir -p "$CONF_DIR"; ports_has "$1" || echo "$1" >> "$PORTS_FILE"; }
ports_del(){ [ -f "$PORTS_FILE" ] || return 0; grep -vx "$1" "$PORTS_FILE" > "$PORTS_FILE.tmp" || true; mv "$PORTS_FILE.tmp" "$PORTS_FILE"; }
unit_name(){ echo "${NAME}@$1.service"; }
listening(){ ss -lnt 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {f=1} END{exit !f}'; }
conn_count(){ ss -tan 2>/dev/null | awk -v p=":$1" '$1=="ESTAB" && $4 ~ p"$" {n++} END{print n+0}'; }

# ---------------------------------------------------------------- firewall (solo toca lo que el mismo abrio)
ufw_active(){ have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; }
firewalld_active(){ have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; }
fw_open(){
  local p="$1"
  mkdir -p "$CONF_DIR"
  if ufw_active; then
    if ufw status 2>/dev/null | grep -Eq "(^|[[:space:]])${p}/tcp([[:space:]]|$)"; then
      info "ufw: el puerto $p/tcp ya estaba permitido."
    else
      ufw allow "${p}/tcp" >/dev/null && echo "ufw $p" >> "$FW_FILE" && ok "ufw: puerto $p/tcp abierto."
    fi
  elif firewalld_active; then
    if firewall-cmd --query-port="${p}/tcp" >/dev/null 2>&1; then
      info "firewalld: el puerto $p/tcp ya estaba permitido."
    else
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null && firewall-cmd --reload >/dev/null \
        && echo "firewalld $p" >> "$FW_FILE" && ok "firewalld: puerto $p/tcp abierto."
    fi
  else
    info "No detecte ufw ni firewalld activos. Si usas iptables a mano o el firewall del proveedor, abre TCP $p."
  fi
}
fw_close(){
  local p="$1"
  [ -f "$FW_FILE" ] || return 0
  if grep -qx "ufw $p" "$FW_FILE" && have ufw; then ufw delete allow "${p}/tcp" >/dev/null 2>&1; ok "ufw: puerto $p/tcp cerrado."; fi
  if grep -qx "firewalld $p" "$FW_FILE" && have firewall-cmd; then
    firewall-cmd --permanent --remove-port="${p}/tcp" >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1
    ok "firewalld: puerto $p/tcp cerrado."
  fi
  grep -vxE "(ufw|firewalld) $p" "$FW_FILE" > "$FW_FILE.tmp" || true; mv "$FW_FILE.tmp" "$FW_FILE"
}

# ---------------------------------------------------------------- instalacion
ensure_python(){
  local okpy='import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'
  if have python3 && python3 -c "$okpy" 2>/dev/null; then return 0; fi
  info "Instalando python3..."
  if have apt-get; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 >/dev/null 2>&1 \
      || { apt-get update -y >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y python3 >/dev/null 2>&1; }
  elif have dnf; then dnf install -y python3 >/dev/null 2>&1
  elif have yum; then yum install -y python3 >/dev/null 2>&1
  fi
  have python3 && python3 -c "$okpy" 2>/dev/null || { fail "Necesito Python 3.8 o mas nuevo y no pude instalarlo."; return 1; }
}
ensure_uvloop(){                 # opcional: si no se puede, el servidor sigue con el bucle normal de Python
  python3 -c 'import uvloop' 2>/dev/null && return 0
  have apt-get || return 0
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3-uvloop >/dev/null 2>&1 || true
  if python3 -c 'import uvloop' 2>/dev/null; then ok "uvloop instalado (bucle de eventos mas rapido)."
  else info "uvloop no disponible en este sistema: se usa el bucle normal de Python (funciona igual)."; fi
}

write_server(){
  mkdir -p "$APP_DIR"
  [ -f "$SERVER" ] && cp -a "$SERVER" "$SERVER.prev"
  cat > "$SERVER" <<'BHTTP_SERVER_PY_EOF'
#!/usr/bin/env python3
"""Servidor BHTTP propio (lado VPS) para la app Conecta. Version 2.

Recibe las peticiones BHTTP de la app y las reenvia al SSH del propio VPS (127.0.0.1:22 por defecto):

    app --BHTTP--> este script --TCP--> sshd

Sin dependencias: solo Python 3.8 o mas nuevo. Uso:

    python3 bhttp_server.py --port 8080 --backend 127.0.0.1:22
    python3 bhttp_server.py --probe 127.0.0.1:8080        # autoprueba de un servidor ya en marcha

Mejoras de la version 2 sobre la 1:
  * Espera corta de datos (--poll-wait-ms): si el SSH aun no tiene nada que enviar, el servidor
    aguarda un momento antes de responder vacio, asi la respuesta sale en cuanto llegan los datos
    en vez de esperar al siguiente sondeo de la app (baja la latencia).
  * Conexiones reutilizables: varias peticiones seguidas por la misma conexion TCP (la app actual
    abre una por peticion y sigue funcionando igual).
  * Keep-alive TCP en las conexiones de la app para limpiar enlaces muertos antes.
  * TLS opcional (--tls-cert y --tls-key): la app puede conectar con TLS y mandar el SNI que quiera.
    El servidor acepta cualquier SNI; la app puede fijar la huella SHA-256 del certificado.

IMPORTANTE sobre seguridad: el "cifrado" de BHTTP es solo ofuscacion (no usa ninguna clave secreta),
no protege nada por si mismo. La seguridad real es la de SSH, que va por dentro. Este servidor solo
reenvia al destino fijo que le indiques con --backend, asi que no sirve de proxy abierto.

Protocolo (lo que el cliente de la app espera):
  Peticion  : [modo:1][sid:16][seq:8][largo:4][datos]      (una peticion por conexion TCP)
  Respuesta : [estado:1][largo:4][cuerpo]
  Modos     : 0 sondeo, 1 subida, 2 bajada (solo en sondeo), 3 lote de bajada, 4 ack
  Estados   : 0 ok, 1 error, 2 datos
  Ofuscacion: XOR con SHA-256(sid | modo | seq | es_respuesta | n_bloque), bloques de 32 bytes.
"""
import argparse
import asyncio
import hashlib
import logging
import signal
import ssl
import struct
import time

MODE_PROBE, MODE_UPLOAD, MODE_DOWNLOAD, MODE_BATCH, MODE_ACK = 0, 1, 2, 3, 4
ST_OK, ST_ERR, ST_DATA = 0, 1, 2

HEADER = 29                      # 1 + 16 + 8 + 4
MAX_REQUEST = 1 << 20            # 1 MiB por peticion (el cliente manda como maximo 32 KiB)
MAX_PROBE_REPLY = 1 << 20
MAX_CHUNK = 65536
MAX_BATCH = 32
REQUEST_TIMEOUT = 15             # segundos para leer una peticion completa
KEEPALIVE_IDLE = 30              # segundos que una conexion reutilizada puede esperar la siguiente peticion
MAX_REQUESTS_PER_CONN = 2048
BACKLOG_MAX = 4 << 20            # bytes que se guardan del SSH antes de dejar de leerlo
UP_PENDING_MAX = 8 << 20         # bytes de subida fuera de orden que se aceptan guardar

log = logging.getLogger("bhttp")
_sha = hashlib.sha256
_CNT = [i.to_bytes(4, "big") for i in range(4096)]   # contadores de bloque ya calculados (hasta 128 KiB)


# ---------------------------------------------------------------- ofuscacion

def crypt(data: bytes, sid: bytes, mode: int, seq: int, is_response: bool) -> bytes:
    """XOR con un flujo derivado de SHA-256. Es simetrico: sirve para cifrar y descifrar."""
    n = len(data)
    if not n:
        return b""
    base = sid + bytes((mode,)) + seq.to_bytes(8, "big") + (b"\x01" if is_response else b"\x00")
    blocks = (n + 31) >> 5
    if blocks <= len(_CNT):
        ks = b"".join([_sha(base + c).digest() for c in _CNT[:blocks]])
    else:
        ks = b"".join([_sha(base + i.to_bytes(4, "big")).digest() for i in range(blocks)])
    if len(ks) != n:
        ks = ks[:n]
    return (int.from_bytes(data, "big") ^ int.from_bytes(ks, "big")).to_bytes(n, "big")


def reply(status: int, body: bytes = b"") -> bytes:
    return bytes([status]) + struct.pack(">I", len(body)) + body


# ---------------------------------------------------------------- sesion

class Session:
    """Una conexion SSH de la app (identificada por su sid de 16 bytes)."""

    def __init__(self, sid, reader, writer):
        self.sid = sid
        self.reader = reader
        self.writer = writer
        self.last = time.monotonic()
        self.closed = False         # el SSH del VPS cerro la conexion
        # subida: se escribe al SSH estrictamente en orden de seq
        self.next_up = 0
        self.up_pending = {}
        self.up_pending_bytes = 0
        # bajada: el flujo del SSH se reparte en "casillas" numeradas; la app las pide por ventanas
        self.backlog = bytearray()
        self.slots = {}             # casilla -> bytes (se guarda hasta que la app la confirma)
        self.filled = 0             # primera casilla aun sin asignar
        self.cond = asyncio.Condition()
        self.task = asyncio.ensure_future(self._pump())

    async def _pump(self):
        """Lee del SSH y guarda los bytes hasta que la app los pida."""
        try:
            while True:
                while len(self.backlog) >= BACKLOG_MAX:
                    await asyncio.sleep(0.02)
                data = await self.reader.read(65536)
                if not data:
                    break
                self.backlog += data
                await self._wake()
        except (ConnectionError, OSError, asyncio.CancelledError):
            pass
        finally:
            self.closed = True
            try:
                await self._wake()
            except Exception:
                pass

    async def _wake(self):
        async with self.cond:
            self.cond.notify_all()

    async def upload(self, seq: int, data: bytes) -> int:
        self.last = time.monotonic()
        if not data or seq < self.next_up:
            return ST_OK            # registro, o un reintento de algo ya entregado
        if seq not in self.up_pending:
            if self.up_pending_bytes + len(data) > UP_PENDING_MAX:
                return ST_ERR
            self.up_pending[seq] = data
            self.up_pending_bytes += len(data)
        wrote = False
        while self.next_up in self.up_pending:
            chunk = self.up_pending.pop(self.next_up)
            self.up_pending_bytes -= len(chunk)
            self.next_up += 1
            self.writer.write(chunk)
            wrote = True
        if wrote:
            try:
                await self.writer.drain()
            except (ConnectionError, OSError):
                return ST_ERR
        return ST_OK

    async def batch(self, base: int, chunk: int, count: int, wait: float):
        """Devuelve las `count` casillas desde `base`.

        Los datos se asignan siempre a la primera casilla libre (en orden), igual que en la version 1.
        Si la ventana aun no esta asignada y no hay datos pendientes, espera hasta `wait` segundos a que
        lleguen (o a que otra peticion asigne esta ventana) en vez de responder vacio al instante.
        """
        self.last = time.monotonic()
        end = base + count
        if wait > 0 and end > self.filled and not self.backlog and not self.closed:
            async with self.cond:
                try:
                    await asyncio.wait_for(self.cond.wait_for(
                        lambda: self.filled >= end or self.closed or len(self.backlog) > 0), wait)
                except asyncio.TimeoutError:
                    pass
            self.last = time.monotonic()
        changed = False
        while self.filled < end:
            take = min(chunk, len(self.backlog))
            self.slots[self.filled] = bytes(self.backlog[:take])
            del self.backlog[:take]
            self.filled += 1
            changed = True
        if changed:
            await self._wake()
        return [self.slots.get(base + i, b"") for i in range(count)]

    def ack(self, seq: int):
        self.last = time.monotonic()
        for k in [k for k in self.slots if k <= seq]:
            del self.slots[k]

    async def close(self):
        self.task.cancel()
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except Exception:
            pass


# ---------------------------------------------------------------- servidor

class Server:
    def __init__(self, backend, max_sessions, idle, max_per_ip, poll_wait=0.8):
        self.poll_wait = poll_wait
        self.backend = backend
        self.max_sessions = max_sessions
        self.idle = idle
        self.max_per_ip = max_per_ip
        self.sessions = {}
        self.creating = {}
        self.per_ip = {}

    async def get_session(self, sid, ip=None, create=False):
        s = self.sessions.get(sid)
        if s or not create:
            return s
        fut = self.creating.get(sid)
        if fut is None:
            if len(self.sessions) + len(self.creating) >= self.max_sessions:
                log.warning("limite de sesiones alcanzado")
                return None
            if self.per_ip.get(ip, 0) >= self.max_per_ip:
                log.warning("limite de sesiones por IP alcanzado")
                return None
            fut = asyncio.ensure_future(self._create(sid, ip))
            self.creating[sid] = fut
        try:
            return await fut
        finally:
            self.creating.pop(sid, None)

    async def _create(self, sid, ip):
        try:
            r, w = await asyncio.wait_for(asyncio.open_connection(*self.backend), 5)
        except (OSError, asyncio.TimeoutError) as e:
            log.warning("no se pudo conectar al destino: %s", e)
            return None
        s = Session(sid, r, w)
        s.ip = ip
        self.per_ip[ip] = self.per_ip.get(ip, 0) + 1
        self.sessions[sid] = s
        log.info("sesion abierta (%d activas)", len(self.sessions))
        return s

    async def drop(self, sid):
        s = self.sessions.pop(sid, None)
        if s:
            left = self.per_ip.get(s.ip, 1) - 1
            if left > 0:
                self.per_ip[s.ip] = left
            else:
                self.per_ip.pop(s.ip, None)
            await s.close()
            log.info("sesion cerrada (%d activas)", len(self.sessions))

    async def janitor(self):
        while True:
            await asyncio.sleep(min(15, max(1, self.idle // 2)))
            now = time.monotonic()
            for sid, s in list(self.sessions.items()):
                if now - s.last > self.idle:
                    await self.drop(sid)

    # ---- una peticion por conexion

    async def handle(self, reader, writer):
        try:
            sock = writer.get_extra_info("socket")
            if sock is not None:
                try:
                    import socket as _s
                    sock.setsockopt(_s.SOL_SOCKET, _s.SO_KEEPALIVE, 1)
                    for name, val in (("TCP_KEEPIDLE", 60), ("TCP_KEEPINTVL", 15), ("TCP_KEEPCNT", 4)):
                        if hasattr(_s, name):
                            sock.setsockopt(_s.IPPROTO_TCP, getattr(_s, name), val)
                except OSError:
                    pass
            peer = writer.get_extra_info("peername")
            ip = peer[0] if peer else None
            for n_req in range(MAX_REQUESTS_PER_CONN):
                # la primera peticion debe llegar enseguida; las siguientes pueden tardar mas
                wait = REQUEST_TIMEOUT if n_req == 0 else KEEPALIVE_IDLE
                head = await asyncio.wait_for(reader.readexactly(HEADER), wait)
                mode = head[0]
                sid = bytes(head[1:17])
                seq = int.from_bytes(head[17:25], "big")
                n = int.from_bytes(head[25:29], "big")
                if n > MAX_REQUEST:
                    writer.write(reply(ST_ERR))
                    await writer.drain()
                    return
                data = await asyncio.wait_for(reader.readexactly(n), REQUEST_TIMEOUT) if n else b""
                out = await self.dispatch(mode, sid, seq, data, ip)
                writer.write(out)
                await writer.drain()
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, OSError):
            pass
        except Exception:
            log.exception("error atendiendo una peticion")
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def dispatch(self, mode, sid, seq, data, ip=None) -> bytes:
        if mode == MODE_PROBE:
            return self.probe(sid, data)

        # Solo la subida (el registro de la app) puede abrir una sesion nueva; lote y ack
        # exigen una sesion existente. Asi la basura no gasta conexiones al destino.
        if mode == MODE_UPLOAD:
            s = await self.get_session(sid, ip, create=True)
            if s is None:
                return reply(ST_ERR)
            return reply(await s.upload(seq, crypt(data, sid, MODE_UPLOAD, seq, False)))

        if mode == MODE_BATCH:
            s = self.sessions.get(sid)
            req = crypt(data, sid, MODE_BATCH, seq, False)
            if s is None or len(req) < 6:
                return reply(ST_ERR)
            chunk = struct.unpack(">i", req[:4])[0]
            count = req[5]
            if not (1 <= chunk <= MAX_CHUNK) or not (1 <= count <= MAX_BATCH):
                return reply(ST_ERR)
            out = bytearray()
            for i, raw in enumerate(await s.batch(seq, chunk, count, self.poll_wait)):
                enc = crypt(raw, sid, MODE_BATCH, seq + i, True)
                out += reply(ST_DATA, struct.pack(">I", len(enc)) + enc)
            return bytes(out)

        if mode == MODE_ACK:
            s = self.sessions.get(sid)
            if s is None:
                return reply(ST_ERR)
            s.ack(seq)
            return reply(ST_OK)

        return reply(ST_ERR)

    @staticmethod
    def probe(sid, data) -> bytes:
        plain = crypt(data, sid, MODE_PROBE, 0, False)
        if len(plain) < 10 or plain[:4] != b"BHP1" or plain[4] != 1:
            return reply(ST_ERR)
        mode = plain[5]
        param = struct.unpack(">i", plain[6:10])[0]
        length = max(10, param) if mode == MODE_DOWNLOAD else 10
        if length > MAX_PROBE_REPLY:
            return reply(ST_ERR)
        body = bytearray(length)
        body[0:4] = b"BHP1"
        body[4] = 1
        body[5] = mode
        body[6:10] = struct.pack(">i", param)
        for i in range(10, length):
            body[i] = (i * 31) & 0xFF
        return reply(ST_OK, crypt(bytes(body), sid, MODE_PROBE, 0, True))


def probe_client(target: str, use_tls: bool = False) -> bool:
    """Autoprueba: hace el sondeo BHP1 igual que la app y comprueba la respuesta."""
    import os
    import socket
    host, _, port = target.rpartition(":")
    try:
        sid = os.urandom(16)
        plain = bytearray(10)
        plain[0:4] = b"BHP1"
        plain[4] = 1
        plain[5] = MODE_BATCH
        plain[6:10] = struct.pack(">i", 8)
        data = crypt(bytes(plain), sid, MODE_PROBE, 0, False)
        raw = socket.create_connection((host or "127.0.0.1", int(port)), timeout=5)
        if use_tls:
            cx = ssl.create_default_context()
            cx.check_hostname = False
            cx.verify_mode = ssl.CERT_NONE
            raw = cx.wrap_socket(raw, server_hostname="localhost")
        with raw as sk:
            sk.sendall(bytes([MODE_PROBE]) + sid + (0).to_bytes(8, "big") + struct.pack(">I", len(data)) + data)
            sk.settimeout(5)
            buf = b""
            while len(buf) < 5:
                chunk = sk.recv(5 - len(buf))
                if not chunk:
                    break
                buf += chunk
            if len(buf) < 5 or buf[0] != ST_OK:
                print("el servidor respondio con error o no respondio")
                return False
            n = struct.unpack(">I", buf[1:5])[0]
            body = b""
            while len(body) < n:
                chunk = sk.recv(n - len(body))
                if not chunk:
                    break
                body += chunk
        resp = crypt(body, sid, MODE_PROBE, 0, True)
        good = (len(resp) == 10 and resp[:4] == b"BHP1" and resp[4] == 1 and resp[5] == MODE_BATCH
                and struct.unpack(">i", resp[6:10])[0] == 8)
        print("sondeo BHP1: OK" if good else "sondeo BHP1: respuesta invalida")
        return good
    except (OSError, ssl.SSLError) as e:
        print("no se pudo conectar:", e)
        return False


async def main_async(args):
    host, _, port = args.backend.rpartition(":")
    srv = Server((host or "127.0.0.1", int(port)), args.max_sessions, args.idle, args.max_per_ip,
                 max(0, args.poll_wait_ms) / 1000.0)
    ctx = None
    if args.tls_cert or args.tls_key:
        if not (args.tls_cert and args.tls_key):
            raise SystemExit("--tls-cert y --tls-key se usan juntos")
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(args.tls_cert, args.tls_key)
        # acepta cualquier SNI (la app elige el dominio); solo lo anota en el modo detallado
        ctx.sni_callback = lambda sock, name, c: log.debug("SNI recibido: %s", name)
    server = await asyncio.start_server(srv.handle, args.listen, args.port, backlog=1024, ssl=ctx,
                                        ssl_handshake_timeout=REQUEST_TIMEOUT if ctx else None)
    asyncio.ensure_future(srv.janitor())
    log.info("BHTTP%s escuchando en %s:%d -> %s", " (TLS)" if ctx else "", args.listen, args.port, args.backend)

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass
    async with server:
        await stop.wait()
    for sid in list(srv.sessions):
        await srv.drop(sid)


def main():
    ap = argparse.ArgumentParser(description="Servidor BHTTP propio para la app Conecta")
    ap.add_argument("--listen", default="0.0.0.0", help="direccion donde escucha (por defecto 0.0.0.0)")
    ap.add_argument("--port", type=int, help="puerto TCP donde escucha la app")
    ap.add_argument("--probe", metavar="HOST:PUERTO", help="autoprueba: hace el sondeo BHP1 contra un servidor en marcha y sale")
    ap.add_argument("--tls", action="store_true", help="con --probe: usar TLS (para un servidor iniciado con --tls-cert)")
    ap.add_argument("--tls-cert", metavar="ARCHIVO", help="certificado (PEM) para atender con TLS")
    ap.add_argument("--tls-key", metavar="ARCHIVO", help="llave privada (PEM) del certificado")
    ap.add_argument("--poll-wait-ms", type=int, default=800,
                    help="milisegundos que espera datos antes de responder vacio (0 = no esperar; por defecto 800)")
    ap.add_argument("--backend", default="127.0.0.1:22", help="destino al que se reenvia (por defecto 127.0.0.1:22)")
    ap.add_argument("--max-sessions", type=int, default=128, help="sesiones simultaneas maximas")
    ap.add_argument("--max-per-ip", type=int, default=64, help="sesiones simultaneas maximas por IP de origen")
    ap.add_argument("--idle", type=int, default=120, help="segundos sin actividad para cerrar una sesion")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.probe:
        raise SystemExit(0 if probe_client(args.probe, args.tls) else 1)
    if not args.port:
        ap.error("falta --port")
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    try:                                   # uvloop (opcional): bucle de eventos mas rapido si esta instalado
        import uvloop
        uvloop.install()
    except Exception:
        pass
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
BHTTP_SERVER_PY_EOF
  chmod 755 "$APP_DIR"; chmod 644 "$SERVER"
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SERVER" || { fail "El archivo del servidor quedo danado."; return 1; }
}

# ---------------------------------------------------------------- motor C (rapido)
write_cengine_src(){
  mkdir -p "$APP_DIR"
  cat > "$CSRC" <<'BHTTP_C_SRC_EOF'
/*
 * el_tioNel BHTTP - motor en C (lado VPS). Mismo protocolo BHP1 que el servidor Python.
 *
 *   app --BHTTP--> este programa --TCP--> sshd (127.0.0.1:22 por defecto)
 *
 * Sin dependencias: solo libc y pthreads. No soporta TLS (para TLS se usa el servidor Python).
 *
 * Protocolo:
 *   Peticion  : [modo:1][sid:16][seq:8][largo:4][datos]
 *   Respuesta : [estado:1][largo:4][cuerpo]
 *   Modos     : 0 sondeo, 1 subida, 2 bajada (solo en sondeo), 3 lote de bajada, 4 ack
 *   Estados   : 0 ok, 1 error, 2 datos
 *   Ofuscacion: XOR con SHA-256(sid | modo | seq | es_respuesta | n_bloque), bloques de 32 bytes.
 *
 * Compilar:  gcc -O2 -pthread -o tionel-bhttp tionel_bhttp.c
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <malloc.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define VERSION "1.0"

#define MODE_PROBE 0
#define MODE_UPLOAD 1
#define MODE_DOWNLOAD 2
#define MODE_BATCH 3
#define MODE_ACK 4
#define ST_OK 0
#define ST_ERR 1
#define ST_DATA 2

#define HEADER 29
#define MAX_REQUEST (1u << 20)
#define MAX_PROBE_REPLY (1u << 20)
#define MAX_CHUNK 65536
#define MAX_BATCH 32
#define MAX_WINDOW_AHEAD 65536u /* casillas por delante de lo ya asignado (evita ventanas absurdas) */
#define REQUEST_TIMEOUT_MS 15000
#define KEEPALIVE_IDLE_MS 30000
#define MAX_REQUESTS_PER_CONN 2048
#define BACKLOG_MAX (4u << 20)
#define UP_PENDING_MAX (8u << 20)
#define THREAD_STACK (256 * 1024)
#define HASH_BUCKETS 8192

/* ------------------------------------------------------------------ utilidades */

static int g_verbose = 0;
static volatile sig_atomic_t g_stop = 0;
static void on_term(int sig) { (void)sig; g_stop = 1; }

static void logmsg(const char *lvl, const char *fmt, ...) {
    char ts[32];
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &tmv);
    fprintf(stderr, "%s %s ", ts, lvl);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

static int64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static inline uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static inline uint64_t be64(const uint8_t *p) { return ((uint64_t)be32(p) << 32) | be32(p + 4); }
static inline void put_be32(uint8_t *p, uint32_t v) {
    p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

/* ------------------------------------------------------------------ SHA-256 + ofuscacion */

static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
static const uint32_t IV256[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

/* Comprime UN bloque de 64 bytes (ya como 16 palabras) a partir del estado inicial. */
static void sha256_block(uint32_t st[8], const uint32_t w16[16]) {
    uint32_t W[64];
    int i;
    memcpy(W, w16, 64);
    for (i = 16; i < 64; i++) {
        uint32_t s0 = ROR(W[i - 15], 7) ^ ROR(W[i - 15], 18) ^ (W[i - 15] >> 3);
        uint32_t s1 = ROR(W[i - 2], 17) ^ ROR(W[i - 2], 19) ^ (W[i - 2] >> 10);
        W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }
    uint32_t a = st[0], b = st[1], c = st[2], d = st[3], e = st[4], f = st[5], g = st[6], h = st[7];
    for (i = 0; i < 64; i++) {
        uint32_t S1 = ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + K256[i] + W[i];
        uint32_t S0 = ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    st[0] += a; st[1] += b; st[2] += c; st[3] += d; st[4] += e; st[5] += f; st[6] += g; st[7] += h;
}

/*
 * Ofuscacion: XOR in-place con el flujo SHA-256(sid | modo | seq(8) | resp | contador(4)).
 * La entrada de cada bloque mide 30 bytes: cabe en un unico bloque SHA-256 (relleno fijo), y los bloques
 * son independientes entre si (solo cambia el contador), asi que se calculan 1, 4 u 8 a la vez (SIMD).
 */
static void crypt_prep(uint32_t w[16], uint32_t *w6hi, const uint8_t sid[16], unsigned mode, uint64_t seq, int resp) {
    uint8_t pre[26];
    int i;
    memcpy(pre, sid, 16);
    pre[16] = (uint8_t)mode;
    for (i = 0; i < 8; i++) pre[17 + i] = (uint8_t)(seq >> (56 - 8 * i));
    pre[25] = resp ? 1 : 0;
    for (i = 0; i < 6; i++) w[i] = be32(pre + 4 * i);
    *w6hi = ((uint32_t)pre[24] << 24) | ((uint32_t)pre[25] << 16);
    for (i = 8; i < 15; i++) w[i] = 0;
    w[15] = 240; /* 30 bytes = 240 bits */
}

static void ks_scalar(const uint32_t w0[16], uint32_t w6hi, uint32_t ctr, uint8_t ks[32]) {
    uint32_t w[16], st[8];
    int i;
    memcpy(w, w0, sizeof w);
    w[6] = w6hi | (ctr >> 16);
    w[7] = (ctr << 16) | 0x8000u;
    memcpy(st, IV256, sizeof st);
    sha256_block(st, w);
    for (i = 0; i < 8; i++) put_be32(ks + 4 * i, st[i]);
}

#ifndef NO_SIMD
typedef uint32_t v4u __attribute__((vector_size(16)));
#define VROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
/* SHA-256 de L bloques a la vez (uno por carril). Los carriles comparten todo salvo W[6] y W[7] (el contador). */
#define DEFINE_MB(NAME, V, L, ATTR)                                                                          \
    ATTR static void NAME(const uint32_t w[16], uint32_t w6hi, uint32_t ctr0, uint8_t *ks) {                \
        V W[64], zero = (V){0};                                                                              \
        int i, l, j;                                                                                         \
        for (i = 0; i < 16; i++) W[i] = zero + w[i];                                                         \
        {                                                                                                    \
            uint32_t a6[L], a7[L];                                                                           \
            for (l = 0; l < L; l++) {                                                                        \
                uint32_t c = ctr0 + (uint32_t)l;                                                             \
                a6[l] = w6hi | (c >> 16);                                                                    \
                a7[l] = (c << 16) | 0x8000u;                                                                 \
            }                                                                                                \
            memcpy(&W[6], a6, sizeof(V));                                                                    \
            memcpy(&W[7], a7, sizeof(V));                                                                    \
        }                                                                                                    \
        for (i = 16; i < 64; i++) {                                                                          \
            V x15 = W[i - 15], x2 = W[i - 2];                                                                \
            V s0 = VROR(x15, 7) ^ VROR(x15, 18) ^ (x15 >> 3);                                                \
            V s1 = VROR(x2, 17) ^ VROR(x2, 19) ^ (x2 >> 10);                                                 \
            W[i] = W[i - 16] + s0 + W[i - 7] + s1;                                                           \
        }                                                                                                    \
        V a = zero + IV256[0], b = zero + IV256[1], c = zero + IV256[2], d = zero + IV256[3];                \
        V e = zero + IV256[4], f = zero + IV256[5], g = zero + IV256[6], h = zero + IV256[7];                \
        for (i = 0; i < 64; i++) {                                                                           \
            V S1 = VROR(e, 6) ^ VROR(e, 11) ^ VROR(e, 25);                                                   \
            V ch = (e & f) ^ (~e & g);                                                                       \
            V t1 = h + S1 + ch + (zero + K256[i]) + W[i];                                                    \
            V S0 = VROR(a, 2) ^ VROR(a, 13) ^ VROR(a, 22);                                                   \
            V maj = (a & b) ^ (a & c) ^ (b & c);                                                             \
            V t2 = S0 + maj;                                                                                 \
            h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;                               \
        }                                                                                                    \
        V r[8] = {a + IV256[0], b + IV256[1], c + IV256[2], d + IV256[3],                                    \
                  e + IV256[4], f + IV256[5], g + IV256[6], h + IV256[7]};                                   \
        for (j = 0; j < 8; j++) {                                                                            \
            uint32_t t[L];                                                                                   \
            memcpy(t, &r[j], sizeof(V));                                                                     \
            for (l = 0; l < L; l++) put_be32(ks + 32 * l + 4 * j, t[l]);                                     \
        }                                                                                                    \
    }

DEFINE_MB(ks_x4, v4u, 4, )
#if defined(__x86_64__) && defined(__GNUC__)
typedef uint32_t v8u __attribute__((vector_size(32)));
DEFINE_MB(ks_x8, v8u, 8, __attribute__((target("avx2"))))
#define HAVE_X8 1
#endif
#endif /* NO_SIMD */

static int g_simd = 0; /* 0 = solo escalar, 1 = 4 bloques a la vez, 2 = 8 bloques a la vez (AVX2) */

static void xor_bytes(uint8_t *d, const uint8_t *k, size_t m) {
    size_t i = 0;
    for (; i + 8 <= m; i += 8) {
        uint64_t a, b;
        memcpy(&a, d + i, 8);
        memcpy(&b, k + i, 8);
        a ^= b;
        memcpy(d + i, &a, 8);
    }
    for (; i < m; i++) d[i] ^= k[i];
}

static void crypt_ex(uint8_t *d, size_t n, const uint8_t sid[16], unsigned mode, uint64_t seq, int resp, int level) {
    if (n == 0) return;
    uint32_t w[16], w6hi, ctr = 0;
    uint8_t ks[256];
    size_t off = 0;
    crypt_prep(w, &w6hi, sid, mode, seq, resp);
#if defined(HAVE_X8)
    if (level >= 2)
        while (n - off >= 256) { ks_x8(w, w6hi, ctr, ks); xor_bytes(d + off, ks, 256); off += 256; ctr += 8; }
#endif
#ifndef NO_SIMD
    if (level >= 1)
        while (n - off >= 128) { ks_x4(w, w6hi, ctr, ks); xor_bytes(d + off, ks, 128); off += 128; ctr += 4; }
#endif
    (void)level;
    while (off < n) {
        size_t m = n - off < 32 ? n - off : 32;
        ks_scalar(w, w6hi, ctr, ks);
        xor_bytes(d + off, ks, m);
        off += 32;
        ctr++;
    }
}

static void crypt_buf(uint8_t *d, size_t n, const uint8_t sid[16], unsigned mode, uint64_t seq, int resp) {
    crypt_ex(d, n, sid, mode, seq, resp, g_simd);
}

/* Compara las rutas SIMD con la escalar (la de referencia). Si alguna difiere en este procesador, se desactiva. */
static int simd_pick(int verbose) {
    int best = 0;
#ifndef NO_SIMD
    best = 1;
#if defined(HAVE_X8)
    __builtin_cpu_init();
    if (__builtin_cpu_supports("avx2")) best = 2;
#endif
#endif
    static const size_t lens[] = {1, 31, 32, 33, 127, 128, 129, 255, 256, 257, 511, 1000, 4097, 65536};
    uint8_t sid[16];
    int lv, ok = 1;
    size_t k, i;
    uint8_t *a = malloc(65536), *b = malloc(65536);
    if (!a || !b) { free(a); free(b); return 0; }
    for (i = 0; i < 16; i++) sid[i] = (uint8_t)(0xA0 + i);
    for (lv = best; lv >= 1; lv--) {
        ok = 1;
        for (k = 0; k < sizeof lens / sizeof lens[0] && ok; k++) {
            for (i = 0; i < lens[k]; i++) a[i] = b[i] = (uint8_t)(i * 7 + k);
            crypt_ex(a, lens[k], sid, MODE_BATCH, 0x1122334455667788ULL + k, 1, 0);
            crypt_ex(b, lens[k], sid, MODE_BATCH, 0x1122334455667788ULL + k, 1, lv);
            if (memcmp(a, b, lens[k]) != 0) ok = 0;
        }
        if (ok) { best = lv; break; }
        if (verbose) printf("aviso: la ruta SIMD nivel %d no coincide con la escalar: desactivada\n", lv);
        best = lv - 1;
    }
    if (best < 1) best = 0;
    free(a);
    free(b);
    return best;
}

static int self_test(int quiet) {
    /* 1) SHA-256("abc") */
    uint32_t w[16] = {0}, st[8];
    memcpy(st, IV256, sizeof st);
    w[0] = 0x61626380u;
    w[15] = 24;
    sha256_block(st, w);
    static const uint32_t abc[8] = {0xba7816bf, 0x8f01cfea, 0x414140de, 0x5dae2223,
                                    0xb00361a3, 0x96177a9c, 0xb410ff61, 0xf20015ad};
    if (memcmp(st, abc, sizeof st) != 0) { printf("FALLO: SHA-256\n"); return 1; }
    /* 2) ofuscacion contra un vector generado con la referencia en Python */
    uint8_t sid[16], buf[70];
    int i;
    for (i = 0; i < 16; i++) sid[i] = (uint8_t)i;
    for (i = 0; i < 70; i++) buf[i] = (uint8_t)i;
    crypt_ex(buf, sizeof buf, sid, 3, 0x0102030405060708ULL, 1, 0);
    static const uint8_t want[70] = {
        0x98, 0x42, 0x0a, 0x75, 0x59, 0x66, 0x08, 0xb3, 0x0c, 0x05, 0x60, 0x50, 0x21, 0x54, 0x5f, 0x27,
        0xd2, 0x72, 0xe4, 0xa1, 0xbc, 0xca, 0xda, 0xb4, 0x77, 0xe7, 0x64, 0x37, 0x9c, 0x61, 0x7f, 0xf3,
        0xa5, 0xf3, 0x9e, 0xcb, 0x9d, 0x58, 0xe0, 0x7b, 0x12, 0x0e, 0x6f, 0x90, 0x56, 0x4c, 0xb1, 0xbd,
        0xa9, 0xc9, 0xc5, 0x86, 0xd6, 0x13, 0xbd, 0x99, 0xb0, 0x47, 0x19, 0x4e, 0x65, 0x98, 0x6e, 0xd2,
        0x07, 0x33, 0xec, 0x01, 0x89, 0x8b};
    if (memcmp(buf, want, sizeof buf) != 0) { printf("FALLO: ofuscacion\n"); return 1; }
    g_simd = simd_pick(!quiet);
    uint8_t buf2[70];
    for (i = 0; i < 70; i++) buf2[i] = (uint8_t)i;
    crypt_buf(buf2, sizeof buf2, sid, 3, 0x0102030405060708ULL, 1);
    if (memcmp(buf2, want, sizeof buf2) != 0) { printf("FALLO: ofuscacion (ruta SIMD)\n"); return 1; }
    if (!quiet) printf("self-test OK (SHA-256 y ofuscacion BHP1; calculo: %s)\n",
                       g_simd == 2 ? "AVX2 x8" : g_simd == 1 ? "SIMD x4" : "escalar");
    return 0;
}

/* ------------------------------------------------------------------ E/S de red */

static int read_full(int fd, uint8_t *buf, size_t n, int64_t deadline) {
    size_t got = 0;
    while (got < n) {
        int64_t left = deadline - now_ms();
        if (left <= 0) return -1;
        struct pollfd p = {fd, POLLIN, 0};
        int r = poll(&p, 1, left > INT_MAX ? INT_MAX : (int)left);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (r == 0) return -1;
        ssize_t k = recv(fd, buf + got, n - got, 0);
        if (k == 0) return -1;
        if (k < 0) { if (errno == EINTR || errno == EAGAIN) continue; return -1; }
        got += (size_t)k;
    }
    return 0;
}

static int write_full(int fd, const uint8_t *buf, size_t n) {
    size_t sent = 0;
    while (sent < n) {
        ssize_t k = send(fd, buf + sent, n - sent, MSG_NOSIGNAL);
        if (k < 0) { if (errno == EINTR) continue; return -1; } /* EAGAIN = SO_SNDTIMEO vencido */
        if (k == 0) return -1;
        sent += (size_t)k;
    }
    return 0;
}

static void set_timeouts(int fd, int sec) {
    struct timeval tv = {sec, 0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
}

/* ------------------------------------------------------------------ configuracion */

static struct sockaddr_storage g_backend;
static socklen_t g_backend_len;
static char g_backend_txt[128] = "127.0.0.1:22";
static int g_poll_wait_ms = 800;
static int g_max_sessions = 128;
static int g_max_per_ip = 64;
static int g_idle = 120;
static long g_max_conns = 0;
static long g_conns = 0;

/* ------------------------------------------------------------------ sesiones */

typedef struct Slot { uint8_t *p; uint32_t n; } Slot;
typedef struct Pend { uint64_t seq; uint8_t *p; uint32_t n; struct Pend *next; } Pend;

typedef struct Session {
    uint8_t sid[16];
    uint8_t ipk[16];
    struct Session *next; /* cadena del hash (protegida por g_T) */
    int fd;
    pthread_mutex_t m; /* protege lo de abajo hasta "um" */
    pthread_cond_t cv;
    int ready, failed, closed, dead;
    int64_t last;
    uint8_t *bl;
    size_t bl_head, bl_tail, bl_cap;
    Slot *sl;
    size_t sl_head, sl_n, sl_cap;
    uint64_t sl_base, filled;
    pthread_mutex_t um; /* protege la subida (orden de escritura al SSH) */
    uint64_t next_up;
    Pend *pend;
    size_t pend_bytes;
    int refs; /* atomico */
} Session;

static pthread_mutex_t g_T = PTHREAD_MUTEX_INITIALIZER;
static Session *g_tab[HASH_BUCKETS];
static int g_total = 0; /* sesiones en la tabla (incluye las que se estan conectando) */

typedef struct { uint8_t ip[16]; int n; } IpCnt;
static IpCnt *g_ipt;
static size_t g_ipn, g_ipcap;

static unsigned hash_sid(const uint8_t *sid) {
    uint32_t h = be32(sid) ^ (be32(sid + 4) * 2654435761u);
    return h & (HASH_BUCKETS - 1);
}

static int ip_count(const uint8_t *ip) {
    for (size_t i = 0; i < g_ipn; i++) if (!memcmp(g_ipt[i].ip, ip, 16)) return g_ipt[i].n;
    return 0;
}
static void ip_inc(const uint8_t *ip) {
    for (size_t i = 0; i < g_ipn; i++) if (!memcmp(g_ipt[i].ip, ip, 16)) { g_ipt[i].n++; return; }
    if (g_ipn == g_ipcap) {
        size_t nc = g_ipcap ? g_ipcap * 2 : 256;
        IpCnt *nt = realloc(g_ipt, nc * sizeof *nt);
        if (!nt) return;
        g_ipt = nt; g_ipcap = nc;
    }
    memcpy(g_ipt[g_ipn].ip, ip, 16);
    g_ipt[g_ipn].n = 1;
    g_ipn++;
}
static void ip_dec(const uint8_t *ip) {
    for (size_t i = 0; i < g_ipn; i++)
        if (!memcmp(g_ipt[i].ip, ip, 16)) {
            if (--g_ipt[i].n <= 0) g_ipt[i] = g_ipt[--g_ipn];
            return;
        }
}

static void cond_init_mono(pthread_cond_t *cv) {
    pthread_condattr_t at;
    pthread_condattr_init(&at);
    pthread_condattr_setclock(&at, CLOCK_MONOTONIC);
    pthread_cond_init(cv, &at);
    pthread_condattr_destroy(&at);
}

/* espera hasta "deadline" (ms monotonico). Devuelve 1 si vencio el plazo. Requiere s->m tomado. */
static int cond_wait_until(Session *s, int64_t deadline) {
    struct timespec ts;
    ts.tv_sec = deadline / 1000;
    ts.tv_nsec = (deadline % 1000) * 1000000L;
    return pthread_cond_timedwait(&s->cv, &s->m, &ts) == ETIMEDOUT;
}

static Session *session_new(const uint8_t *sid, const uint8_t *ipk) {
    Session *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    memcpy(s->sid, sid, 16);
    memcpy(s->ipk, ipk, 16);
    s->fd = -1;
    pthread_mutex_init(&s->m, NULL);
    pthread_mutex_init(&s->um, NULL);
    cond_init_mono(&s->cv);
    s->last = now_ms();
    s->refs = 2; /* 1 la tabla + 1 quien la crea */
    return s;
}

static void session_free(Session *s) {
    if (s->fd >= 0) close(s->fd);
    free(s->bl);
    for (size_t i = 0; i < s->sl_n; i++) free(s->sl[s->sl_head + i].p);
    free(s->sl);
    while (s->pend) { Pend *p = s->pend; s->pend = p->next; free(p->p); free(p); }
    pthread_mutex_destroy(&s->m);
    pthread_mutex_destroy(&s->um);
    pthread_cond_destroy(&s->cv);
    free(s);
}

static void session_release(Session *s) {
    if (__atomic_sub_fetch(&s->refs, 1, __ATOMIC_ACQ_REL) == 0) session_free(s);
}
static void session_ref(Session *s) { __atomic_add_fetch(&s->refs, 1, __ATOMIC_ACQ_REL); }

static void *pump_thread(void *arg) {
    Session *s = arg;
    uint8_t *tmp = malloc(65536);
    for (;;) {
        pthread_mutex_lock(&s->m);
        while (!s->dead && (s->bl_tail - s->bl_head) >= BACKLOG_MAX) cond_wait_until(s, now_ms() + 20);
        int dead = s->dead;
        pthread_mutex_unlock(&s->m);
        if (dead || !tmp) break;
        ssize_t k = recv(s->fd, tmp, 65536, 0);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) break;
        pthread_mutex_lock(&s->m);
        size_t len = s->bl_tail - s->bl_head;
        if (s->bl_head > 0 && (s->bl_head > s->bl_cap / 2 || s->bl_tail + (size_t)k > s->bl_cap)) {
            memmove(s->bl, s->bl + s->bl_head, len);
            s->bl_head = 0;
            s->bl_tail = len;
        }
        if (s->bl_tail + (size_t)k > s->bl_cap) {
            size_t nc = s->bl_cap ? s->bl_cap : 65536;
            while (nc < s->bl_tail + (size_t)k) nc *= 2;
            uint8_t *nb = realloc(s->bl, nc);
            if (!nb) { pthread_mutex_unlock(&s->m); break; }
            s->bl = nb;
            s->bl_cap = nc;
        }
        memcpy(s->bl + s->bl_tail, tmp, (size_t)k);
        s->bl_tail += (size_t)k;
        pthread_cond_broadcast(&s->cv);
        pthread_mutex_unlock(&s->m);
    }
    free(tmp);
    pthread_mutex_lock(&s->m);
    s->closed = 1;
    pthread_cond_broadcast(&s->cv);
    pthread_mutex_unlock(&s->m);
    session_release(s);
    return NULL;
}

static int start_thread(void *(*fn)(void *), void *arg) {
    pthread_attr_t at;
    pthread_t th;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&at, THREAD_STACK);
    int r = pthread_create(&th, &at, fn, arg);
    pthread_attr_destroy(&at);
    return r;
}

static int backend_connect(void) {
    int fd = socket(g_backend.ss_family, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    int r = connect(fd, (struct sockaddr *)&g_backend, g_backend_len);
    if (r < 0 && errno == EINPROGRESS) {
        struct pollfd p = {fd, POLLOUT, 0};
        if (poll(&p, 1, 5000) == 1) {
            int err = 0;
            socklen_t el = sizeof err;
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el);
            r = err ? -1 : 0;
        } else r = -1;
    }
    if (r < 0) { close(fd); return -1; }
    fcntl(fd, F_SETFL, fl);
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
    set_timeouts(fd, 30);
    return fd;
}

static void wait_ready(Session *s) {
    pthread_mutex_lock(&s->m);
    while (!s->ready) pthread_cond_wait(&s->cv, &s->m);
    pthread_mutex_unlock(&s->m);
}

static Session *tab_find_locked(const uint8_t *sid) {
    for (Session *s = g_tab[hash_sid(sid)]; s; s = s->next)
        if (!memcmp(s->sid, sid, 16)) return s;
    return NULL;
}
static int tab_remove_locked(Session *s) {
    Session **pp = &g_tab[hash_sid(s->sid)];
    while (*pp) {
        if (*pp == s) { *pp = s->next; g_total--; ip_dec(s->ipk); return 1; }
        pp = &(*pp)->next;
    }
    return 0;
}

static void session_drop(Session *s) {
    pthread_mutex_lock(&g_T);
    int removed = tab_remove_locked(s);
    int left = g_total;
    pthread_mutex_unlock(&g_T);
    if (!removed) return;
    pthread_mutex_lock(&s->m);
    s->dead = 1;
    pthread_cond_broadcast(&s->cv);
    pthread_mutex_unlock(&s->m);
    if (s->fd >= 0) shutdown(s->fd, SHUT_RDWR);
    if (g_verbose) logmsg("INFO", "sesion cerrada (%d activas)", left);
    session_release(s); /* la referencia de la tabla */
}

/* Devuelve la sesion con una referencia tomada (hay que soltarla con session_release), o NULL. */
static Session *get_session(const uint8_t *sid, const uint8_t *ipk, int create) {
    pthread_mutex_lock(&g_T);
    Session *s = tab_find_locked(sid);
    if (s) {
        session_ref(s);
        pthread_mutex_unlock(&g_T);
        wait_ready(s);
        pthread_mutex_lock(&s->m);
        int failed = s->failed;
        pthread_mutex_unlock(&s->m);
        if (failed) { session_release(s); return NULL; }
        return s;
    }
    if (!create) { pthread_mutex_unlock(&g_T); return NULL; }
    if (g_total >= g_max_sessions) {
        pthread_mutex_unlock(&g_T);
        logmsg("WARNING", "limite de sesiones alcanzado");
        return NULL;
    }
    if (ip_count(ipk) >= g_max_per_ip) {
        pthread_mutex_unlock(&g_T);
        logmsg("WARNING", "limite de sesiones por IP alcanzado");
        return NULL;
    }
    s = session_new(sid, ipk);
    if (!s) { pthread_mutex_unlock(&g_T); return NULL; }
    unsigned h = hash_sid(sid);
    s->next = g_tab[h];
    g_tab[h] = s;
    g_total++;
    ip_inc(ipk);
    pthread_mutex_unlock(&g_T);

    int fd = backend_connect();
    int ok = fd >= 0;
    if (ok) {
        s->fd = fd;
        session_ref(s); /* la del hilo lector */
        if (start_thread(pump_thread, s) != 0) { session_release(s); ok = 0; }
    } else {
        logmsg("WARNING", "no se pudo conectar al destino: %s", strerror(errno));
    }
    pthread_mutex_lock(&s->m);
    s->failed = !ok;
    s->ready = 1;
    pthread_cond_broadcast(&s->cv);
    pthread_mutex_unlock(&s->m);
    if (!ok) {
        pthread_mutex_lock(&g_T);
        tab_remove_locked(s);
        pthread_mutex_unlock(&g_T);
        session_release(s); /* tabla */
        session_release(s); /* quien la crea */
        return NULL;
    }
    if (g_verbose) { pthread_mutex_lock(&g_T); int n = g_total; pthread_mutex_unlock(&g_T); logmsg("INFO", "sesion abierta (%d activas)", n); }
    return s;
}

static void *janitor_thread(void *arg) {
    (void)arg;
    int step = g_idle / 2;
    if (step < 1) step = 1;
    if (step > 15) step = 15;
    for (;;) {
        sleep((unsigned)step);
        int64_t now = now_ms();
        Session **list = NULL;
        size_t n = 0, cap = 0;
        pthread_mutex_lock(&g_T);
        for (int b = 0; b < HASH_BUCKETS; b++)
            for (Session *s = g_tab[b]; s; s = s->next) {
                pthread_mutex_lock(&s->m);
                int stale = s->ready && !s->failed && (now - s->last) > (int64_t)g_idle * 1000;
                pthread_mutex_unlock(&s->m);
                if (!stale) continue;
                if (n == cap) {
                    size_t nc = cap ? cap * 2 : 64;
                    Session **nl = realloc(list, nc * sizeof *nl);
                    if (!nl) continue;
                    list = nl; cap = nc;
                }
                session_ref(s);
                list[n++] = s;
            }
        pthread_mutex_unlock(&g_T);
        for (size_t i = 0; i < n; i++) { session_drop(list[i]); session_release(list[i]); }
        free(list);
    }
    return NULL;
}

/* ---- subida (en orden estricto de seq) */

static int session_upload(Session *s, uint64_t seq, uint8_t *data, uint32_t n) {
    pthread_mutex_lock(&s->m);
    s->last = now_ms();
    pthread_mutex_unlock(&s->m);
    if (n == 0) return ST_OK;
    int rc = ST_OK;
    pthread_mutex_lock(&s->um);
    if (seq < s->next_up) { pthread_mutex_unlock(&s->um); return ST_OK; }
    if (seq == s->next_up && s->pend == NULL) { /* camino rapido */
        s->next_up++;
        if (write_full(s->fd, data, n) < 0) rc = ST_ERR;
        pthread_mutex_unlock(&s->um);
        return rc;
    }
    int have = 0;
    for (Pend *p = s->pend; p; p = p->next) if (p->seq == seq) { have = 1; break; }
    if (!have) {
        if (s->pend_bytes + n > UP_PENDING_MAX) { pthread_mutex_unlock(&s->um); return ST_ERR; }
        Pend *p = malloc(sizeof *p);
        uint8_t *cp = malloc(n);
        if (!p || !cp) { free(p); free(cp); pthread_mutex_unlock(&s->um); return ST_ERR; }
        memcpy(cp, data, n);
        p->seq = seq; p->p = cp; p->n = n; p->next = s->pend;
        s->pend = p;
        s->pend_bytes += n;
    }
    for (;;) {
        Pend **pp = &s->pend;
        while (*pp && (*pp)->seq != s->next_up) pp = &(*pp)->next;
        if (!*pp) break;
        Pend *p = *pp;
        *pp = p->next;
        s->pend_bytes -= p->n;
        s->next_up++;
        if (write_full(s->fd, p->p, p->n) < 0) rc = ST_ERR;
        free(p->p);
        free(p);
        if (rc == ST_ERR) break;
    }
    pthread_mutex_unlock(&s->um);
    return rc;
}

/* ---- bajada: el flujo del SSH se reparte en "casillas" numeradas */

static int slot_push_locked(Session *s, size_t take) {
    if (s->sl_head + s->sl_n == s->sl_cap) {
        if (s->sl_head > 0) {
            memmove(s->sl, s->sl + s->sl_head, s->sl_n * sizeof *s->sl);
            s->sl_head = 0;
        } else {
            size_t nc = s->sl_cap ? s->sl_cap * 2 : 64;
            Slot *ns = realloc(s->sl, nc * sizeof *ns);
            if (!ns) return -1;
            s->sl = ns;
            s->sl_cap = nc;
        }
    }
    Slot *sl = &s->sl[s->sl_head + s->sl_n];
    sl->p = NULL;
    sl->n = (uint32_t)take;
    if (take) {
        sl->p = malloc(take);
        if (!sl->p) return -1;
        memcpy(sl->p, s->bl + s->bl_head, take);
        s->bl_head += take;
        if (s->bl_head == s->bl_tail) s->bl_head = s->bl_tail = 0;
    }
    s->sl_n++;
    s->filled++;
    return 0;
}

static uint8_t *session_batch(Session *s, uint64_t base, uint32_t chunk, uint32_t count, size_t *outn) {
    uint64_t end = base + count;
    pthread_mutex_lock(&s->m);
    s->last = now_ms();
    if (end > s->filled && end - s->filled > MAX_WINDOW_AHEAD) { pthread_mutex_unlock(&s->m); return NULL; }
    if (g_poll_wait_ms > 0 && end > s->filled && s->bl_tail == s->bl_head && !s->closed && !s->dead) {
        int64_t deadline = now_ms() + g_poll_wait_ms;
        while (!(s->filled >= end || s->closed || s->dead || s->bl_tail > s->bl_head))
            if (cond_wait_until(s, deadline)) break;
        s->last = now_ms();
    }
    int changed = 0;
    while (s->filled < end) {
        size_t avail = s->bl_tail - s->bl_head;
        size_t take = avail < chunk ? avail : chunk;
        if (slot_push_locked(s, take) < 0) { pthread_mutex_unlock(&s->m); return NULL; }
        changed = 1;
    }
    if (changed) pthread_cond_broadcast(&s->cv);

    size_t total = 0;
    uint32_t i;
    uint32_t lens[MAX_BATCH];
    for (i = 0; i < count; i++) {
        uint64_t k = base + i;
        lens[i] = (k >= s->sl_base && k < s->filled) ? s->sl[s->sl_head + (size_t)(k - s->sl_base)].n : 0;
        total += 9 + lens[i];
    }
    uint8_t *out = malloc(total);
    if (!out) { pthread_mutex_unlock(&s->m); return NULL; }
    uint8_t *o = out;
    for (i = 0; i < count; i++) {
        uint64_t k = base + i;
        *o++ = ST_DATA;
        put_be32(o, 4 + lens[i]); o += 4;
        put_be32(o, lens[i]); o += 4;
        if (lens[i]) memcpy(o, s->sl[s->sl_head + (size_t)(k - s->sl_base)].p, lens[i]);
        o += lens[i];
    }
    pthread_mutex_unlock(&s->m);

    o = out;
    for (i = 0; i < count; i++) {
        crypt_buf(o + 9, lens[i], s->sid, MODE_BATCH, base + i, 1);
        o += 9 + lens[i];
    }
    *outn = total;
    return out;
}

static void session_ack(Session *s, uint64_t seq) {
    pthread_mutex_lock(&s->m);
    s->last = now_ms();
    while (s->sl_n > 0 && s->sl_base <= seq) {
        free(s->sl[s->sl_head].p);
        s->sl_head++;
        s->sl_n--;
        s->sl_base++;
    }
    if (s->sl_n == 0) { s->sl_head = 0; s->sl_base = s->filled; }
    pthread_mutex_unlock(&s->m);
}

/* ------------------------------------------------------------------ despacho de peticiones */

static uint8_t *mkreply(uint8_t st, const uint8_t *body, uint32_t n, size_t *outn) {
    uint8_t *o = malloc(5 + (size_t)n);
    if (!o) return NULL;
    o[0] = st;
    put_be32(o + 1, n);
    if (n) memcpy(o + 5, body, n);
    *outn = 5 + (size_t)n;
    return o;
}

static uint8_t *dispatch(unsigned mode, const uint8_t *sid, uint64_t seq, uint8_t *data, uint32_t n,
                         const uint8_t *ipk, size_t *outn) {
    Session *s;
    if (mode == MODE_PROBE) {
        crypt_buf(data, n, sid, MODE_PROBE, 0, 0);
        if (n < 10 || memcmp(data, "BHP1", 4) != 0 || data[4] != 1) return mkreply(ST_ERR, NULL, 0, outn);
        unsigned pm = data[5];
        int32_t param = (int32_t)be32(data + 6);
        uint32_t length = 10;
        if (pm == MODE_DOWNLOAD && param > 10) length = (uint32_t)param;
        if (length > MAX_PROBE_REPLY) return mkreply(ST_ERR, NULL, 0, outn);
        uint8_t *body = malloc(length);
        if (!body) return NULL;
        memcpy(body, "BHP1", 4);
        body[4] = 1;
        body[5] = (uint8_t)pm;
        memcpy(body + 6, data + 6, 4);
        for (uint32_t i = 10; i < length; i++) body[i] = (uint8_t)((i * 31u) & 0xFF);
        crypt_buf(body, length, sid, MODE_PROBE, 0, 1);
        uint8_t *r = mkreply(ST_OK, body, length, outn);
        free(body);
        return r;
    }
    if (mode == MODE_UPLOAD) {
        s = get_session(sid, ipk, 1);
        if (!s) return mkreply(ST_ERR, NULL, 0, outn);
        crypt_buf(data, n, sid, MODE_UPLOAD, seq, 0);
        int st = session_upload(s, seq, data, n);
        session_release(s);
        return mkreply((uint8_t)st, NULL, 0, outn);
    }
    if (mode == MODE_BATCH) {
        s = get_session(sid, ipk, 0);
        crypt_buf(data, n, sid, MODE_BATCH, seq, 0);
        if (!s || n < 6) { if (s) session_release(s); return mkreply(ST_ERR, NULL, 0, outn); }
        int32_t chunk = (int32_t)be32(data);
        unsigned count = data[5];
        if (chunk < 1 || chunk > MAX_CHUNK || count < 1 || count > MAX_BATCH) {
            session_release(s);
            return mkreply(ST_ERR, NULL, 0, outn);
        }
        uint8_t *r = session_batch(s, seq, (uint32_t)chunk, count, outn);
        session_release(s);
        return r ? r : mkreply(ST_ERR, NULL, 0, outn);
    }
    if (mode == MODE_ACK) {
        s = get_session(sid, ipk, 0);
        if (!s) return mkreply(ST_ERR, NULL, 0, outn);
        session_ack(s, seq);
        session_release(s);
        return mkreply(ST_OK, NULL, 0, outn);
    }
    return mkreply(ST_ERR, NULL, 0, outn);
}

typedef struct { int fd; uint8_t ipk[16]; } ConnArg;

static void *conn_thread(void *arg) {
    ConnArg ca = *(ConnArg *)arg;
    free(arg);
    int fd = ca.fd;
    for (int nreq = 0; nreq < MAX_REQUESTS_PER_CONN; nreq++) {
        uint8_t head[HEADER];
        if (read_full(fd, head, HEADER, now_ms() + (nreq == 0 ? REQUEST_TIMEOUT_MS : KEEPALIVE_IDLE_MS)) < 0) break;
        unsigned mode = head[0];
        const uint8_t *sid = head + 1;
        uint64_t seq = be64(head + 17);
        uint32_t n = be32(head + 25);
        size_t outn = 0;
        uint8_t *out;
        if (n > MAX_REQUEST) {
            out = mkreply(ST_ERR, NULL, 0, &outn);
            if (out) { write_full(fd, out, outn); free(out); }
            break;
        }
        uint8_t *data = NULL;
        if (n) {
            data = malloc(n);
            if (!data) break;
            if (read_full(fd, data, n, now_ms() + REQUEST_TIMEOUT_MS) < 0) { free(data); break; }
        }
        out = dispatch(mode, sid, seq, data, n, ca.ipk, &outn);
        free(data);
        if (!out) break;
        int bad = write_full(fd, out, outn);
        free(out);
        if (bad) break;
    }
    close(fd);
    __atomic_sub_fetch(&g_conns, 1, __ATOMIC_RELAXED);
    return NULL;
}

/* ------------------------------------------------------------------ autoprueba de un servidor en marcha */

static int probe_client(const char *target) {
    char host[128] = "127.0.0.1";
    const char *c = strrchr(target, ':');
    if (!c) { printf("uso: --probe HOST:PUERTO\n"); return 0; }
    if (c > target) { size_t l = (size_t)(c - target); if (l >= sizeof host) l = sizeof host - 1; memcpy(host, target, l); host[l] = 0; }
    struct addrinfo hints = {0}, *ai = NULL;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, c + 1, &hints, &ai) != 0 || !ai) { printf("no se pudo conectar: direccion invalida\n"); return 0; }
    int fd = socket(ai->ai_family, SOCK_STREAM, 0);
    if (fd < 0 || connect(fd, ai->ai_addr, ai->ai_addrlen) < 0) { printf("no se pudo conectar: %s\n", strerror(errno)); freeaddrinfo(ai); return 0; }
    freeaddrinfo(ai);
    uint8_t sid[16], plain[10], req[HEADER + 10];
    FILE *ur = fopen("/dev/urandom", "rb");
    if (!ur || fread(sid, 1, 16, ur) != 16) { printf("sin /dev/urandom\n"); return 0; }
    fclose(ur);
    memcpy(plain, "BHP1", 4); plain[4] = 1; plain[5] = MODE_BATCH; put_be32(plain + 6, 8);
    crypt_buf(plain, 10, sid, MODE_PROBE, 0, 0);
    req[0] = MODE_PROBE; memcpy(req + 1, sid, 16); memset(req + 17, 0, 8); put_be32(req + 25, 10); memcpy(req + HEADER, plain, 10);
    int64_t dl = now_ms() + 5000;
    uint8_t h[5], body[64];
    if (write_full(fd, req, sizeof req) < 0 || read_full(fd, h, 5, dl) < 0) { printf("el servidor respondio con error o no respondio\n"); close(fd); return 0; }
    uint32_t bn = be32(h + 1);
    if (h[0] != ST_OK || bn != 10 || read_full(fd, body, bn, dl) < 0) { printf("el servidor respondio con error o no respondio\n"); close(fd); return 0; }
    close(fd);
    crypt_buf(body, bn, sid, MODE_PROBE, 0, 1);
    int good = !memcmp(body, "BHP1", 4) && body[4] == 1 && body[5] == MODE_BATCH && be32(body + 6) == 8;
    printf(good ? "sondeo BHP1: OK\n" : "sondeo BHP1: respuesta invalida\n");
    return good;
}

/* ------------------------------------------------------------------ main */

static void usage(void) {
    printf("el_tioNel BHTTP (motor C) v" VERSION "\n"
           "  --listen DIR            direccion donde escucha (0.0.0.0)\n"
           "  --port N                puerto TCP\n"
           "  --backend HOST:PUERTO   destino al que se reenvia (127.0.0.1:22)\n"
           "  --poll-wait-ms MS       espera de datos antes de responder vacio (800)\n"
           "  --max-sessions N        sesiones simultaneas maximas (128)\n"
           "  --max-per-ip N          sesiones maximas por IP (64)\n"
           "  --idle S                segundos sin actividad para cerrar una sesion (120)\n"
           "  --probe HOST:PUERTO     autoprueba contra un servidor en marcha\n"
           "  --self-test             comprueba SHA-256 y la ofuscacion\n"
           "  -v, --verbose           registra sesiones abiertas/cerradas\n"
           "  (TLS no esta soportado en este motor)\n");
}

static void ip_key(const struct sockaddr_storage *ss, uint8_t out[16]) {
    memset(out, 0, 16);
    if (ss->ss_family == AF_INET) {
        const struct sockaddr_in *a = (const struct sockaddr_in *)ss;
        out[10] = out[11] = 0xff;
        memcpy(out + 12, &a->sin_addr, 4);
    } else if (ss->ss_family == AF_INET6) {
        const struct sockaddr_in6 *a = (const struct sockaddr_in6 *)ss;
        memcpy(out, &a->sin6_addr, 16);
    }
}

int main(int argc, char **argv) {
    const char *listen_addr = "0.0.0.0", *probe = NULL, *backend = "127.0.0.1:22";
    int port = 0, i;
    signal(SIGPIPE, SIG_IGN);
    mallopt(M_ARENA_MAX, 2); /* muchos hilos cortos: evita que cada uno infle su propio arena de malloc */
    {   /* apagado limpio con SIGTERM/SIGINT (sin SA_RESTART: accept() se interrumpe y se sale) */
        struct sigaction sa;
        memset(&sa, 0, sizeof sa);
        sa.sa_handler = on_term;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGTERM, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);
    }
    for (i = 1; i < argc; i++) {
        char *a = argv[i], *eq = strchr(a, '='), *val = NULL;
        char key[64];
        if (a[0] == '-' && a[1] == '-' && eq) {
            size_t l = (size_t)(eq - a);
            if (l >= sizeof key) l = sizeof key - 1;
            memcpy(key, a, l); key[l] = 0; a = key; val = eq + 1;
        }
#define NEXTVAL() (val ? val : (i + 1 < argc ? argv[++i] : (fprintf(stderr, "falta valor para %s\n", a), exit(2), (char *)0)))
        if (!strcmp(a, "--listen")) listen_addr = NEXTVAL();
        else if (!strcmp(a, "--port")) port = atoi(NEXTVAL());
        else if (!strcmp(a, "--backend")) backend = NEXTVAL();
        else if (!strcmp(a, "--poll-wait-ms")) { g_poll_wait_ms = atoi(NEXTVAL()); if (g_poll_wait_ms < 0) g_poll_wait_ms = 0; }
        else if (!strcmp(a, "--max-sessions")) g_max_sessions = atoi(NEXTVAL());
        else if (!strcmp(a, "--max-per-ip")) g_max_per_ip = atoi(NEXTVAL());
        else if (!strcmp(a, "--idle")) g_idle = atoi(NEXTVAL());
        else if (!strcmp(a, "--probe")) probe = NEXTVAL();
        else if (!strcmp(a, "--tls")) { printf("este motor no soporta TLS\n"); return 1; }
        else if (!strcmp(a, "--tls-cert") || !strcmp(a, "--tls-key")) {
            fprintf(stderr, "este motor C no soporta TLS: usa el servidor Python para TLS\n");
            return 2;
        }
        else if (!strcmp(a, "--self-test")) return self_test(0);
        else if (!strcmp(a, "-v") || !strcmp(a, "--verbose")) g_verbose = 1;
        else if (!strcmp(a, "-h") || !strcmp(a, "--help")) { usage(); return 0; }
        else { fprintf(stderr, "opcion desconocida: %s\n", a); return 2; }
    }
    if (self_test(1) != 0) return 1;
    if (probe) return probe_client(probe) ? 0 : 1;
    if (port < 1 || port > 65535) { fprintf(stderr, "falta --port\n"); return 2; }
    if (g_max_sessions < 1) g_max_sessions = 1;
    if (g_max_per_ip < 1) g_max_per_ip = 1;
    if (g_idle < 1) g_idle = 1;

    /* destino */
    {
        char host[128] = "127.0.0.1", pt[16];
        const char *c = strrchr(backend, ':');
        if (!c) { fprintf(stderr, "--backend debe ser HOST:PUERTO\n"); return 2; }
        if (c > backend) { size_t l = (size_t)(c - backend); if (l >= sizeof host) l = sizeof host - 1; memcpy(host, backend, l); host[l] = 0; }
        snprintf(pt, sizeof pt, "%s", c + 1);
        struct addrinfo hints = {0}, *ai = NULL;
        hints.ai_socktype = SOCK_STREAM;
        if (getaddrinfo(host, pt, &hints, &ai) != 0 || !ai) { fprintf(stderr, "destino invalido: %s\n", backend); return 2; }
        memcpy(&g_backend, ai->ai_addr, ai->ai_addrlen);
        g_backend_len = ai->ai_addrlen;
        freeaddrinfo(ai);
        snprintf(g_backend_txt, sizeof g_backend_txt, "%s", backend);
    }

    struct rlimit rl;
    if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < rl.rlim_max) { rl.rlim_cur = rl.rlim_max; setrlimit(RLIMIT_NOFILE, &rl); }
    g_max_conns = (long)g_max_sessions * 16 + 1024;
    if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur != RLIM_INFINITY && (long)rl.rlim_cur > 64 && g_max_conns > (long)rl.rlim_cur - 64 - g_max_sessions)
        g_max_conns = (long)rl.rlim_cur - 64 - g_max_sessions;
    if (g_max_conns < 16) g_max_conns = 16;

    struct addrinfo hints = {0}, *ai = NULL;
    char ps[16];
    snprintf(ps, sizeof ps, "%d", port);
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;
    if (getaddrinfo(listen_addr, ps, &hints, &ai) != 0 || !ai) { fprintf(stderr, "direccion de escucha invalida: %s\n", listen_addr); return 2; }
    int ls = socket(ai->ai_family, SOCK_STREAM, 0);
    int one = 1;
    if (ls < 0) { perror("socket"); return 1; }
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    if (bind(ls, ai->ai_addr, ai->ai_addrlen) < 0) { perror("bind"); return 1; }
    freeaddrinfo(ai);
    if (listen(ls, 1024) < 0) { perror("listen"); return 1; }

    if (start_thread(janitor_thread, NULL) != 0) { fprintf(stderr, "no pude crear el hilo de limpieza\n"); return 1; }
    logmsg("INFO", "BHTTP (motor C v" VERSION ") escuchando en %s:%d -> %s", listen_addr, port, g_backend_txt);

    for (;;) {
        struct sockaddr_storage ss;
        socklen_t sl = sizeof ss;
        int fd = accept(ls, (struct sockaddr *)&ss, &sl);
        if (fd < 0) {
            if (g_stop) break;
            if (errno == EINTR || errno == ECONNABORTED) continue;
            if (errno == EMFILE || errno == ENFILE || errno == ENOBUFS || errno == ENOMEM) { usleep(50000); continue; }
            perror("accept");
            return 1;
        }
        if (__atomic_add_fetch(&g_conns, 1, __ATOMIC_RELAXED) > g_max_conns) {
            __atomic_sub_fetch(&g_conns, 1, __ATOMIC_RELAXED);
            close(fd);
            continue;
        }
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof one);
        int v = 60; setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &v, sizeof v);
        v = 15; setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &v, sizeof v);
        v = 4; setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &v, sizeof v);
        set_timeouts(fd, 30);
        ConnArg *ca = malloc(sizeof *ca);
        if (!ca) { close(fd); __atomic_sub_fetch(&g_conns, 1, __ATOMIC_RELAXED); continue; }
        ca->fd = fd;
        ip_key(&ss, ca->ipk);
        if (start_thread(conn_thread, ca) != 0) {
            free(ca);
            close(fd);
            __atomic_sub_fetch(&g_conns, 1, __ATOMIC_RELAXED);
        }
    }
    close(ls);
    logmsg("INFO", "BHTTP detenido");
    return 0;
}
BHTTP_C_SRC_EOF
  chmod 644 "$CSRC"
}
ensure_cc(){
  have gcc && return 0
  have cc && return 0
  info "Instalando el compilador (gcc)..."
  if have apt-get; then DEBIAN_FRONTEND=noninteractive apt-get install -y gcc libc6-dev >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y gcc libc6-dev >/dev/null 2>&1; }
  elif have dnf; then dnf install -y gcc glibc-devel >/dev/null 2>&1
  elif have yum; then yum install -y gcc glibc-devel >/dev/null 2>&1
  elif have apk; then apk add --no-cache gcc musl-dev >/dev/null 2>&1; fi
  have gcc || have cc
}
build_cengine(){
  ensure_cc || { warn "No pude instalar un compilador: se usara el motor Python."; return 1; }
  local cc tmp="$CBIN.new"; cc="$(command -v gcc || command -v cc)"
  write_cengine_src || return 1
  info "Compilando el motor C (unos segundos)..."
  if   "$cc" -O2 -pthread -fstack-protector-strong -D_FORTIFY_SOURCE=2 -o "$tmp" "$CSRC" >/dev/null 2>&1; then :
  elif "$cc" -O2 -pthread -DNO_SIMD -o "$tmp" "$CSRC" >/dev/null 2>&1; then info "Compilado sin SIMD (compilador antiguo)."
  else rm -f "$tmp"; warn "No pude compilar el motor C: se usara el motor Python."; return 1; fi
  if ! "$tmp" --self-test >/dev/null 2>&1; then
    rm -f "$tmp"; warn "El motor C no paso su autoprueba en este equipo: se usara el motor Python."; return 1
  fi
  [ -x "$CBIN" ] && cp -a "$CBIN" "$CBIN.prev"
  mv -f "$tmp" "$CBIN"; chmod 755 "$CBIN"
  ok "Motor C listo: $("$CBIN" --self-test 2>/dev/null | sed -n 's/.*calculo: \(.*\))/\1/p')"
}
# Motor que se usara de verdad: C si esta compilado y no hay TLS (el C no hace TLS); si no, Python.
engine_pick(){
  if [ "$(cfg_get ENGINE)" = c ] && [ -x "$CBIN" ] && ! tls_active; then echo c; else echo python; fi
}
engine_label(){
  local e w; e="$(engine_pick)"; w="$(cfg_get ENGINE)"
  if [ "$e" = c ]; then echo "C (compilado)"
  elif [ "$w" = c ]; then
    if tls_active; then echo "Python (TLS activo: el motor C no hace TLS)"; else echo "Python (el motor C no esta compilado: opcion 1)"; fi
  else echo "Python"; fi
}
set_engine(){
  need_root
  local e="${1:-}"
  if [ -z "$e" ]; then ask e "Motor (c / python) [$(cfg_get ENGINE)]: "; e="${e:-$(cfg_get ENGINE)}"; fi
  case "$e" in c|C) e=c;; py|python|Python|PYTHON) e=python;; *) fail "Elige c o python."; return 1;; esac
  if [ "$e" = c ]; then
    [ -x "$CBIN" ] || build_cengine || return 1
    if tls_active; then warn "TLS esta activo: mientras siga activo se usara Python (el motor C no hace TLS)."; fi
  fi
  cfg_set ENGINE "$e"; write_unit; restart_all
  ok "Motor en uso: $(engine_label)"
}

write_unit(){
  local py eng exec_line; py="$(command -v python3)"; eng="$(engine_pick)"
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<'UNIT_EOF'
[Unit]
Description=__BRAND__ BHTTP (puerto %i)
After=network-online.target ssh.service sshd.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
EnvironmentFile=__CONFIG__
ExecStart=__EXEC__
Restart=always
RestartSec=1
TimeoutStopSec=15
LimitNOFILE=524288
TasksMax=infinity
# Sin privilegios y con el sistema protegido
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
# Solo hace falta para puertos menores a 1024
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT_EOF
  if [ "$eng" = c ]; then
    exec_line='__CBIN__ --listen 0.0.0.0 --port %i --backend ${BACKEND} --poll-wait-ms ${POLL_WAIT_MS} --max-sessions ${MAX_SESSIONS} --max-per-ip ${MAX_PER_IP} --idle ${IDLE}'
  else
    exec_line='__LAUNCHER__ __SERVER__ --listen 0.0.0.0 --port %i --backend ${BACKEND} --poll-wait-ms ${POLL_WAIT_MS} --max-sessions ${MAX_SESSIONS} --max-per-ip ${MAX_PER_IP} --idle ${IDLE} $TLS_ARGS'
  fi
  awk -v e="$exec_line" '$0=="ExecStart=__EXEC__"{print "ExecStart=" e; next} {print}' "$UNIT_FILE" > "$UNIT_FILE.tmp" && mv "$UNIT_FILE.tmp" "$UNIT_FILE"
  mkdir -p "$(dirname "$LAUNCHER")"
  ln -sfn "$py" "$LAUNCHER"
  sed -i -e "s|__BRAND__|$BRAND|" -e "s|__CONFIG__|${CONFIG#"$ROOT"}|" \
         -e "s|__LAUNCHER__|${LAUNCHER#"$ROOT"}|" -e "s|__SERVER__|${SERVER#"$ROOT"}|" \
         -e "s|__CBIN__|${CBIN#"$ROOT"}|" "$UNIT_FILE"
  systemctl daemon-reload
}

install_self(){
  local src="${BASH_SOURCE[0]:-$0}"
  if [ -f "$src" ] && [ -r "$src" ]; then
    mkdir -p "$(dirname "$SELF_DEST")" "$(dirname "$BIN_LINK")"
    if [ "$(readlink -f "$src")" != "$(readlink -f "$SELF_DEST" 2>/dev/null)" ]; then cp "$src" "$SELF_DEST"; fi
    chmod 755 "$SELF_DEST"; ln -sfn "$SELF_DEST" "$BIN_LINK"
    ok "Comando instalado: sudo $CMD"
  else
    warn "No instale el comando '$CMD' (ejecuta el archivo guardado en disco, no por pipe)."
  fi
}

do_install(){
  need_root; ensure_python || return 1
  local first="${1:-}" p
  cfg_init; cfg_upgrade_limits; ensure_uvloop; write_server || return 1
  if [ "$(cfg_get ENGINE)" != python ]; then build_cengine || true; fi
  write_unit; install_self
  tuning_on || warn "No pude aplicar el ajuste de red (puedes hacerlo luego con la opcion 8)."
  for p in $(ports_list); do systemctl enable --now "$(unit_name "$p")" >/dev/null 2>&1; systemctl restart "$(unit_name "$p")"; done
  ok "Servidor BHTTP v2 instalado/actualizado. Motor: $(engine_label)"
  if [ -z "$(ports_list)" ]; then
    if [ -n "$first" ]; then add_port "$first"
    elif [ -t 0 ]; then ask p "Puerto TCP para BHTTP, el que pondras en la app [8080]: "; add_port "${p:-8080}"
    else info "No hay puertos: usa  $CMD add-port NUMERO"; fi
  fi
  echo; selftest
}

# ---------------------------------------------------------------- puertos: agregar / quitar
add_port(){
  need_root; local p="${1:-}"
  [ -n "$p" ] || ask p "Puerto TCP a abrir: "
  valid_port "$p" || { fail "Puerto invalido."; return 1; }
  [ -f "$SERVER" ] || { fail "Primero instala (opcion 1)."; return 1; }
  if ports_has "$p"; then info "El puerto $p ya esta configurado."; return 0; fi
  if listening "$p"; then fail "El puerto $p ya esta ocupado por otro servicio. No toque nada."; ss -lntp 2>/dev/null | awk -v p=":$p" '$4 ~ p"$"'; return 1; fi
  cfg_init; ports_add "$p"
  systemctl enable --now "$(unit_name "$p")" >/dev/null 2>&1
  sleep 1
  if listening "$p"; then
    ok "Puerto BHTTP :$p activo y con arranque automatico."
    fw_open "$p"
    if python3 "$SERVER" --probe "127.0.0.1:$p" $(probe_flags) >/dev/null 2>&1; then ok "Sondeo BHP1 en :$p: OK"; else warn "El puerto escucha pero el sondeo BHP1 fallo: mira los logs (opcion 10)."; fi
  else
    fail "El puerto :$p no quedo activo. Revisa: journalctl -u $(unit_name "$p")"
    ports_del "$p"; return 1
  fi
}
remove_port(){
  need_root; local p="${1:-}"
  [ -n "$(ports_list)" ] || { info "No hay puertos configurados."; return 0; }
  [ -n "$p" ] || { echo "Puertos actuales: $(ports_list | tr '\n' ' ')"; ask p "Puerto a cerrar: "; }
  ports_has "$p" || { fail "El puerto $p no es uno de los de BHTTP."; return 1; }
  confirm_word CERRAR "Se cerrara el puerto $p." || { info "Sin cambios."; return 0; }
  systemctl disable --now "$(unit_name "$p")" >/dev/null 2>&1
  ports_del "$p"; fw_close "$p"
  ok "Puerto $p cerrado y quitado del arranque."
}

# ---------------------------------------------------------------- control
each_port(){ local p; for p in $(ports_list); do "$@" "$p"; done; }
restart_all(){
  local p n=0; for p in $(ports_list); do systemctl restart "$(unit_name "$p")"; n=$((n+1)); done
  [ "$n" -gt 0 ] && ok "Reiniciados $n puerto(s)." || info "No hay puertos configurados."
}
start_all(){ local p n=0; for p in $(ports_list); do systemctl enable --now "$(unit_name "$p")" >/dev/null 2>&1; n=$((n+1)); done; [ "$n" -gt 0 ] && ok "Iniciados $n puerto(s)." || info "No hay puertos configurados."; }
stop_all(){ local p n=0; for p in $(ports_list); do systemctl stop "$(unit_name "$p")"; n=$((n+1)); done; [ "$n" -gt 0 ] && warn "Detenidos. Siguen con arranque automatico." || info "No hay puertos configurados."; }
show_logs(){
  local p n=0
  for p in $(ports_list); do echo "===== :$p ====="; journalctl -u "$(unit_name "$p")" -n 60 --no-pager 2>/dev/null || true; n=$((n+1)); done
  [ "$n" -gt 0 ] || info "No hay puertos configurados."
}
set_backend(){
  need_root; local p="${1:-}"
  [ -n "$p" ] || ask p "Puerto del SSH (destino local) [$(backend_port)]: "
  p="${p:-$(backend_port)}"
  valid_port "$p" || { fail "Puerto invalido."; return 1; }
  cfg_set BACKEND "127.0.0.1:$p"; ok "Destino: 127.0.0.1:$p"
  listening "$p" || warn "No veo nada escuchando en :$p."
  restart_all
}
set_value(){            # set_value CLAVE min max "texto"
  need_root; local k="$1" min="$2" max="$3" label="$4" v="${5:-}"
  [ -n "$v" ] || ask v "$label [$(cfg_get "$k")]: "
  v="${v:-$(cfg_get "$k")}"
  valid_num "$min" "$v" "$max" || { fail "Valor invalido (entre $min y $max)."; return 1; }
  cfg_set "$k" "$v"; ok "$label: $v"; restart_all
}

# ---------------------------------------------------------------- ajuste de red (opcional y reversible)
tune_list(){
cat <<'TUNE_EOF'
net.core.default_qdisc|fq
net.ipv4.tcp_congestion_control|bbr
fs.file-max|1048576
net.core.somaxconn|16384
net.core.netdev_max_backlog|16384
net.core.rmem_max|16777216
net.core.wmem_max|16777216
net.ipv4.tcp_rmem|4096 131072 16777216
net.ipv4.tcp_wmem|4096 131072 16777216
net.ipv4.ip_local_port_range|10240 65535
net.ipv4.tcp_max_syn_backlog|16384
net.ipv4.tcp_max_tw_buckets|262144
net.ipv4.tcp_fin_timeout|15
net.ipv4.tcp_tw_reuse|1
net.ipv4.tcp_slow_start_after_idle|0
net.ipv4.tcp_fastopen|3
net.ipv4.tcp_keepalive_time|60
net.ipv4.tcp_keepalive_intvl|15
net.ipv4.tcp_keepalive_probes|4
net.ipv4.tcp_mtu_probing|1
TUNE_EOF
}
tuning_on(){
  need_root
  have sysctl || { fail "No encontre sysctl."; return 1; }
  local line k v cur avail
  mkdir -p "$CONF_DIR" "$(dirname "$SYSCTL_FILE")"
  [ -f "$SYSCTL_PREV" ] || : > "$SYSCTL_PREV"
  printf '# %s BHTTP - ajustes de red opcionales (se quitan desde el menu: %s)\n' "$BRAND" "$CMD" > "$SYSCTL_FILE"
  have modprobe && modprobe tcp_bbr >/dev/null 2>&1 || true
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  while IFS='|' read -r k v; do
    [ -n "$k" ] || continue
    cur="$(sysctl -n "$k" 2>/dev/null)" || continue          # la clave no existe en este kernel
    if [ "$k" = "net.ipv4.tcp_congestion_control" ] && ! printf '%s' "$avail" | grep -qw bbr; then
      warn "Este kernel no ofrece BBR: se omite."; continue
    fi
    grep -q "^$k|" "$SYSCTL_PREV" 2>/dev/null || printf '%s|%s\n' "$k" "$cur" >> "$SYSCTL_PREV"
    printf '%s = %s\n' "$k" "$v" >> "$SYSCTL_FILE"
    sysctl -w "$k=$v" >/dev/null 2>&1 || true
  done < <(tune_list)
  ok "Ajuste de red aplicado ($(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?'))."
  info "Afecta a todo el servidor. Los valores anteriores quedaron guardados para poder revertirlo."
}
tuning_off(){
  need_root
  local k v
  if [ -s "$SYSCTL_PREV" ]; then
    while IFS='|' read -r k v; do [ -n "$k" ] && sysctl -w "$k=$v" >/dev/null 2>&1 || true; done < "$SYSCTL_PREV"
    ok "Valores anteriores restaurados."
  fi
  rm -f "$SYSCTL_FILE" "$SYSCTL_PREV"
  ok "Ajuste de red quitado."
}
tuning_state(){ [ -f "$SYSCTL_FILE" ] && echo "ACTIVO" || echo "apagado"; }

# ---------------------------------------------------------------- TLS con SNI (opcional)
tls_active(){ [ -n "$(cfg_get TLS_ARGS)" ]; }
probe_flags(){ tls_active && echo "--tls"; }
tls_fingerprint(){
  [ -f "$TLS_DIR/cert.pem" ] || return 1
  openssl x509 -in "$TLS_DIR/cert.pem" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//'
}
ensure_openssl(){
  have openssl && return 0
  info "Instalando openssl..."
  if have apt-get; then DEBIAN_FRONTEND=noninteractive apt-get install -y openssl >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y openssl >/dev/null 2>&1; }
  elif have dnf; then dnf install -y openssl >/dev/null 2>&1
  elif have yum; then yum install -y openssl >/dev/null 2>&1; fi
  have openssl || { fail "Necesito openssl y no pude instalarlo."; return 1; }
}
tls_on(){
  need_root; [ -f "$SERVER" ] || { fail "Primero instala (opcion 1)."; return 1; }
  if ! python3 "$SERVER" --help 2>/dev/null | grep -q -- '--tls-cert'; then
    fail "El servidor instalado es una version anterior, sin TLS. Actualiza primero con la opcion 1 (Instalar / actualizar)."
    return 1
  fi
  ensure_openssl || return 1
  mkdir -p "$TLS_DIR"; chmod 755 "$TLS_DIR"
  if [ ! -f "$TLS_DIR/cert.pem" ] || [ ! -f "$TLS_DIR/key.pem" ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
      -subj "/CN=$BRAND" -keyout "$TLS_DIR/key.pem" -out "$TLS_DIR/cert.pem" >/dev/null 2>&1 \
      || { fail "No pude crear el certificado."; return 1; }
    ok "Certificado creado (valido 10 anos)."
  fi
  chmod 644 "$TLS_DIR/cert.pem" "$TLS_DIR/key.pem"     # el servicio corre sin privilegios y debe poder leerlos
  local t="${TLS_DIR#"$ROOT"}"
  cfg_set TLS_ARGS "--tls-cert $t/cert.pem --tls-key $t/key.pem"
  ok "TLS activado en TODOS los puertos BHTTP."
  write_unit; restart_all
  echo
  info "En la app: activa 'TLS con SNI (BHTTP)', escribe el dominio que quieras en SNI y,"
  info "si quieres verificar el servidor, pega esta huella SHA-256:"
  echo "   $(tls_fingerprint)"
  warn "Con TLS activo, las conexiones SIN TLS dejan de funcionar: la app debe tener TLS activado."
}
tls_off(){
  need_root
  cfg_set TLS_ARGS ""
  ok "TLS desactivado: los puertos BHTTP vuelven a atender sin TLS."
  write_unit; restart_all
  warn "Ahora la app debe tener TLS desactivado."
}
tls_menu(){
  calc_w; clear 2>/dev/null || true
  title "TLS CON SNI"
  line "Estado:" "$(tls_active && printf 'ACTIVO' || printf 'apagado')"
  local fp; fp="$(tls_fingerprint)"
  [ -n "$fp" ] && line "Huella SHA-256:" "$fp"
  dash
  item 1 "ACTIVAR"; item 2 "DESACTIVAR"; item 3 "SOLO VER LA HUELLA"
  back
  local o; ask_op o
  case "$o" in 1) tls_on;; 2) tls_off;; 3) [ -n "$fp" ] && echo "$fp" || info "Aun no hay certificado: activa TLS primero.";; esac
}

# ---------------------------------------------------------------- estado y autoprueba
show_status(){
  local p inst="NO"
  [ -f "$SERVER" ] && inst="SI"
  echo "================ $BRAND BHTTP v$MANAGER_VERSION ================"
  echo "Servidor instalado : $inst"
  echo "Destino (SSH)      : $(cfg_get BACKEND) ($(listening "$(backend_port)" && echo escuchando || echo 'NO escucha'))"
  echo "Espera de datos    : $(cfg_get POLL_WAIT_MS) ms | Max sesiones: $(cfg_get MAX_SESSIONS) | Max por IP: $(cfg_get MAX_PER_IP) | Inactividad: $(cfg_get IDLE) s"
  echo "Motor              : $(engine_label)"
  echo "TLS con SNI        : $(tls_active && echo "ACTIVO (la app debe usar TLS)" || echo apagado)"
  echo "Ajuste de red      : $(tuning_state) | congestion TCP: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')"
  echo "Puertos BHTTP      :"
  if [ -z "$(ports_list)" ]; then echo "  (ninguno) usa 'agregar puerto'"; fi
  for p in $(ports_list); do
    printf '  %-6s | %-9s | arranque: %-3s | conexiones: %s\n' "$p" \
      "$(systemctl is-active "$(unit_name "$p")" 2>/dev/null || true)" \
      "$(systemctl is-enabled --quiet "$(unit_name "$p")" 2>/dev/null && echo si || echo no)" "$(conn_count "$p")"
  done
}
selftest(){
  local fails=0 p
  echo "===== AUTOPRUEBA $BRAND BHTTP ====="
  if have python3; then ok "python3 $(python3 -V 2>&1 | awk '{print $2}')"; else fail "falta python3"; fails=$((fails+1)); fi
  if [ -f "$SERVER" ] && python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SERVER" 2>/dev/null; then ok "servidor instalado y sin errores de sintaxis"
  else fail "servidor no instalado o danado"; fails=$((fails+1)); fi
  if [ -L "$LAUNCHER" ] && [ -x "$LAUNCHER" ]; then ok "lanzador ${NAME}-server presente"; else fail "falta el lanzador $LAUNCHER (reinstala, opcion 1)"; fails=$((fails+1)); fi
  if [ "$(engine_pick)" = c ]; then
    if "$CBIN" --self-test >/dev/null 2>&1; then ok "motor C activo ($("$CBIN" --self-test 2>/dev/null | sed -n 's/.*calculo: \(.*\))/\1/p'))"
    else fail "el motor C no pasa su autoprueba (usa: $CMD set-engine python)"; fails=$((fails+1)); fi
  else info "motor activo: $(engine_label)"; fi
  if listening "$(backend_port)"; then ok "el destino SSH escucha en :$(backend_port)"
  else fail "nada escucha en el destino :$(backend_port) (revisa el puerto del SSH, opcion 5)"; fails=$((fails+1)); fi
  if [ -z "$(ports_list)" ]; then info "Aun no hay puertos BHTTP: usa 'agregar puerto'."; return $(( fails > 0 )); fi
  for p in $(ports_list); do
    if systemctl is-enabled --quiet "$(unit_name "$p")" 2>/dev/null; then ok ":$p arranca con el sistema"; else fail ":$p NO arranca con el sistema"; fails=$((fails+1)); fi
    if systemctl is-active --quiet "$(unit_name "$p")" 2>/dev/null; then ok ":$p esta activo"; else fail ":$p NO esta activo"; fails=$((fails+1)); continue; fi
    if listening "$p"; then ok ":$p escucha"; else fail ":$p no escucha"; fails=$((fails+1)); continue; fi
    if python3 "$SERVER" --probe "127.0.0.1:$p" $(probe_flags) >/dev/null 2>&1; then ok ":$p responde al sondeo BHP1"; else fail ":$p no responde al sondeo BHP1"; fails=$((fails+1)); fi
  done
  if [ "$fails" -eq 0 ]; then ok "TODO OK"; else fail "$fails problema(s)"; fi
  return $(( fails > 0 ))
}
rollback(){
  need_root
  [ -f "$SERVER.prev" ] || { fail "No hay version anterior guardada."; return 1; }
  cp -a "$SERVER" "$SERVER.tmp" && cp -a "$SERVER.prev" "$SERVER" && mv "$SERVER.tmp" "$SERVER.prev"
  restart_all; ok "Version anterior del servidor restaurada."
}

uninstall_all(){
  need_root
  warn "Esto elimina SOLO $BRAND BHTTP (no toca SSH ni tus otros servicios)."
  confirm_word BHTTP "Desinstalar." || { info "Sin cambios."; return 0; }
  local p
  for p in $(ports_list); do systemctl disable --now "$(unit_name "$p")" >/dev/null 2>&1; fw_close "$p"; done
  [ -f "$SYSCTL_FILE" ] && tuning_off
  rm -f "$UNIT_FILE" "$BIN_LINK" "$SELF_DEST" "$LAUNCHER"
  rm -rf "$APP_DIR" "$CONF_DIR"
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "$BRAND BHTTP desinstalado."
}

# ---------------------------------------------------------------- menu
ui_status(){
  local p inst=NO st
  [ -f "$SERVER" ] && inst=SI
  line "Instalado:" "$inst"
  line "Destino SSH:" "$(cfg_get BACKEND) ($(listening "$(backend_port)" && echo escuchando || echo 'NO escucha'))"
  line "Motor:" "$(engine_label)"
  line "TLS con SNI:" "$(tls_active && echo ACTIVO || echo apagado)"
  line "Ajuste de red:" "$(tuning_state) | TCP: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '?')"
  line "Limites:" "ses $(cfg_get MAX_SESSIONS) | ip $(cfg_get MAX_PER_IP) | idle $(cfg_get IDLE)s"
  if [ -z "$(ports_list)" ]; then line "Puertos:" "(ninguno)"; fi
  for p in $(ports_list); do
    systemctl is-active --quiet "$(unit_name "$p")" 2>/dev/null && st=on || st=off
    printf ' %b%-15s%b %-6s ' "$GY" "Puerto:" "$WH" "$p"; tag "$st"; printf ' %bconexiones: %s%b\n' "$GY" "$(conn_count "$p")" "$C_OFF"
  done
}
menu(){
  need_root
  while true; do
    clear 2>/dev/null || true; calc_w
    title "ADMINISTRADOR BHTTP  v$MANAGER_VERSION"
    ui_status
    dash
    item 1 "INSTALAR / ACTUALIZAR"
    item 2 "ESTADO"
    item 3 "AUTOPRUEBA"
    dash
    item 4 "AGREGAR PUERTO BHTTP"
    item 13 "CERRAR UN PUERTO BHTTP"
    item 5 "CAMBIAR PUERTO DEL SSH (DESTINO)"
    item 6 "CAMBIAR ESPERA DE DATOS (MS)"
    item 7 "CAMBIAR MAX. SESIONES / IP / INACTIVIDAD"
    dash
    item 8 "AJUSTE DE RED (BBR): ACTIVAR/QUITAR"
    item 16 "TLS CON SNI"
    item 17 "CAMBIAR MOTOR (C / PYTHON)"
    dash
    item 9 "REINICIAR"
    item 11 "INICIAR"
    item 12 "DETENER"
    item 10 "VER LOGS"
    item 14 "VOLVER A LA VERSION ANTERIOR" "$OR"
    item 15 "[!] DESINSTALAR" "$OR"
    back
    local op; ask_op op
    case "$op" in
      1) do_install; pause;;
      2) show_status; pause;;
      3) selftest; pause;;
      4) add_port; pause;;
      5) set_backend; pause;;
      6) set_value POLL_WAIT_MS 0 5000 "Espera de datos (ms, 0 = no esperar)"; pause;;
      7) set_value MAX_SESSIONS 1 32768 "Max. sesiones"; set_value MAX_PER_IP 1 4096 "Max. sesiones por IP"; set_value IDLE 10 86400 "Segundos de inactividad"; pause;;
      8) if [ -f "$SYSCTL_FILE" ]; then tuning_off; else tuning_on; fi; pause;;
      9) restart_all; pause;;
      10) show_logs; pause;;
      11) start_all; pause;;
      12) stop_all; pause;;
      13) remove_port; pause;;
      14) rollback; pause;;
      15) uninstall_all; pause;;
      16) tls_menu; pause;;
      17) set_engine; pause;;
      0) exit 0;;
      *) echo "Opcion invalida"; sleep 1;;
    esac
  done
}
usage(){
cat <<EOF
$BRAND BHTTP - administrador v$MANAGER_VERSION
  $CMD                                abre el menu
  $CMD install [--port N]        instala o actualiza (y abre el puerto N)
  $CMD status | selftest | ports
  $CMD add-port N | remove-port N
  $CMD set-backend N             puerto del SSH local (destino)
  $CMD set-poll MS               espera de datos antes de responder vacio
  $CMD set-engine c|python       motor del servidor (C compilado: mucho mas rapido; Python: respaldo / TLS)
  $CMD restart | start | stop | logs
  $CMD tls-on | tls-off | tls-fp ajuste TLS con SNI (la app debe usar lo mismo) y su huella
  $CMD tuning-on | tuning-off    ajuste de red opcional (BBR y buffers)
  $CMD rollback | uninstall
EOF
}

main(){
  local a="${1:-menu}"; shift || true
  case "$a" in
    menu|"") menu;;
    install) if [ "${1:-}" = "--port" ]; then do_install "${2:-}"; else do_install "${1:-}"; fi;;
    status) show_status;;
    selftest|test) selftest;;
    ports) ports_list;;
    add-port) add_port "${1:-}";;
    remove-port) remove_port "${1:-}";;
    set-backend) set_backend "${1:-}";;
    set-poll) set_value POLL_WAIT_MS 0 5000 "Espera de datos (ms)" "${1:-}";;
    set-engine|engine) set_engine "${1:-}";;
    restart) need_root; restart_all;;
    start) need_root; start_all;;
    stop) need_root; stop_all;;
    logs) show_logs;;
    tls-on) tls_on;;
    tls-off) tls_off;;
    tls-fp) tls_fingerprint || { fail "Aun no hay certificado: usa tls-on."; exit 1; };;
    tls) echo "TLS: $(tls_active && echo ACTIVO || echo apagado)"; tls_fingerprint || true;;
    tuning-on) tuning_on;;
    tuning-off) tuning_off;;
    rollback) rollback;;
    uninstall) uninstall_all;;
    help|-h|--help) usage;;
    *) usage; exit 2;;
  esac
}

main "$@"
EMBED_BHTTP_MANAGER_EOF
}
emit_xray_manager(){
cat <<'EMBED_XRAY_MANAGER_EOF'
#!/usr/bin/env bash
# el_tioNel Xray - instala y administra un servidor VLESS + Reality (no necesita dominio ni certificado).
# Lo usa el panel "el_tioNel", pero tambien funciona solo.
# Uso:  el_tioNel-xray                  (menu)
#       el_tioNel-xray install --port 443
set -u

BRAND="el_tioNel"
NAME="${BRAND}-xray"
CMD="$NAME"
MANAGER_VERSION="1.0"
DEFAULT_SNI="www.microsoft.com"

ROOT="${XRAY_ROOT:-}"                        # solo para pruebas
APP_DIR="$ROOT/opt/$NAME"
BIN="$APP_DIR/$NAME"
CONF_DIR="$ROOT/etc/$NAME"
CONFIG="$CONF_DIR/config.json"
STATE="$CONF_DIR/state"
USERS="$CONF_DIR/users"
FW_FILE="$CONF_DIR/firewall-added"
UNIT_FILE="$ROOT/etc/systemd/system/$NAME.service"
SERVICE="$NAME.service"
SELF_DEST="$ROOT/usr/local/sbin/$NAME-manager"
BIN_LINK="$ROOT/usr/local/bin/$CMD"

if [ -t 1 ]; then C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_INF='\033[1;36m'; C_WRN='\033[1;33m'; C_OFF='\033[0m'
else C_OK=''; C_ERR=''; C_INF=''; C_WRN=''; C_OFF=''; fi
# ---- diseno (igual que el panel el_tioNel)
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UI_UTF=1;; *) UI_UTF=0;; esac
if [ "$UI_UTF" -eq 1 ]; then HZ='═'; else HZ='='; fi
if [ -t 1 ]; then RD='\033[1;31m'; WH='\033[1;37m'; GY='\033[0;37m'; OR='\033[38;5;208m'; GN='\033[1;32m'; BGR='\033[41;1;37m'
else RD=''; WH=''; GY=''; OR=''; GN=''; BGR=''; fi
W=54
calc_w(){ local c; c="$(tput cols 2>/dev/null || echo 54)"; [[ "$c" =~ ^[0-9]+$ ]] || c=54
  [ "$c" -gt 54 ] && c=54; [ "$c" -lt 40 ] && c=40; W="$c"; }
rep_char(){ local i out=""; for ((i = 0; i < $2; i++)); do out+="$1"; done; printf '%s' "$out"; }
hl(){ printf '%b%s%b\n' "$RD" "$(rep_char "$HZ" "$W")" "$C_OFF"; }
dash(){ printf '%b%s%b\n' "$RD" "$(rep_char "-" "$W")" "$C_OFF"; }
title(){ local t="$1" pad; pad=$(( (W - ${#t}) / 2 )); [ "$pad" -lt 0 ] && pad=0
  hl; printf '%*s%b%s%b\n' "$pad" "" "$GY" "$t" "$C_OFF"; hl; }
item(){ local col="${3:-$WH}"; printf ' %b[%s]%b>%b %b%s%b\n' "$GY" "$1" "$RD" "$C_OFF" "$col" "$2" "$C_OFF"; }
tag(){ case "$1" in on) printf '%b%s%b' "$GN" "[ON]" "$C_OFF";; off) printf '%b%s%b' "$RD" "[OFF]" "$C_OFF";; *) printf '%b%s%b' "$GY" "[--]" "$C_OFF";; esac; }
line(){ printf ' %b%-15s%b %s\n' "$GY" "$1" "$WH" "$2"; printf '%b' "$C_OFF"; }
back(){ hl; printf ' %b[0]%b %b %s %b\n' "$GY" "$C_OFF" "$BGR" "${1:-Volver}" "$C_OFF"; hl; }
ask_op(){ ask "$1" "$(printf '\n%b Ingresa una Opcion: %b' "$GY" "$C_OFF")"; }
ok(){ printf '%b✔%b %s\n' "$C_OK" "$C_OFF" "$*"; }
info(){ printf '%bℹ%b %s\n' "$C_INF" "$C_OFF" "$*"; }
warn(){ printf '%b⚠%b %s\n' "$C_WRN" "$C_OFF" "$*"; }
fail(){ printf '%b✘%b %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
need_root(){ [ -n "${XRAY_TEST:-}" ] && return 0; [ "$(id -u)" -eq 0 ] || { fail "Ejecuta como root."; exit 1; }; }
ask(){ local __v="$1"; IFS= read -r -p "$2" "$__v" || eval "$__v=''"; }
pause(){ [ -t 0 ] || return 0; echo; local _; ask _ "Presiona ENTER para continuar..."; }
confirm_word(){ [ -n "${XRAY_YES:-}" ] && return 0; local c; ask c "$2 Escribe $1 para confirmar: "; [ "$c" = "$1" ]; }
valid_port(){ [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_host(){ [[ "${1:-}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]] && [[ "$1" == *.* ]]; }
listening(){ ss -lnt 2>/dev/null | awk -v p=":$1" '$4 ~ p"$" {f=1} END{exit !f}'; }

# ---- estado (clave=valor, se lee sin ejecutarlo)
st_get(){ grep -m1 "^$1=" "$STATE" 2>/dev/null | cut -d= -f2-; }
st_set(){
  local k="$1" v="$2"; mkdir -p "$CONF_DIR"; touch "$STATE"
  grep -v "^$k=" "$STATE" > "$STATE.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$k" "$v" >> "$STATE.tmp"; mv "$STATE.tmp" "$STATE"; chmod 600 "$STATE"
}
installed(){ [ -x "$BIN" ] && [ -f "$STATE" ]; }

# ---- firewall (solo toca lo que el mismo abrio)
ufw_active(){ have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; }
firewalld_active(){ have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; }
fw_open(){
  local p="$1"; mkdir -p "$CONF_DIR"
  if ufw_active; then
    if ufw status 2>/dev/null | grep -Eq "(^|[[:space:]])${p}/tcp([[:space:]]|$)"; then info "ufw: $p/tcp ya estaba permitido."
    else ufw allow "${p}/tcp" >/dev/null && echo "ufw $p" >> "$FW_FILE" && ok "ufw: puerto $p/tcp abierto."; fi
  elif firewalld_active; then
    if firewall-cmd --query-port="${p}/tcp" >/dev/null 2>&1; then info "firewalld: $p/tcp ya estaba permitido."
    else firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null && firewall-cmd --reload >/dev/null && echo "firewalld $p" >> "$FW_FILE" && ok "firewalld: puerto $p/tcp abierto."; fi
  else info "No detecte ufw ni firewalld activos. Si usas iptables a mano o el firewall del proveedor, abre TCP $p."; fi
}
fw_close(){
  local p="$1"; [ -f "$FW_FILE" ] || return 0
  if grep -qx "ufw $p" "$FW_FILE" && have ufw; then ufw delete allow "${p}/tcp" >/dev/null 2>&1; ok "ufw: puerto $p/tcp cerrado."; fi
  if grep -qx "firewalld $p" "$FW_FILE" && have firewall-cmd; then firewall-cmd --permanent --remove-port="${p}/tcp" >/dev/null 2>&1; firewall-cmd --reload >/dev/null 2>&1; ok "firewalld: puerto $p/tcp cerrado."; fi
  grep -vxE "(ufw|firewalld) $p" "$FW_FILE" > "$FW_FILE.tmp" || true; mv "$FW_FILE.tmp" "$FW_FILE"
}

# ---- motor Xray (oficial, con verificacion SHA-256)
arch_asset(){ case "$(uname -m)" in x86_64|amd64) echo Xray-linux-64;; aarch64|arm64) echo Xray-linux-arm64-v8a;; *) echo "";; esac; }
ensure_tools(){
  local missing=0 c; for c in curl unzip sha256sum; do have "$c" || missing=1; done
  [ "$missing" -eq 0 ] && return 0
  info "Instalando herramientas (curl, unzip)..."
  if have apt-get; then DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip ca-certificates >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip ca-certificates >/dev/null 2>&1; }
  elif have dnf; then dnf install -y curl unzip ca-certificates >/dev/null 2>&1
  elif have yum; then yum install -y curl unzip ca-certificates >/dev/null 2>&1; fi
  for c in curl unzip sha256sum; do have "$c" || { fail "Falta '$c' y no pude instalarlo."; return 1; }; done
}
install_core(){
  local asset base tmp want got
  asset="$(arch_asset)"; [ -n "$asset" ] || { fail "Arquitectura no soportada: $(uname -m) (solo x86_64 y arm64)."; return 1; }
  ensure_tools || return 1
  base="${XRAY_BASE_URL:-https://github.com/XTLS/Xray-core/releases/latest/download}"
  tmp="$(mktemp -d)"
  info "Descargando Xray ($asset)..."
  curl -fL --retry 3 --connect-timeout 15 -o "$tmp/x.zip" "$base/$asset.zip" 2>/dev/null || { fail "No pude descargar Xray."; rm -rf "$tmp"; return 1; }
  curl -fL --retry 3 --connect-timeout 15 -o "$tmp/x.dgst" "$base/$asset.zip.dgst" 2>/dev/null || { fail "No pude descargar la huella oficial (.dgst)."; rm -rf "$tmp"; return 1; }
  want="$(sed -n 's/^SHA2-256= *\([0-9a-fA-F]\{64\}\).*/\1/p' "$tmp/x.dgst" | head -1 | tr 'A-F' 'a-f')"
  got="$(sha256sum "$tmp/x.zip" | awk '{print $1}')"
  if [ -z "$want" ] || [ "$want" != "$got" ]; then fail "La huella SHA-256 de Xray NO coincide con la oficial: no se instala."; rm -rf "$tmp"; return 1; fi
  unzip -qo "$tmp/x.zip" xray -d "$tmp/ex" 2>/dev/null || { fail "No pude extraer el binario de Xray."; rm -rf "$tmp"; return 1; }
  mkdir -p "$APP_DIR"; chmod 755 "$APP_DIR"
  install -m 755 "$tmp/ex/xray" "$BIN"; rm -rf "$tmp"
  "$BIN" version >/dev/null 2>&1 || { fail "El binario de Xray no arranca en este servidor."; return 1; }
  ok "Xray verificado por SHA-256: $("$BIN" version 2>/dev/null | head -1)"
}

# ---- llaves, usuarios, configuracion
gen_keys(){
  local out priv pub
  out="$("$BIN" x25519 2>&1)" || { fail "xray x25519 fallo: $out"; return 1; }
  priv="$(printf '%s\n' "$out" | sed -n 's/^[Pp]rivate[ ]*[Kk]ey:[ ]*//p' | head -1 | tr -d '\r ')"
  pub="$(printf '%s\n' "$out" | sed -n 's/^[Pp]ublic[ ]*[Kk]ey:[ ]*//p' | head -1 | tr -d '\r ')"
  [ -n "$pub" ] || pub="$(printf '%s\n' "$out" | sed -n 's/^Password[^:]*:[ ]*//p' | head -1 | tr -d '\r ')"
  if ! [[ "$priv" =~ ^[A-Za-z0-9_-]{43}$ ]] || ! [[ "$pub" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
    fail "No pude leer las llaves que genero Xray. Su salida fue:"; printf '%s\n' "$out" >&2; return 1
  fi
  st_set PRIV "$priv"; st_set PUB "$pub"
}
new_uuid(){ cat /proc/sys/kernel/random/uuid; }
new_sid(){ head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
build_config(){
  local port sni priv sid clients="" u first=1
  port="$(st_get PORT)"; sni="$(st_get SNI)"; priv="$(st_get PRIV)"; sid="$(st_get SID)"
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    [ "$first" -eq 1 ] || clients+=","
    clients+="{\"id\":\"$u\",\"flow\":\"xtls-rprx-vision\"}"; first=0
  done < "$USERS"
  [ "$first" -eq 0 ] || { fail "No hay usuarios."; return 1; }
  cat > "$CONFIG" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [$clients], "decryption": "none"},
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "$sni:443",
        "xver": 0,
        "serverNames": ["$sni"],
        "privateKey": "$priv",
        "shortIds": ["$sid"]
      }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
  }],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "block"}
  ]
}
EOF
  chmod 644 "$CONFIG"
  local out; out="$("$BIN" run -test -config "$CONFIG" 2>&1)" || { fail "Xray rechazo la configuracion:"; printf '%s\n' "$out" >&2; return 1; }
}
make_link(){
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s\n' \
    "$1" "$(st_get IP)" "$(st_get PORT)" "$(st_get SNI)" "$(st_get PUB)" "$(st_get SID)" "$BRAND"
}
show_links(){
  installed || { fail "No esta instalado."; return 1; }
  local u n=0
  echo "Pega este enlace en la app (boton V2Ray):"; echo
  while IFS= read -r u; do [ -n "$u" ] || continue; n=$((n+1)); echo "Usuario $n:"; make_link "$u"; echo; done < "$USERS"
}
detect_ip(){
  local ip=""
  have curl && ip="$(curl -4fsS --max-time 6 https://api.ipify.org 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

# ---- servicio
write_unit(){
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<'UNIT_EOF'
[Unit]
Description=__BRAND__ Xray (VLESS Reality)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=__BIN__ run -config __CONFIG__
Restart=always
RestartSec=2
LimitNOFILE=65535
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT_EOF
  sed -i -e "s|__BRAND__|$BRAND|" -e "s|__BIN__|${BIN#"$ROOT"}|" -e "s|__CONFIG__|${CONFIG#"$ROOT"}|" "$UNIT_FILE"
  systemctl daemon-reload
}
install_self(){
  local src="${BASH_SOURCE[0]:-$0}"
  if [ -f "$src" ] && [ -r "$src" ]; then
    mkdir -p "$(dirname "$SELF_DEST")" "$(dirname "$BIN_LINK")"
    [ "$(readlink -f "$src")" = "$(readlink -f "$SELF_DEST" 2>/dev/null)" ] || cp "$src" "$SELF_DEST"
    chmod 755 "$SELF_DEST"; ln -sfn "$SELF_DEST" "$BIN_LINK"; ok "Comando instalado: $CMD"
  else warn "No instale el comando '$CMD' (ejecuta el archivo guardado en disco, no por pipe)."; fi
}

do_install(){
  need_root
  local port="" sni=""
  while [ $# -gt 0 ]; do case "$1" in --port) port="${2:-}"; shift 2;; --sni) sni="${2:-}"; shift 2;; *) shift;; esac; done
  if installed; then warn "Ya esta instalado. Usa 'status' o 'links'; para empezar de cero, desinstala primero."; return 0; fi
  [ -n "$port" ] || { if [ -t 0 ]; then ask port "Puerto TCP del servidor [443]: "; fi; port="${port:-443}"; }
  valid_port "$port" || { fail "Puerto invalido."; return 1; }
  if listening "$port"; then
    fail "El puerto $port ya esta ocupado por otro servicio (por ejemplo un panel o stunnel). Elige otro, p. ej.: install --port 8443"
    ss -lntp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$"'; return 1
  fi
  sni="${sni:-$DEFAULT_SNI}"; valid_host "$sni" || { fail "Sitio de camuflaje invalido: $sni"; return 1; }
  install_core || return 1
  mkdir -p "$CONF_DIR"; : > "$STATE"; chmod 600 "$STATE"
  st_set PORT "$port"; st_set SNI "$sni"; st_set SID "$(new_sid)"
  gen_keys || return 1
  new_uuid > "$USERS"
  local ip; ip="$(detect_ip)"
  if [ -z "$ip" ] && [ -t 0 ]; then ask ip "No pude detectar la IP publica. Escribela: "; fi
  [ -n "$ip" ] || { fail "Sin IP del servidor."; return 1; }
  st_set IP "$ip"
  build_config || return 1
  write_unit; install_self
  systemctl enable --now "$SERVICE" >/dev/null 2>&1; sleep 1
  if listening "$port"; then ok "Servidor activo en :$port con arranque automatico."; fw_open "$port"
  else fail "No quedo activo. Revisa: journalctl -u $SERVICE -n 50"; return 1; fi
  echo; show_links
  info "Camuflaje (Reality): $sni. El VPS debe poder abrir https://$sni."
}
add_user(){
  need_root; installed || { fail "No esta instalado."; return 1; }
  local u; u="$(new_uuid)"; echo "$u" >> "$USERS"
  build_config || { grep -vx "$u" "$USERS" > "$USERS.tmp"; mv "$USERS.tmp" "$USERS"; return 1; }
  systemctl restart "$SERVICE"; ok "Usuario agregado."; echo; make_link "$u"
}
del_user(){
  need_root; installed || { fail "No esta instalado."; return 1; }
  local u="${1:-}"; [ -n "$u" ] || { show_links; ask u "UUID a eliminar: "; }
  grep -qx "$u" "$USERS" || { fail "Ese UUID no existe."; return 1; }
  [ "$(grep -c . "$USERS")" -gt 1 ] || { fail "No puedes borrar el ultimo usuario."; return 1; }
  grep -vx "$u" "$USERS" > "$USERS.tmp"; mv "$USERS.tmp" "$USERS"
  build_config && systemctl restart "$SERVICE" && ok "Usuario eliminado."
}
set_ip(){ need_root; installed || { fail "No esta instalado."; return 1; }; local v="${1:-}"; [ -n "$v" ] || ask v "IP o dominio del servidor [$(st_get IP)]: "; [ -n "$v" ] && st_set IP "$v" && ok "Listo."; }
show_status(){
  echo "============ $BRAND Xray v$MANAGER_VERSION ============"
  if ! installed; then echo "Instalado: NO"; return 0; fi
  echo "Instalado  : SI ($("$BIN" version 2>/dev/null | head -1))"
  echo "Servicio   : $(systemctl is-active "$SERVICE" 2>/dev/null || true) | arranque: $(systemctl is-enabled --quiet "$SERVICE" 2>/dev/null && echo si || echo no)"
  echo "Puerto     : $(st_get PORT) ($(listening "$(st_get PORT)" && echo escuchando || echo 'NO escucha'))"
  echo "Camuflaje  : $(st_get SNI) | IP: $(st_get IP) | Usuarios: $(grep -c . "$USERS")"
}
selftest(){
  local f=0
  installed && ok "instalado" || { fail "no esta instalado"; return 1; }
  "$BIN" run -test -config "$CONFIG" >/dev/null 2>&1 && ok "configuracion valida" || { fail "configuracion invalida"; f=$((f+1)); }
  systemctl is-active --quiet "$SERVICE" 2>/dev/null && ok "servicio activo" || { fail "servicio inactivo"; f=$((f+1)); }
  listening "$(st_get PORT)" && ok "escucha en :$(st_get PORT)" || { fail "no escucha en :$(st_get PORT)"; f=$((f+1)); }
  [ "$f" -eq 0 ] && ok "TODO OK" || fail "$f problema(s)"; return $(( f > 0 ))
}
do_uninstall(){
  need_root; warn "Esto elimina SOLO $BRAND Xray (no toca SSH ni tus otros servicios)."
  confirm_word XRAY "Desinstalar." || { info "Sin cambios."; return 0; }
  local p; p="$(st_get PORT)"
  systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
  [ -n "$p" ] && fw_close "$p"
  rm -f "$UNIT_FILE" "$BIN_LINK" "$SELF_DEST"; rm -rf "$APP_DIR" "$CONF_DIR"
  systemctl daemon-reload >/dev/null 2>&1 || true; ok "$BRAND Xray desinstalado."
}
ui_status(){
  if ! installed; then line "Instalado:" "NO"; return 0; fi
  local st; systemctl is-active --quiet "$SERVICE" 2>/dev/null && st=on || st=off
  printf ' %b%-15s%b ' "$GY" "Servicio:" "$WH"; tag "$st"
  printf ' %barranque: %s%b\n' "$GY" "$(systemctl is-enabled --quiet "$SERVICE" 2>/dev/null && echo si || echo no)" "$C_OFF"
  line "Puerto:" "$(st_get PORT) ($(listening "$(st_get PORT)" && echo escuchando || echo 'NO escucha'))"
  line "Camuflaje:" "$(st_get SNI)"
  line "IP:" "$(st_get IP)"
  line "Usuarios:" "$(grep -c . "$USERS" 2>/dev/null || echo 0)"
}
menu(){
  need_root
  while true; do
    clear 2>/dev/null || true; calc_w
    title "ADMINISTRADOR V2RAY / XRAY  v$MANAGER_VERSION"
    ui_status
    dash
    item 1 "INSTALAR"
    item 2 "VER ENLACES"
    dash
    item 3 "AGREGAR USUARIO"
    item 4 "QUITAR USUARIO" "$OR"
    dash
    item 5 "REINICIAR"
    item 6 "VER LOGS"
    item 7 "AUTOPRUEBA"
    item 8 "[!] DESINSTALAR" "$OR"
    back
    local op; ask_op op
    case "$op" in
      1) do_install; pause;; 2) show_links; pause;; 3) add_user; pause;; 4) del_user; pause;;
      5) need_root; systemctl restart "$SERVICE"; ok "Reiniciado."; pause;;
      6) journalctl -u "$SERVICE" -n 60 --no-pager 2>/dev/null || true; pause;;
      7) selftest; pause;; 8) do_uninstall; pause;; 0) exit 0;; *) echo "Opcion invalida"; sleep 1;;
    esac
  done
}
usage(){ cat <<EOF
$BRAND Xray (VLESS + Reality) - v$MANAGER_VERSION
  $CMD                                 menu
  $CMD install [--port N] [--sni sitio.com]
  $CMD links | add-user | del-user [UUID] | set-ip [IP]
  $CMD status | selftest | restart | logs | uninstall
EOF
}
main(){
  local a="${1:-menu}"; shift || true
  case "$a" in
    menu|"") menu;; install) do_install "$@";; links|link) show_links;; add-user) add_user;; del-user) del_user "${1:-}";;
    set-ip) set_ip "${1:-}";; status) show_status;; selftest|test) selftest;;
    restart) need_root; systemctl restart "$SERVICE";; logs) journalctl -u "$SERVICE" -n 80 --no-pager 2>/dev/null || true;;
    uninstall) do_uninstall;; help|-h|--help) usage;; *) usage; exit 2;;
  esac
}
main "$@"
EMBED_XRAY_MANAGER_EOF
}
write_subs(){
  mkdir -p "$SBIN" "$UBIN"
  emit_bhttp_manager > "$BH_MGR"; chmod 755 "$BH_MGR"; ln -sfn "$BH_MGR" "$BH_LINK"
  emit_xray_manager  > "$XR_MGR"; chmod 755 "$XR_MGR"; ln -sfn "$XR_MGR" "$XR_LINK"
}
install_panel(){
  local src; src="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")"
  mkdir -p "$SBIN" "$UBIN"
  # Copia normal: esto corre desde un archivo de verdad en disco (el .sh tal
  # cual, no un binario compilado) y no esta en /tmp.
  if [ -f "$src" ] && [ -r "$src" ] && [[ "$src" != /tmp/* ]]; then
    [ "$(readlink -f "$src")" = "$(readlink -f "$PANEL_DEST" 2>/dev/null)" ] || cp "$src" "$PANEL_DEST"
    chmod 755 "$PANEL_DEST"; ln -sfn "$PANEL_DEST" "$PANEL_LINK"
    return 0
  fi
  # Si no es un archivo normal legible fuera de /tmp, puede ser un binario
  # compilado con shc (que entrega el script por una tuberia/temporal, no
  # como archivo normal) o alguien corriendolo por pipe (curl | bash). Si el
  # panel YA esta instalado (lo pusiste tu a mano al compilar), no lo tocamos:
  # evita pisar el binario protegido con una copia de ese temporal sin compilar.
  if [ -e "$PANEL_DEST" ]; then
    ln -sfn "$PANEL_DEST" "$PANEL_LINK"; return 0
  fi
  fail "Ejecuta el archivo guardado en disco, no por pipe (curl | bash)."; return 1
}

# =====================================================================
#  PANEL v3 - diseno estilo ADMRufu + BADVPN-UDPGW + usuarios HWID/SSH
# =====================================================================
UG_DIR="$ROOT/etc/${BRAND}-udpgw";  UG_PORTS="$UG_DIR/ports"
UG_UNIT="$ROOT/etc/systemd/system/${BRAND}-udpgw@.service"
USR_DB="$ROOT/etc/${BRAND}/users.db"
CRON_FILE="$ROOT/etc/cron.d/${BRAND}-expire"
CLEAN_CONF="$ROOT/etc/${BRAND}/cleanup.conf"
CLEAN_CRON="$ROOT/etc/cron.d/${BRAND}-cleanup"
PANEL_IP=""

# ---- colores del panel (rojo/blanco/gris como en las capturas)
if [ -t 1 ] || [ -n "${TIONEL_COLOR:-}" ]; then
  RD='\033[1;31m'; WH='\033[1;37m'; GY='\033[0;37m'; OR='\033[38;5;208m'
  GN='\033[1;32m'; YL='\033[1;33m'; BGR='\033[41;1;37m'; BGB='\033[44;1;37m'
else RD=''; WH=''; GY=''; OR=''; GN=''; YL=''; BGR=''; BGB=''; fi
if [ "$UTF" -eq 1 ]; then LT='╠'; RT='╣'; else LT='+'; RT='+'; fi

W=54
calc_w(){ local c; c="$(tput cols 2>/dev/null || echo 54)"; [[ "$c" =~ ^[0-9]+$ ]] || c=54
  [ "$c" -gt 54 ] && c=54; [ "$c" -lt 40 ] && c=40; W="$c"; }

# ---- piezas de dibujo
hl(){ printf '%b%s%b\n' "$RD" "$(rep_char "$HZ" "$W")" "$C_O"; }
dash(){ printf '%b%s%b\n' "$RD" "$(rep_char "-" "$W")" "$C_O"; }
title(){ local t="$1" pad; pad=$(( (W - ${#t}) / 2 )); [ "$pad" -lt 0 ] && pad=0
  hl; printf '%*s%b%s%b\n' "$pad" "" "$GY" "$t" "$C_O"; hl; }
item(){ local col="${3:-$WH}"; printf ' %b[%s]%b>%b %b%s%b\n' "$GY" "$1" "$RD" "$C_O" "$col" "$2" "$C_O"; }
tag(){ case "$1" in on) printf '%b%-5s%b' "$GN" "[ON]" "$C_O";; off) printf '%b%-5s%b' "$RD" "[OFF]" "$C_O";;
  *) printf '%b%-5s%b' "$GY" "[--]" "$C_O";; esac; }
pitem(){ printf ' %b[%s]%b>%b %b%-20s%b ' "$GY" "$1" "$RD" "$C_O" "$WH" "$2" "$C_O"; tag "$3"; printf ' %b%s%b\n' "$GY" "${4:-}" "$C_O"; }
boxtop(){ printf '%b%s%s%s%b\n' "$RD" "$TL" "$(rep_char "$HZ" $((W - 2)))" "$TR" "$C_O"; }
boxbot(){ printf '%b%s%s%s%b\n' "$RD" "$BL" "$(rep_char "$HZ" $((W - 2)))" "$BRR" "$C_O"; }
boxlbl(){ local l="$1" n; n=$(( (W - 2 - ${#l}) / 2 ))
  printf '%b%s%s%s%s%s%b\n' "$RD" "$LT" "$(rep_char "$HZ" "$n")" "$l" "$(rep_char "$HZ" $((W - 2 - n - ${#l})))" "$RT" "$C_O"; }
bl_c=""; bl_n=0
kv(){ local l="$1" v="$2" cw="$3" room pad; room=$((cw - ${#l})); v="${v:0:$room}"; pad=$((cw - ${#l} - ${#v}))
  bl_c+="${GY}${l}${WH}${v}${C_O}$(printf '%*s' "$pad" '')"; bl_n=$((bl_n + cw)); }
brow(){ printf '%b%s%b %b%*s%b%s%b\n' "$RD" "$VT" "$C_O" "$bl_c" $((W - 3 - bl_n)) "" "$RD" "$VT" "$C_O"; bl_c=""; bl_n=0; }
ask_op(){ ask "$1" "$(printf '\n%b Ingresa una Opcion: %b' "$GY" "$C_O")"; }

sysinfo(){
  local tot used fr
  read -r tot used fr <<<"$(free -m 2>/dev/null | awk '/^Mem:/ {print $2, $3, $7}')"
  tot="${tot:-0}"; used="${used:-0}"; fr="${fr:-0}"
  boxtop
  kv "S.O: " "$(os_name)" 30; kv "Fecha: " "$(date +%d-%m-%Y)" 20; brow
  kv "IP: " "$PANEL_IP" 30;   kv "Hora: " "$(date +%T)" 20; brow
  boxlbl "ram"
  kv "Total: " "$(awk -v m="$tot" 'BEGIN{printf "%.2fGB", m/1024}')" 16
  kv "En Uso: " "${used}MB" 17; kv "Libre: " "${fr}MB" 17; brow
  boxbot
}

# ---- estado de cada servicio
bh_ports(){ [ -f "$BH_PORTS" ] && grep -E '^[0-9]+$' "$BH_PORTS" | sort -n -u | tr '\n' ' ' | sed 's/ $//' || true; }
bh_installed(){ [ -f "$BH_APP" ]; }
bh_tls(){ grep -q '^TLS_ARGS=.' "$ROOT/etc/${BRAND}-bhttp/config" 2>/dev/null; }
bh_active(){ local p; for p in $(bh_ports); do systemctl is-active --quiet "${BRAND}-bhttp@$p.service" 2>/dev/null && return 0; done; return 1; }
xr_installed(){ [ -x "$XR_BIN" ] && [ -f "$XR_STATE" ]; }
xr_port(){ grep -m1 '^PORT=' "$XR_STATE" 2>/dev/null | cut -d= -f2; }
xr_active(){ systemctl is-active --quiet "${BRAND}-xray.service" 2>/dev/null; }
hy_active(){ pgrep -f '[h]ysteria' >/dev/null 2>&1 || systemctl list-units --type=service --state=active 2>/dev/null | grep -qi hysteria; }
hy_port(){ ss -ulnp 2>/dev/null | grep -i hysteria | awk '{print $5}' | sed 's/.*://' | head -1; }
bbr_on(){ [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; }
ufw_on(){ have ufw && ufw status 2>/dev/null | grep -q '^Status: active'; }
conn_count(){ ss -tan 2>/dev/null | awk -v p=":$1" '$1=="ESTAB" && $4 ~ p"$" {n++} END{print n+0}'; }

public_ip(){
  local ip=""
  have curl && ip="$(curl -4fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "${ip:-?}"
}
os_name(){ ( . /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" ) || printf 'Linux'; }

# =====================================================================
#  BADVPN-UDPGW  (escucha en 127.0.0.1: se usa a traves del tunel SSH)
# =====================================================================
ug_ports(){ [ -f "$UG_PORTS" ] && grep -E '^[0-9]+$' "$UG_PORTS" | sort -n -u | tr '\n' ' ' | sed 's/ $//' || true; }
ug_installed(){ [ -f "$UG_UNIT" ]; }
ug_has(){ ug_ports | tr ' ' '\n' | grep -qx "$1"; }
ug_unit(){ echo "${BRAND}-udpgw@$1.service"; }
ug_active(){ local p; for p in $(ug_ports); do systemctl is-active --quiet "$(ug_unit "$p")" 2>/dev/null && return 0; done; return 1; }
valid_port(){ [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

ug_bin(){ command -v badvpn-udpgw 2>/dev/null || { [ -x "$UBIN/badvpn-udpgw" ] && echo "$UBIN/badvpn-udpgw"; } || true; }
ug_get_binary(){
  [ -n "$(ug_bin)" ] && return 0
  have apt-get || { fail "No hay apt-get: instala badvpn-udpgw a mano y vuelve a intentar."; return 1; }
  info "Instalando badvpn desde los repositorios..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y badvpn >/dev/null 2>&1 || true
  [ -n "$(ug_bin)" ] && return 0
  info "No esta en los repositorios: compilando desde el codigo fuente (tarda un par de minutos)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y cmake build-essential git >/dev/null 2>&1 || { fail "No pude instalar cmake/gcc/git."; return 1; }
  local tmp; tmp="$(mktemp -d)"
  if git clone --depth 1 https://github.com/ambrop72/badvpn "$tmp/b" >/dev/null 2>&1 \
     && cmake -S "$tmp/b" -B "$tmp/b/build" -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1 \
     && make -C "$tmp/b/build" -j"$(nproc 2>/dev/null || echo 1)" >/dev/null 2>&1 \
     && install -m 755 "$tmp/b/build/udpgw/badvpn-udpgw" "$UBIN/badvpn-udpgw"; then
    rm -rf "$tmp"; ok "badvpn-udpgw compilado."; return 0
  fi
  rm -rf "$tmp"; fail "No pude compilar badvpn-udpgw (revisa tu conexion a internet)."; return 1
}
ug_write_unit(){
  local bin; bin="$(ug_bin)"; [ -n "$bin" ] || return 1
  mkdir -p "$(dirname "$UG_UNIT")"
  cat > "$UG_UNIT" <<EOF
[Unit]
Description=$BRAND BADVPN-UDPGW (puerto %i)
After=network.target

[Service]
ExecStart=$bin --listen-addr 127.0.0.1:%i --max-clients 1000 --max-connections-for-client 10 --loglevel 1
Restart=always
RestartSec=2
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
}
ug_add_port(){
  local p="$1"
  valid_port "$p" || { fail "Puerto invalido: $p"; return 1; }
  if ! ug_has "$p" && listening "$p"; then fail "El puerto $p ya esta en uso por otro programa."; return 1; fi
  mkdir -p "$UG_DIR"; ug_has "$p" || echo "$p" >> "$UG_PORTS"
  systemctl enable --now "$(ug_unit "$p")" >/dev/null 2>&1
  sleep 1
  if systemctl is-active --quiet "$(ug_unit "$p")" 2>/dev/null; then ok "BADVPN-UDPGW activo en 127.0.0.1:$p"
  else fail "No arranco el puerto $p (mira: journalctl -u $(ug_unit "$p"))"; return 1; fi
}
ug_del_port(){
  local p="$1"; ug_has "$p" || { fail "Ese puerto no esta configurado."; return 1; }
  systemctl disable --now "$(ug_unit "$p")" >/dev/null 2>&1 || true
  grep -vx "$p" "$UG_PORTS" > "$UG_PORTS.tmp" || true; mv "$UG_PORTS.tmp" "$UG_PORTS"
  ok "Puerto $p eliminado."
}
ug_install(){
  need_root; ug_get_binary || return 1; ug_write_unit || { fail "No pude crear el servicio."; return 1; }
  local ps p; ask ps " Puertos [7100 7200 7300]: "; ps="${ps:-7100 7200 7300}"
  for p in ${ps//,/ }; do ug_add_port "$p" || true; done
  echo; info "En HTTP Custom / tu app activa UDPGW con la direccion 127.0.0.1 y uno de esos puertos."
}
ug_uninstall(){
  need_root; confirm_word BORRAR "Se quitara BADVPN-UDPGW de este panel." || { info "Sin cambios."; return 0; }
  ug_installed || return 0
  local p; for p in $(ug_ports); do systemctl disable --now "$(ug_unit "$p")" >/dev/null 2>&1 || true; done
  rm -f "$UG_UNIT"; rm -rf "$UG_DIR"; systemctl daemon-reload >/dev/null 2>&1 || true
  ok "BADVPN-UDPGW desinstalado."
}
ug_menu(){
  need_root; local op p
  while true; do
    clear 2>/dev/null || true; calc_w
    title "ADMINISTRADOR BADVPN-UDPGW"
    if ug_installed; then
      printf ' %bPuertos:%b %s   ' "$GY" "$WH" "$(ug_ports)"; ug_active && tag on || tag off; echo
    else printf ' %bBADVPN-UDPGW sin instalar%b\n' "$GY" "$C_O"; fi
    dash
    item 1 "INSTALAR / REINSTALAR"
    item 2 "AGREGAR PUERTO"
    item 3 "QUITAR PUERTO"
    item 4 "REINICIAR"
    item 5 "DETENER"
    item 6 "VER LOGS"
    item 7 "[!] DESINSTALAR" "$OR"
    hl; printf ' %b[0]%b %b Volver %b\n' "$GY" "$C_O" "$BGR" "$C_O"; hl
    ask_op op
    case "$op" in
      1) ug_install; pause;;
      2) ug_installed || { warn "Primero instala (opcion 1)."; pause; continue; }
         ask p " Nuevo puerto: "; ug_add_port "$p"; pause;;
      3) ug_installed || { warn "No esta instalado."; pause; continue; }
         ask p " Puerto a quitar [$(ug_ports)]: "; ug_del_port "$p"; pause;;
      4) if ug_installed; then for p in $(ug_ports); do systemctl restart "$(ug_unit "$p")"; done; ok "Reiniciado."; else warn "No esta instalado."; fi; pause;;
      5) for p in $(ug_ports); do systemctl stop "$(ug_unit "$p")"; done; warn "Detenido (vuelve a arrancar con Reiniciar)."; pause;;
      6) ask p " Puerto [$(ug_ports | awk '{print $1}')]: "; p="${p:-$(ug_ports | awk '{print $1}')}"
         journalctl -u "$(ug_unit "$p")" -n 50 --no-pager 2>/dev/null || info "Sin logs."; pause;;
      7) ug_uninstall; pause;;
      0) return 0;;
      *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}

# =====================================================================
#  USUARIOS HWID / SSH  (cuentas del sistema con fecha de vencimiento)
#  HWID: el HWID del dispositivo se usa como clave de la cuenta.
#  Solo se tocan usuarios creados desde este panel (users.db).
# =====================================================================
db_all(){ [ -f "$USR_DB" ] && grep -E '^[^|#]+\|' "$USR_DB" || true; }
db_row(){ [ -f "$USR_DB" ] && awk -F'|' -v u="$1" '$1==u' "$USR_DB" | head -1 || true; }
db_field(){ db_row "$1" | cut -d'|' -f"$2"; }
db_del(){ [ -f "$USR_DB" ] || return 0; awk -F'|' -v u="$1" '$1!=u' "$USR_DB" > "$USR_DB.tmp"; mv "$USR_DB.tmp" "$USR_DB"; chmod 600 "$USR_DB"; }
db_put(){ mkdir -p "$(dirname "$USR_DB")"; [ -f "$USR_DB" ] || : > "$USR_DB"; db_del "$1"
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$USR_DB"; chmod 600 "$USR_DB"; }
days_left(){ local e t; e="$(date -u -d "$1" +%s 2>/dev/null)" || { echo -9999; return; }
  t="$(date -u -d "$(date +%F)" +%s)"; echo $(( (e - t) / 86400 )); }
user_locked(){ passwd -S "$1" 2>/dev/null | awk '{print $2}' | grep -q '^L'; }
valid_user(){ [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{2,15}$ ]]; }
valid_hwid(){ local h="${1:-}"; [ -n "$h" ] && [ "${#h}" -le 64 ] && [[ "$h" != *:* ]] && [[ "$h" != *$'\n'* ]]; }
valid_secret(){ [[ "${1:-}" =~ ^[A-Za-z0-9._@-]{4,128}$ ]]; }

pick_user(){
  local names=() n i=0 sel
  mapfile -t names < <(db_all | cut -d'|' -f1)
  [ "${#names[@]}" -gt 0 ] || { warn "No hay usuarios creados con el panel."; return 1; }
  for n in "${names[@]}"; do i=$((i + 1)); item "$i" "$n"; done
  ask sel " Usuario (numero o nombre): "
  if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#names[@]}" ]; then PICKED="${names[$((sel - 1))]}"; else PICKED="$sel"; fi
  [ -n "$PICKED" ] && [ -n "$(db_row "$PICKED")" ] || { fail "Ese usuario no esta en el panel."; return 1; }
}

u_new(){                       # u_new hwid|ssh
  need_root; local mode="$1" name secret days exp label badname=()
  if [ "$mode" = hwid ]; then
    label="HWID"
    ask secret " HWID del dispositivo (tal cual lo manda la app): "
    valid_hwid "$secret" || { fail "HWID invalido (vacio, con ':' , salto de linea, o mayor a 64 caracteres)."; return 1; }
    name="$secret"      # la app conecta SOLO con el HWID: usuario = clave = HWID, sin nombre aparte
    badname=(--badname) # permite usuarios de sistema con mayusculas, numeros al inicio, etc. (igual al HWID real)
  else
    label="Clave"
    ask name " Nombre de usuario (3-16, minusculas): "
    valid_user "$name" || { fail "Nombre invalido (usa minusculas, numeros, _ o -)."; return 1; }
    ask secret " Clave: "
    valid_secret "$secret" || { fail "Clave invalida (4-128 caracteres: letras, numeros . _ @ -)."; return 1; }
  fi
  id "$name" >/dev/null 2>&1 && { fail "Ya existe un usuario del sistema con ese ${label,,}."; return 1; }
  ask days " Dias de duracion [30]: "; days="${days:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ] || { fail "Dias invalidos (1-3650)."; return 1; }
  exp="$(date -d "+$days days" +%F)"
  grep -qx /bin/false /etc/shells 2>/dev/null || echo /bin/false >> /etc/shells
  useradd "${badname[@]}" -M -s /bin/false -e "$exp" -c "$BRAND" -- "$name" \
    || { fail "No pude crear el usuario (revisa que el $label no tenga caracteres raros)."; return 1; }
  printf '%s:%s\n' "$name" "$secret" | chpasswd || { userdel -f "$name" 2>/dev/null; fail "No pude poner la clave."; return 1; }
  db_put "$name" "$secret" "$exp" "$mode"
  echo; hl
  if [ "$mode" = hwid ]; then
    printf ' %bHWID (usuario y clave):%b %s\n %bVence   :%b %s (%s dias)\n %bIP      :%b %s\n' \
      "$GY" "$WH" "$name" "$GY" "$WH" "$exp" "$days" "$GY" "$WH" "${PANEL_IP:-$(public_ip)}"
  else
    printf ' %bUsuario :%b %s\n %b%-8s:%b %s\n %bVence   :%b %s (%s dias)\n %bIP      :%b %s\n' \
      "$GY" "$WH" "$name" "$GY" "$label" "$WH" "$secret" "$GY" "$WH" "$exp" "$days" "$GY" "$WH" "${PANEL_IP:-$(public_ip)}"
  fi
  hl; ok "Usuario creado."
}
u_renew(){
  need_root; pick_user || return 1
  local days cur today base new
  ask days " Dias a sumar [30]: "; days="${days:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ] || { fail "Dias invalidos (1-3650)."; return 1; }
  cur="$(db_field "$PICKED" 3)"; today="$(date +%F)"; base="$cur"; [[ "$cur" < "$today" ]] && base="$today"
  new="$(date -d "$base +$days days" +%F)"
  usermod -e "$new" "$PICKED" 2>/dev/null || { fail "No pude renovar (el usuario no existe en el sistema)."; return 1; }
  db_put "$PICKED" "$(db_field "$PICKED" 2)" "$new" "$(db_field "$PICKED" 4)"
  ok "$PICKED renovado: vence el $new ($(days_left "$new") dias)."
}
u_remove_user(){
  local u="$1"; case "$u" in ""|root) return 1;; esac
  if id "$u" >/dev/null 2>&1; then
    [ "$(id -u "$u")" -ge 1000 ] || return 1
    pkill -KILL -u "$u" 2>/dev/null || true; userdel -f "$u" 2>/dev/null || true
  fi
  db_del "$u"
}
u_remove(){ need_root; pick_user || return 1; local a; ask a " Eliminar '$PICKED'? [s/N]: "
  case "$a" in s|S|y|Y) u_remove_user "$PICKED" && ok "Usuario eliminado." || fail "No se pudo eliminar.";; *) info "Sin cambios.";; esac; }
u_lock(){
  need_root; pick_user || return 1
  if user_locked "$PICKED"; then usermod -U "$PICKED" && ok "$PICKED DESBLOQUEADO."
  else usermod -L "$PICKED" && pkill -KILL -u "$PICKED" 2>/dev/null; ok "$PICKED BLOQUEADO (sesiones cerradas)."; fi
}
u_list(){
  local u s e t left st col n=0
  while IFS='|' read -r u s e t; do
    [ -n "$u" ] || continue; n=$((n + 1)); left="$(days_left "$e")"
    if [ "$left" -lt 0 ]; then st="VENCIDO"; col="$RD"; elif user_locked "$u"; then st="BLOQUEADO"; col="$YL"; else st="ACTIVO"; col="$GN"; fi
    printf ' %b%-14s%b %s %b%4sd%b  %b%s%b\n' "$WH" "$u" "$GY" "$e" "$WH" "$left" "$C_O" "$col" "$st" "$C_O"
    printf '   %b%s: %s%b\n' "$GY" "$([ "$t" = hwid ] && echo HWID || echo Clave)" "$s" "$C_O"
  done < <(db_all)
  [ "$n" -gt 0 ] || warn "No hay usuarios creados con el panel."
}
u_monitor(){
  local u c tot=0
  while IFS='|' read -r u _; do
    [ -n "$u" ] || continue; c="$(pgrep -c -u "$u" -f 'sshd|dropbear' 2>/dev/null || echo 0)"; c="${c:-0}"
    tot=$((tot + c))
    if [ "$c" -gt 0 ]; then printf ' %b%-16s%b %b%s conexion(es)%b\n' "$WH" "$u" "$C_O" "$GN" "$c" "$C_O"; fi
  done < <(db_all)
  [ "$tot" -gt 0 ] || info "Nadie conectado ahora."
  printf '\n %bTotal:%b %s\n' "$GY" "$WH" "$tot"
}
u_expired(){
  local u e n=0
  while IFS='|' read -r u _ e _; do
    [ -n "$u" ] || continue
    if [ "$(days_left "$e")" -lt 0 ]; then u_remove_user "$u" && n=$((n + 1)); fi
  done < <(db_all)
  [ "$n" -gt 0 ] && ok "Eliminados $n usuario(s) vencido(s)." || info "No hay usuarios vencidos."
}
u_all_remove(){
  need_root; confirm_word BORRAR "Se eliminaran TODOS los usuarios creados con el panel." || { info "Sin cambios."; return 0; }
  local u n=0; while IFS='|' read -r u _; do [ -n "$u" ] && u_remove_user "$u" && n=$((n + 1)); done < <(db_all)
  ok "Eliminados $n usuario(s)."
}
ensure_cron(){
  [ -d "$(dirname "$CRON_FILE")" ] || return 0
  [ -f "$CRON_FILE" ] || printf '17 0 * * * root %s expire >/dev/null 2>&1\n' "$PANEL_LINK" > "$CRON_FILE" 2>/dev/null || true
}

# =====================================================================
#  LIMPIADOR AUTOMATICO  (RAM/cache + logs y temporales viejos)
# =====================================================================
clean_hours(){ grep -m1 '^HOURS=' "$CLEAN_CONF" 2>/dev/null | cut -d= -f2; }
clean_enabled(){ [ -f "$CLEAN_CRON" ]; }
clean_write_cron(){
  local h="$1"; mkdir -p "$(dirname "$CLEAN_CONF")" "$(dirname "$CLEAN_CRON")" 2>/dev/null
  printf 'HOURS=%s\n' "$h" > "$CLEAN_CONF"
  printf '0 */%s * * * root %s cleanup >/dev/null 2>&1\n' "$h" "$PANEL_LINK" > "$CLEAN_CRON"
}
clean_disable(){ rm -f "$CLEAN_CRON"; }
do_cleanup(){
  need_root
  local before after freedkb
  before="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  sync 2>/dev/null
  [ -w /proc/sys/vm/drop_caches ] && echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
  after="$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  freedkb=$(( after - before )); [ "$freedkb" -lt 0 ] && freedkb=0
  ok "RAM: cache liberado (+${freedkb}KB disponibles aprox.)."
  if have journalctl; then
    journalctl --vacuum-time=3d >/dev/null 2>&1
    journalctl --vacuum-size=50M >/dev/null 2>&1
    ok "Logs del sistema (journal): recortados a 3 dias / 50MB."
  fi
  if have apt-get; then apt-get clean -y >/dev/null 2>&1 && ok "Cache de apt limpiada."; fi
  find /tmp -mindepth 1 -type f -mtime +1 -delete 2>/dev/null
  find /tmp -mindepth 1 -type d -empty -delete 2>/dev/null
  ok "Archivos temporales de mas de 1 dia en /tmp eliminados."
}
clean_menu(){
  need_root; local op st
  while true; do
    clear 2>/dev/null || true; calc_w
    title "LIMPIADOR AUTOMATICO"
    clean_enabled && st=on || st=off
    printf ' %bEstado:%b ' "$GY" "$C_O"; tag "$st"
    clean_enabled && printf '  %bCada %s hora(s)%b\n' "$GY" "$(clean_hours)" "$C_O" || echo
    printf ' %bLimpia:%b cache de RAM, logs viejos (journal), cache de apt y /tmp\n' "$GY" "$C_O"
    dash
    item 1 "ACTIVAR (cada 1 hora)"
    item 2 "ACTIVAR (cada 2 horas)"
    item 3 "DESACTIVAR" "$OR"
    item 4 "LIMPIAR AHORA"
    hl; printf ' %b[0]%b %b Volver %b\n' "$GY" "$C_O" "$BGR" "$C_O"; hl
    ask_op op
    case "$op" in
      1) clean_write_cron 1; ok "Activado: se limpia cada 1 hora."; pause;;
      2) clean_write_cron 2; ok "Activado: se limpia cada 2 horas."; pause;;
      3) clean_disable; info "Limpiador automatico desactivado."; pause;;
      4) echo; do_cleanup; pause;;
      0) return 0;; *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}

users_menu(){
  need_root; local op
  while true; do
    clear 2>/dev/null || true; calc_w
    title "ADMINISTRACION DE USUARIOS HWID"
    item 1 "NUEVO USUARIO HWID"
    item 2 "NUEVO USUARIO SSH (CLAVE)"
    item 3 "RENOVAR USUARIO"
    item 4 "REMOVER USUARIO" "$OR"
    item 5 "BLOQUEAR/DESBLOQUEAR USUARIO"
    dash
    item 6 "DETALLES DE TODOS USUARIOS" "$GY"
    item 7 "MONITOR DE USUARIOS CONECTADOS"
    dash
    item 8 "ELIMINAR USUARIOS VENCIDOS"
    item 9 "ELIMINAR TODOS LOS USUARIOS" "$OR"
    hl; printf ' %b[0]%b %b Volver %b\n' "$GY" "$C_O" "$BGR" "$C_O"; hl
    ask_op op
    case "$op" in
      1) u_new hwid; pause;; 2) u_new ssh; pause;; 3) u_renew; pause;; 4) u_remove; pause;; 5) u_lock; pause;;
      6) echo; u_list; pause;; 7) echo; u_monitor; pause;; 8) u_expired; pause;; 9) u_all_remove; pause;;
      0) return 0;; *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}

# =====================================================================
#  Acciones existentes (BHTTP, V2Ray, Hysteria, herramientas)
# =====================================================================
open_bhttp(){ write_subs; if bh_installed; then "$BH_MGR" menu; else "$BH_MGR" install; pause; fi; }
open_xray(){ write_subs; if xr_installed; then "$XR_MGR" menu; else "$XR_MGR" install; pause; fi; }
hysteria_info(){
  echo "===== Hysteria2 ====="
  if hy_active; then ok "Detectado en ejecucion (puerto UDP: $(hy_port))."; else warn "No lo detecto en ejecucion."; fi
  echo
  info "Hysteria2 se instala y administra con tu instalador UDP-Hysteria de siempre (opcion 2 = version 2)."
  info "En la app usa un enlace  hysteria2://CLAVE@IP:PUERTO/?obfs=salamander&obfs-password=...&sni=...&pinSHA256=..."
}
toggle_bbr(){
  write_subs
  if [ -f "$BH_TUNE" ]; then "$BH_MGR" tuning-off; else "$BH_MGR" tuning-on; fi
}
firewall_view(){
  echo "===== Firewall ====="
  if have ufw; then ufw status 2>/dev/null | head -40; else info "ufw no esta instalado."; fi
}
conns_view(){
  echo "===== Conexiones activas ahora ====="
  local p any=0
  show(){
    local label="$1" port="$2" n ips
    n="$(conn_count "$port")"
    ips="$(ss -tan 2>/dev/null | awk -v p=":$port" '$1=="ESTAB" && $4 ~ p"$" {r=$5; sub(/:[0-9]+$/,"",r); c[r]++} END{for (k in c) printf "%s (%d)\n", k, c[k]}' | sort -t'(' -k2 -nr | head -10)"
    printf '%s :%s  ->  %s conexiones TCP, %s IP(s) distintas\n' "$label" "$port" "$n" "$(printf '%s\n' "$ips" | grep -c .)"
    [ -n "$ips" ] && printf '%s\n' "$ips" | sed 's/^/     /'
    any=1
  }
  for p in $(bh_ports); do show "BHTTP" "$p"; done
  xr_installed && show "V2Ray" "$(xr_port)"
  [ "$any" -eq 1 ] || info "No hay servicios instalados."
  echo; info "Con BHTTP cada usuario abre muchas conexiones cortas: mira el numero de IPs, no el de conexiones."
}
restart_services(){
  write_subs; local did=0 p
  if bh_installed; then "$BH_MGR" restart; did=1; fi
  if xr_installed; then systemctl restart "${BRAND}-xray.service" && ok "V2Ray reiniciado."; did=1; fi
  if ug_installed; then for p in $(ug_ports); do systemctl restart "$(ug_unit "$p")"; done; ok "BADVPN-UDPGW reiniciado."; did=1; fi
  [ "$did" -eq 1 ] || info "No hay servicios instalados."
}
reboot_server(){ confirm_word REINICIAR "Se reiniciara TODO el servidor y se cortaran las conexiones." || { info "Sin cambios."; return 0; }; info "Reiniciando..."; sleep 1; reboot; }
logs_menu(){
  local o p; echo "1) BHTTP   2) V2Ray   3) BADVPN-UDPGW"; ask o "Cual: "
  case "$o" in
    1) write_subs; "$BH_MGR" logs;;
    2) journalctl -u "${BRAND}-xray.service" -n 80 --no-pager 2>/dev/null || info "Sin logs.";;
    3) p="$(ug_ports | awk '{print $1}')"; [ -n "$p" ] && { journalctl -u "$(ug_unit "$p")" -n 80 --no-pager 2>/dev/null || info "Sin logs."; } || info "BADVPN-UDPGW sin instalar.";;
  esac
}
uninstall_all(){
  need_root; write_subs
  warn "Esto desinstala BHTTP, V2Ray, BADVPN-UDPGW y este panel. No toca tu SSH, Hysteria2 ni las cuentas de usuario ya creadas."
  confirm_word TODO "Desinstalar todo." || { info "Sin cambios."; return 0; }
  bh_installed && BHTTP_YES=1 "$BH_MGR" uninstall
  [ -f "$BH_TUNE" ] && BHTTP_YES=1 "$BH_MGR" tuning-off
  xr_installed && XRAY_YES=1 "$XR_MGR" uninstall
  if ug_installed; then TIONEL_YES=1 ug_uninstall; fi
  rm -f "$CRON_FILE" "$BH_MGR" "$BH_LINK" "$XR_MGR" "$XR_LINK" "$PANEL_LINK" "$PANEL_DEST"
  ok "$BRAND desinstalado por completo."; exit 0
}

# =====================================================================
#  Menus
# =====================================================================
protocols_menu(){
  need_root; local op st ps
  while true; do
    clear 2>/dev/null || true; calc_w
    title "ADMINISTRADOR DE PROTOCOLOS"
    printf ' %bBADVPN:%b %-14s %bBHTTP:%b %s\n' "$OR" "$GY" "$(ug_ports || true)" "$OR" "$GY" "$(bh_ports || true)"
    printf ' %bV2RAY :%b %-14s %bHY2  :%b %s\n' "$OR" "$GY" "$(xr_installed && xr_port || true)" "$OR" "$GY" "$(hy_active && hy_port || true)"
    dash
    if bh_installed; then bh_active && st=on || st=off; ps="$(bh_ports)"; pitem 1 "BHTTP" "$st" "${ps:+:${ps// /,:}}$(bh_tls && printf ' TLS')"
    else pitem 1 "BHTTP" none "(sin instalar)"; fi
    if xr_installed; then xr_active && st=on || st=off; pitem 2 "V2RAY/XRAY REALITY" "$st" ":$(xr_port)"
    else pitem 2 "V2RAY/XRAY REALITY" none "(sin instalar)"; fi
    if ug_installed; then ug_active && st=on || st=off; pitem 3 "BADVPN-UDPGW" "$st" "$(ug_ports)"
    else pitem 3 "BADVPN-UDPGW" none "(sin instalar)"; fi
    if hy_active; then pitem 4 "HYSTERIA2" on "udp :$(hy_port)"; else pitem 4 "HYSTERIA2" none "(no detectado)"; fi
    hl; printf ' %b[0]%b %b Volver %b\n' "$GY" "$C_O" "$BGR" "$C_O"; hl
    ask_op op
    case "$op" in
      1) open_bhttp;; 2) open_xray;; 3) ug_menu;; 4) hysteria_info; pause;;
      0) return 0;; *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}
AUTOSTART_RC="/root/.bashrc"
AUTOSTART_TAG="el_tioNel-autostart"
autostart_enabled(){ [ -f "$AUTOSTART_RC" ] && grep -q "# >>> $AUTOSTART_TAG >>>" "$AUTOSTART_RC"; }
autostart_on(){
  autostart_enabled && return 0
  [ -f "$AUTOSTART_RC" ] || : > "$AUTOSTART_RC"
  {
    printf '\n# >>> %s >>>\n' "$AUTOSTART_TAG"
    printf 'if [ -n "$PS1" ] && [ -z "${TIONEL_NO_AUTOSTART:-}" ]; then %s; fi\n' "$PANEL_LINK"
    printf '# <<< %s <<<\n' "$AUTOSTART_TAG"
  } >> "$AUTOSTART_RC"
  ok "Autoinicio activado: la proxima vez que entres por SSH, el panel se abrira solo."
}
autostart_off(){
  autostart_enabled || return 0
  sed -i "/# >>> $AUTOSTART_TAG >>>/,/# <<< $AUTOSTART_TAG <<</d" "$AUTOSTART_RC"
  ok "Autoinicio desactivado."
}
tools_menu(){
  need_root; local op st
  while true; do
    clear 2>/dev/null || true; calc_w
    title "HERRAMIENTAS EXTRAS"
    bbr_on && st=on || st=off; pitem 1 "AJUSTE DE RED BBR" "$st"
    ufw_on && st=on || st=off; pitem 2 "FIREWALL (UFW)" "$st"
    item 3 "CONEXIONES ACTIVAS AHORA"
    item 4 "REINICIAR SERVICIOS"
    item 5 "VER LOGS"
    dash
    clean_enabled && st=on || st=off; pitem 6 "LIMPIADOR AUTOMATICO" "$st" "$(clean_enabled && printf 'cada %sh' "$(clean_hours)")"
    autostart_enabled && st=on || st=off; pitem 7 "AUTOINICIAR PANEL AL CONECTAR (SSH)" "$st"
    hl; printf ' %b[0]%b %b Volver %b\n' "$GY" "$C_O" "$BGR" "$C_O"; hl
    ask_op op
    case "$op" in
      1) toggle_bbr; pause;; 2) firewall_view; pause;; 3) conns_view; pause;;
      4) restart_services; pause;; 5) logs_menu; pause;; 6) clean_menu;;
      7) autostart_enabled && autostart_off || autostart_on; pause;;
      0) return 0;; *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}
draw(){
  calc_w; title "$BRAND  v$PANEL_VERSION"; sysinfo
  item 1 "ADMINISTRAR USUARIOS (HWID/SSH)"
  dash
  item 2 "CONFIGURACION DE PROTOCOLOS"
  item 3 "HERRAMIENTAS EXTRAS"
  item 4 "LIMPIAR AHORA (RAM/logs/temporales)"
  dash
  item 5 "[!] DESINSTALAR PANEL" "$OR"
  hl
  printf ' %b[0]%b %b SALIR DEL PANEL %b   %b[9]%b %b REINICIAR VPS %b\n' "$GY" "$C_O" "$BGR" "$C_O" "$GY" "$C_O" "$BGB" "$C_O"
  hl
}
menu(){
  need_root; local op; PANEL_IP="$(public_ip)"; ensure_cron
  while true; do
    clear 2>/dev/null || true
    draw; ask_op op
    case "$op" in
      1) users_menu;; 2) protocols_menu;; 3) tools_menu;;
      4) echo; do_cleanup; pause;; 5) uninstall_all; pause;;
      9) reboot_server; pause;; 0) exit 0;; *) echo " Opcion invalida"; sleep 1;;
    esac
  done
}
usage(){ cat <<EOF
$BRAND - panel de VPS v$PANEL_VERSION
  $BRAND                abre el panel
  $BRAND status         muestra el estado y sale
  $BRAND users          menu de usuarios HWID/SSH
  $BRAND udpgw          menu de BADVPN-UDPGW
  $BRAND expire         borra los usuarios vencidos (lo usa el cron diario)
  $BRAND cleanup        limpia RAM/cache y logs viejos (lo usa el cron del limpiador)
  $BRAND bhttp ...      atajo a $BRAND-bhttp (ej: $BRAND bhttp add-port 8081)
  $BRAND xray ...       atajo a $BRAND-xray  (ej: $BRAND xray links)
EOF
}

main(){
  verify_signature
  local a="${1:-}"; [ $# -gt 0 ] && shift
  case "$a" in
    "") need_root; install_panel || exit 1; write_subs; menu;;
    install) need_root; install_panel || exit 1; write_subs; ensure_cron; ok "Panel instalado: escribe  $BRAND";;
    status) PANEL_IP="$(public_ip)"; draw;;
    users) need_root; PANEL_IP="$(public_ip)"; users_menu;;
    udpgw) need_root; ug_menu;;
    expire) need_root; u_expired;;
    cleanup) need_root; do_cleanup;;
    bhttp) need_root; write_subs; "$BH_MGR" "$@";;
    xray) need_root; write_subs; "$XR_MGR" "$@";;
    uninstall) uninstall_all;;
    help|-h|--help) usage;;
    *) usage; exit 2;;
  esac
}
main "$@"
