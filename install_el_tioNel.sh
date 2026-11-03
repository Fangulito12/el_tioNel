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

MANAGER_VERSION="1.1"
ROOT="${BHTTP_ROOT:-}"                       # solo para pruebas; en uso normal queda vacio
APP_DIR="$ROOT/opt/$NAME"
SERVER="$APP_DIR/${NAME}-server.py"
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
CFG_KEYS="BACKEND POLL_WAIT_MS MAX_SESSIONS MAX_PER_IP IDLE TLS_ARGS"

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
cfg_default(){
  case "$1" in
    BACKEND) echo "127.0.0.1:22";; POLL_WAIT_MS) echo 800;; MAX_SESSIONS) echo 1024;;
    MAX_PER_IP) echo 64;; IDLE) echo 120;;
  esac
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


# ---------------------------------------------------------------- ofuscacion

def crypt(data: bytes, sid: bytes, mode: int, seq: int, is_response: bool) -> bytes:
    """XOR con un flujo derivado de SHA-256. Es simetrico: sirve para cifrar y descifrar."""
    if not data:
        return b""
    base = sid + bytes([mode]) + seq.to_bytes(8, "big") + (b"\x01" if is_response else b"\x00")
    n = len(data)
    ks = b"".join(hashlib.sha256(base + i.to_bytes(4, "big")).digest() for i in range((n + 31) // 32))
    return (int.from_bytes(data, "big") ^ int.from_bytes(ks[:n], "big")).to_bytes(n, "big")


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
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
BHTTP_SERVER_PY_EOF
  chmod 755 "$APP_DIR"; chmod 644 "$SERVER"
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$SERVER" || { fail "El archivo del servidor quedo danado."; return 1; }
}

write_unit(){
  local py; py="$(command -v python3)"
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<'UNIT_EOF'
[Unit]
Description=__BRAND__ BHTTP (puerto %i)
After=network-online.target ssh.service sshd.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=__CONFIG__
ExecStart=__LAUNCHER__ __SERVER__ --listen 0.0.0.0 --port %i --backend ${BACKEND} --poll-wait-ms ${POLL_WAIT_MS} --max-sessions ${MAX_SESSIONS} --max-per-ip ${MAX_PER_IP} --idle ${IDLE} $TLS_ARGS
Restart=always
RestartSec=1
LimitNOFILE=65535
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
  mkdir -p "$(dirname "$LAUNCHER")"
  ln -sfn "$py" "$LAUNCHER"
  sed -i -e "s|__BRAND__|$BRAND|" -e "s|__CONFIG__|${CONFIG#"$ROOT"}|" \
         -e "s|__LAUNCHER__|${LAUNCHER#"$ROOT"}|" -e "s|__SERVER__|${SERVER#"$ROOT"}|" "$UNIT_FILE"
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
  cfg_init; write_server || return 1; write_unit; install_self
  for p in $(ports_list); do systemctl enable --now "$(unit_name "$p")" >/dev/null 2>&1; systemctl restart "$(unit_name "$p")"; done
  ok "Servidor BHTTP v2 instalado/actualizado."
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
net.core.rmem_max|16777216
net.core.wmem_max|16777216
net.ipv4.tcp_rmem|4096 131072 16777216
net.ipv4.tcp_wmem|4096 131072 16777216
net.core.somaxconn|4096
net.ipv4.tcp_slow_start_after_idle|0
net.ipv4.tcp_mtu_probing|1
TUNE_EOF
}
tuning_on(){
  need_root
  have sysctl || { fail "No encontre sysctl."; return 1; }
  local line k v cur first=0 avail
  [ -s "$SYSCTL_PREV" ] || first=1
  mkdir -p "$CONF_DIR" "$(dirname "$SYSCTL_FILE")"
  [ "$first" -eq 1 ] && : > "$SYSCTL_PREV"
  printf '# %s BHTTP - ajustes de red opcionales (se quitan desde el menu: %s)\n' "$BRAND" "$CMD" > "$SYSCTL_FILE"
  have modprobe && modprobe tcp_bbr >/dev/null 2>&1 || true
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  while IFS='|' read -r k v; do
    [ -n "$k" ] || continue
    cur="$(sysctl -n "$k" 2>/dev/null)" || continue          # la clave no existe en este kernel
    if [ "$k" = "net.ipv4.tcp_congestion_control" ] && ! printf '%s' "$avail" | grep -qw bbr; then
      warn "Este kernel no ofrece BBR: se omite."; continue
    fi
    [ "$first" -eq 1 ] && printf '%s|%s\n' "$k" "$cur" >> "$SYSCTL_PREV"
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
  restart_all
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
  restart_all
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
