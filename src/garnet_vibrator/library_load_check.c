extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern const char *dlerror(void);
extern long write(int, const void *, unsigned long);
extern void _exit(int);

struct shared_ptr {
    void *object;
    void *control;
};

extern void call_connect(void *, struct shared_ptr *, struct shared_ptr *);
__asm__(
    ".text\n"
    ".global call_connect\n"
    "call_connect:\n"
    "mov x8, x2\n"
    "mov x2, x0\n"
    "mov x0, x1\n"
    "br x2\n"
);

void _start(void) {
    void *handle = dlopen("/data/local/tmp/garnet-vibrator-test.so", 2);
    if (!handle) {
        const char *error = dlerror();
        unsigned long length = 0;
        while (error[length]) length++;
        write(2, error, length);
        _exit(1);
    }
    void *connect = dlsym(handle,
        "_ZN7android8vibrator10connectHalENSt3__110shared_ptrINS0_17CallbackSchedulerEEE");
    if (!connect) {
        write(2, "connectHal not found\n", 21);
        _exit(1);
    }
    struct shared_ptr scheduler = {0, 0};
    struct shared_ptr result = {0, 0};
    call_connect(connect, &scheduler, &result);
    if (!result.object) {
        write(2, "No vibrator HAL connected\n", 26);
        _exit(2);
    }
    write(1, "Vibrator HAL connected\n", 23);
    _exit(0);
}
