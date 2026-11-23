/*
 * Minimal static AArch64 Optical FOD / Local HBM bridge daemon for Xiaomi garnet.
 * Watches:
 *   1. /dev/mi_display/disp_feature (MI_DISP_EVENT_FOD -> UI_READY 1/0)
 *   2. focaltech_ts evdev touch input (auto-triggers LHBM 1000nit + TOUCH 1/0 in FOD zone when active)
 *   3. /dev/garnet_fod.sock (commands from GarnetFodHelper: ACTIVE 1/0, HBM 1/0)
 */
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef int int32_t;
typedef long int64_t;
typedef unsigned long uint64_t;
typedef unsigned long size_t;
typedef long ssize_t;

#define SYS_ioctl         29
#define SYS_unlinkat      35
#define SYS_fchmodat      53
#define SYS_openat        56
#define SYS_close         57
#define SYS_getdents64    61
#define SYS_read          63
#define SYS_write         64
#define SYS_ppoll         73
#define SYS_exit_group    94
#define SYS_clock_gettime 113
#define SYS_socket        198
#define SYS_bind          200
#define SYS_listen        201
#define SYS_accept4       242

#define AT_FDCWD          (-100)
#define O_RDONLY          0
#define O_WRONLY          1
#define O_RDWR            2
#define O_NONBLOCK        04000
#define O_DIRECTORY       0200000

#define AF_UNIX           1
#define SOCK_STREAM       1
#define SOCK_NONBLOCK     04000

#define POLLIN            0x0001
#define POLLERR           0x0008
#define POLLHUP           0x0010

#define CLOCK_MONOTONIC   1

/* Xiaomi mi_disp UAPI ioctls (verified from garnet msm_drm.ko) */
#define DISP_FEATURE_PATH            "/dev/mi_display/disp_feature"
#define MI_DISP_PRIMARY              0
#define MI_DISP_EVENT_FOD            2
#define MI_DISP_IOCTL_REGISTER_EVENT 0x400c4407UL
#define MI_DISP_IOCTL_SET_LOCAL_HBM  0x400c440eUL
#define LHBM_OFF_FINGER_UP           0
#define LHBM_WHITE_1000NIT           2
#define LOCAL_HBM_UI_READY_MASK      0x08

/* Linux evdev constants */
#define EV_SYN              0x00
#define EV_KEY              0x01
#define EV_ABS              0x03
#define ABS_MT_SLOT         0x2f
#define ABS_MT_POSITION_X   0x35
#define ABS_MT_POSITION_Y   0x36
#define ABS_MT_TRACKING_ID  0x39
#define BTN_TOUCH           0x14a
#define BTN_INFO            0x152
#define EVIOCGNAME_64       0x80404506UL
#define EVIOCGABS_X         0x80184575UL
#define EVIOCGABS_Y         0x80184576UL

/* Garnet physical FOD sensor zone in 1220x2712 pixels (center 610, 2437, widened bounds) */
#define PANEL_W             1220
#define PANEL_H             2712
#define FOD_X_MIN           380
#define FOD_X_MAX           840
#define FOD_Y_MIN           2200
#define FOD_Y_MAX           2680
#define MAX_SLOTS           10
#define HBM_WATCHDOG_MS     4000

struct disp_base {
    uint32_t flag;
    uint32_t disp_id;
};
struct disp_local_hbm_req {
    struct disp_base base;
    uint32_t local_hbm_value;
};
struct disp_event_req {
    struct disp_base base;
    uint32_t type;
};
struct disp_event {
    int32_t disp_id;
    uint32_t type;
    uint32_t length;
};
struct input_event {
    int64_t sec;
    int64_t usec;
    uint16_t type;
    uint16_t code;
    int32_t value;
};
struct input_absinfo {
    int32_t value;
    int32_t minimum;
    int32_t maximum;
    int32_t fuzz;
    int32_t flat;
    int32_t resolution;
};
struct pollfd {
    int32_t fd;
    int16_t events;
    int16_t revents;
};
struct timespec {
    int64_t tv_sec;
    int64_t tv_nsec;
};
struct sockaddr_un {
    uint16_t sun_family;
    char sun_path[108];
};

static inline long sc6(long nr, long a0, long a1, long a2, long a3, long a4, long a5) {
    register long x8 __asm__("x8") = nr;
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;
    __asm__ volatile("svc #0"
                     : "+r"(x0)
                     : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5)
                     : "memory");
    return x0;
}
#define sc1(n,a)       sc6(n,(long)(a),0,0,0,0,0)
#define sc2(n,a,b)     sc6(n,(long)(a),(long)(b),0,0,0,0)
#define sc3(n,a,b,c)   sc6(n,(long)(a),(long)(b),(long)(c),0,0,0)
#define sc4(n,a,b,c,d) sc6(n,(long)(a),(long)(b),(long)(c),(long)(d),0,0)

static size_t c_strlen(const char *s) {
    size_t n = 0;
    while (((volatile const char *)s)[n]) n++;
    return n;
}
static int c_contains(const char *hay, const char *ndl) {
    size_t nl = c_strlen(ndl);
    if (!nl) return 1;
    for (size_t i = 0; hay[i]; i++) {
        size_t j = 0;
        while (j < nl && hay[i + j] == ndl[j]) j++;
        if (j == nl) return 1;
    }
    return 0;
}
static int c_starts(const char *s, const char *p) {
    while (*p) {
        if (*s++ != *p++) return 0;
    }
    return 1;
}
static void c_memset(void *dst, int v, size_t n) {
    volatile uint8_t *p = (volatile uint8_t *)dst;
    for (size_t i = 0; i < n; i++) p[i] = (uint8_t)v;
}
static void c_strcpy(char *dst, const char *src) {
    size_t i = 0;
    while (src[i]) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}
static void c_fmt_int(char *dst, int *pos, long v) {
    char tmp[24];
    int n = 0;
    unsigned long uv = v < 0 ? (unsigned long)(-v) : (unsigned long)v;
    if (v < 0) dst[(*pos)++] = '-';
    if (uv == 0) tmp[n++] = '0';
    while (uv) { tmp[n++] = (char)('0' + (uv % 10)); uv /= 10; }
    while (n > 0) dst[(*pos)++] = tmp[--n];
}

static int g_kmsg_fd = -1;
static void klog(const char *msg, long arg) {
    char buf[160];
    int p = 0;
    const char *pre = "<6>garnet_lhbm: ";
    while (*pre) buf[p++] = *pre++;
    while (*msg && p < 120) buf[p++] = *msg++;
    if (arg != 999999999L) {
        buf[p++] = ' ';
        c_fmt_int(buf, &p, arg);
    }
    buf[p++] = '\n';
    if (g_kmsg_fd >= 0) sc3(SYS_write, g_kmsg_fd, buf, p);
    sc3(SYS_write, 2, buf + 3, p - 3);
}

static int64_t now_ms(void) {
    struct timespec ts;
    sc2(SYS_clock_gettime, CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static int g_disp_fd = -1;
static int g_client_fd = -1;
static int g_touch_fd = -1;
static int g_hbm_on = 0;
static int64_t g_hbm_on_ms = 0;
static int g_fod_active = 0;
static int g_touch_pressed = 0;
static int32_t g_max_x = 19520;
static int32_t g_max_y = 43392;

static void send_client(const char *s) {
    if (g_client_fd < 0) return;
    long rc = sc3(SYS_write, g_client_fd, s, c_strlen(s));
    if (rc < 0) {
        sc1(SYS_close, g_client_fd);
        g_client_fd = -1;
    }
}

static void set_lhbm(int on) {
    if (g_disp_fd < 0) return;
    if (on && g_hbm_on) return;
    if (!on && !g_hbm_on) return;
    struct disp_local_hbm_req req;
    req.base.flag = 0;
    req.base.disp_id = MI_DISP_PRIMARY;
    req.local_hbm_value = on ? LHBM_WHITE_1000NIT : LHBM_OFF_FINGER_UP;
    long rc = sc3(SYS_ioctl, g_disp_fd, MI_DISP_IOCTL_SET_LOCAL_HBM, &req);
    g_hbm_on = on ? 1 : 0;
    g_hbm_on_ms = on ? now_ms() : 0;
    klog(on ? "set_lhbm ON rc=" : "set_lhbm OFF rc=", rc);
}

static int find_touch_dev(void) {
    char path[32];
    char name[64];
    for (int i = 0; i < 16; i++) {
        int p = 0;
        const char *pre = "/dev/input/event";
        while (*pre) path[p++] = *pre++;
        c_fmt_int(path, &p, i);
        path[p] = 0;
        long fd = sc4(SYS_openat, AT_FDCWD, path, O_RDONLY | O_NONBLOCK, 0);
        if (fd < 0) continue;
        c_memset(name, 0, sizeof(name));
        long rc = sc3(SYS_ioctl, fd, EVIOCGNAME_64, name);
        if (rc >= 0 && (c_contains(name, "focaltech_ts") || c_contains(name, "fts"))) {
            struct input_absinfo ai;
            c_memset(&ai, 0, sizeof(ai));
            if (sc3(SYS_ioctl, fd, EVIOCGABS_X, &ai) >= 0 && ai.maximum > 0) g_max_x = ai.maximum;
            c_memset(&ai, 0, sizeof(ai));
            if (sc3(SYS_ioctl, fd, EVIOCGABS_Y, &ai) >= 0 && ai.maximum > 0) g_max_y = ai.maximum;
            klog("touch_dev opened event index=", i);
            klog("touch max_x=", g_max_x);
            klog("touch max_y=", g_max_y);
            return (int)fd;
        }
        sc1(SYS_close, fd);
    }
    klog("focaltech_ts not found!", -1);
    return -1;
}

static void handle_client_line(const char *line) {
    if (c_starts(line, "HBM 1")) {
        set_lhbm(1);
    } else if (c_starts(line, "HBM 0")) {
        set_lhbm(0);
    } else if (c_starts(line, "ACTIVE 1")) {
        g_fod_active = 1;
        klog("fod_active=", 1);
    } else if (c_starts(line, "ACTIVE 0")) {
        g_fod_active = 0;
        g_touch_pressed = 0;
        set_lhbm(0);
        klog("fod_active=", 0);
    }
}

void _start(void) {
    g_kmsg_fd = (int)sc4(SYS_openat, AT_FDCWD, "/dev/kmsg", O_WRONLY, 0);
    klog("starting garnet_lhbm_helper", 999999999L);

    g_disp_fd = (int)sc4(SYS_openat, AT_FDCWD, DISP_FEATURE_PATH, O_RDWR, 0);
    if (g_disp_fd < 0) {
        klog("open disp_feature failed rc=", g_disp_fd);
        sc1(SYS_exit_group, 1);
    }

    struct disp_event_req ereq;
    ereq.base.flag = 0;
    ereq.base.disp_id = MI_DISP_PRIMARY;
    ereq.type = MI_DISP_EVENT_FOD;
    long rc = sc3(SYS_ioctl, g_disp_fd, MI_DISP_IOCTL_REGISTER_EVENT, &ereq);
    klog("register MI_DISP_EVENT_FOD rc=", rc);

    g_touch_fd = find_touch_dev();

    const char *sock_path = "/dev/garnet_fod.sock";
    sc3(SYS_unlinkat, AT_FDCWD, sock_path, 0);
    int listen_fd = (int)sc3(SYS_socket, AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (listen_fd < 0) {
        klog("socket failed rc=", listen_fd);
        sc1(SYS_exit_group, 2);
    }
    struct sockaddr_un addr;
    c_memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    c_strcpy(addr.sun_path, sock_path);
    rc = sc3(SYS_bind, listen_fd, &addr, 2 + c_strlen(sock_path) + 1);
    if (rc < 0) {
        klog("bind failed rc=", rc);
        sc1(SYS_exit_group, 3);
    }
    sc4(SYS_fchmodat, AT_FDCWD, sock_path, 0666, 0);
    rc = sc2(SYS_listen, listen_fd, 4);
    klog("listening on /dev/garnet_fod.sock rc=", rc);

    /* Touch tracking state */
    int cur_slot = 0;
    int slot_down[MAX_SLOTS];
    int32_t slot_x[MAX_SLOTS];
    int32_t slot_y[MAX_SLOTS];
    for (int i = 0; i < MAX_SLOTS; i++) { slot_down[i] = 0; slot_x[i] = 0; slot_y[i] = 0; }
    int key_fod_down = 0;

    char cmd_buf[256];
    int cmd_len = 0;

    for (;;) {
        struct pollfd pfds[4];
        int nfds = 0;
        int idx_listen = -1, idx_disp = -1, idx_touch = -1, idx_client = -1;

        idx_listen = nfds;
        pfds[nfds++] = (struct pollfd){listen_fd, POLLIN, 0};

        idx_disp = nfds;
        pfds[nfds++] = (struct pollfd){g_disp_fd, POLLIN, 0};

        if (g_touch_fd >= 0) {
            idx_touch = nfds;
            pfds[nfds++] = (struct pollfd){g_touch_fd, POLLIN, 0};
        }
        if (g_client_fd >= 0) {
            idx_client = nfds;
            pfds[nfds++] = (struct pollfd){g_client_fd, POLLIN, 0};
        }

        struct timespec ts = {0, 250000000L}; /* 250ms watchdog tick when HBM on */
        long prc = sc4(SYS_ppoll, pfds, nfds, g_hbm_on ? &ts : 0, 0);
        if (prc < 0) {
            if (prc == -4) continue; /* EINTR */
            break;
        }

        if (g_hbm_on && g_hbm_on_ms > 0 && (now_ms() - g_hbm_on_ms) > HBM_WATCHDOG_MS) {
            klog("LHBM watchdog timeout ms=", HBM_WATCHDOG_MS);
            g_touch_pressed = 0;
            set_lhbm(0);
            send_client("TOUCH 0\n");
        }

        if (idx_listen >= 0 && (pfds[idx_listen].revents & POLLIN)) {
            int nfd = (int)sc4(SYS_accept4, listen_fd, 0, 0, SOCK_NONBLOCK);
            if (nfd >= 0) {
                if (g_client_fd >= 0) sc1(SYS_close, g_client_fd);
                g_client_fd = nfd;
                cmd_len = 0;
                klog("client connected fd=", g_client_fd);
            }
        }

        if (idx_disp >= 0 && (pfds[idx_disp].revents & POLLIN)) {
            uint8_t evbuf[64];
            ssize_t r = sc3(SYS_read, g_disp_fd, evbuf, sizeof(evbuf));
            if (r >= 16) {
                struct disp_event *ev = (struct disp_event *)evbuf;
                if (ev->type == MI_DISP_EVENT_FOD) {
                    int32_t val = *(int32_t *)(evbuf + 12);
                    int ready = (val & LOCAL_HBM_UI_READY_MASK) ? 1 : 0;
                    klog("disp_fod val=", val);
                    send_client(ready ? "UI_READY 1\n" : "UI_READY 0\n");
                }
            }
        }

        if (idx_touch >= 0 && (pfds[idx_touch].revents & POLLIN)) {
            struct input_event evs[32];
            for (;;) {
                ssize_t r = sc3(SYS_read, g_touch_fd, evs, sizeof(evs));
                if (r <= 0) break;
                int count = (int)(r / (ssize_t)sizeof(struct input_event));
                for (int i = 0; i < count; i++) {
                    struct input_event *e = &evs[i];
                    if (e->type == EV_ABS) {
                        if (e->code == ABS_MT_SLOT) {
                            cur_slot = e->value;
                            if (cur_slot < 0) cur_slot = 0;
                            if (cur_slot >= MAX_SLOTS) cur_slot = MAX_SLOTS - 1;
                        } else if (e->code == ABS_MT_TRACKING_ID) {
                            slot_down[cur_slot] = (e->value >= 0) ? 1 : 0;
                        } else if (e->code == ABS_MT_POSITION_X) {
                            slot_x[cur_slot] = e->value;
                        } else if (e->code == ABS_MT_POSITION_Y) {
                            slot_y[cur_slot] = e->value;
                        }
                    } else if (e->type == EV_KEY) {
                        if (e->code == BTN_INFO) {
                            key_fod_down = (e->value != 0);
                        } else if (e->code == BTN_TOUCH && e->value == 0) {
                            for (int s = 0; s < MAX_SLOTS; s++) slot_down[s] = 0;
                        }
                    } else if (e->type == EV_SYN && g_fod_active) {
                        int in_fod = key_fod_down;
                        if (!in_fod) {
                            for (int s = 0; s < MAX_SLOTS; s++) {
                                if (!slot_down[s]) continue;
                                int32_t px = (int32_t)(((int64_t)slot_x[s] * PANEL_W) / g_max_x);
                                int32_t py = (int32_t)(((int64_t)slot_y[s] * PANEL_H) / g_max_y);
                                if (px >= FOD_X_MIN && px <= FOD_X_MAX &&
                                    py >= FOD_Y_MIN && py <= FOD_Y_MAX) {
                                    in_fod = 1;
                                    break;
                                }
                            }
                        }
                        if (in_fod && !g_touch_pressed) {
                            g_touch_pressed = 1;
                            set_lhbm(1);
                            send_client("TOUCH 1\n");
                        } else if (!in_fod && g_touch_pressed) {
                            g_touch_pressed = 0;
                            set_lhbm(0);
                            send_client("TOUCH 0\n");
                        }
                    }
                }
            }
        }

        if (idx_client >= 0 && (pfds[idx_client].revents & (POLLIN | POLLERR | POLLHUP))) {
            char rbuf[128];
            ssize_t r = sc3(SYS_read, g_client_fd, rbuf, sizeof(rbuf));
            if (r <= 0) {
                sc1(SYS_close, g_client_fd);
                g_client_fd = -1;
                klog("client disconnected", 999999999L);
            } else {
                for (ssize_t i = 0; i < r; i++) {
                    if (rbuf[i] == '\n' || rbuf[i] == '\r') {
                        if (cmd_len > 0) {
                            cmd_buf[cmd_len] = 0;
                            handle_client_line(cmd_buf);
                            cmd_len = 0;
                        }
                    } else if (cmd_len < (int)sizeof(cmd_buf) - 1) {
                        cmd_buf[cmd_len++] = rbuf[i];
                    }
                }
            }
        }
    }

    sc1(SYS_exit_group, 0);
}
