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
