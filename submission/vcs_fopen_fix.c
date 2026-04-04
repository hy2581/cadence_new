#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <setjmp.h>
#include <fcntl.h>

static FILE *(*real_fopen)(const char *, const char *) = NULL;
static FILE *(*real_fopen64)(const char *, const char *) = NULL;
static int (*real_fclose)(FILE *) = NULL;

static __thread sigjmp_buf fclose_jmp;
static __thread volatile int in_fclose_guard = 0;

static void fclose_segv_handler(int sig) {
    if (in_fclose_guard) {
        siglongjmp(fclose_jmp, 1);
    }
}

__attribute__((constructor))
static void init_fix(void) {
    real_fopen = dlsym(RTLD_NEXT, "fopen");
    real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    real_fclose = dlsym(RTLD_NEXT, "fclose");
}

int fclose(FILE *fp) {
    if (!real_fclose)
        real_fclose = dlsym(RTLD_NEXT, "fclose");

    if (!fp)
        return 0;

    struct sigaction sa, old_sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = fclose_segv_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGSEGV, &sa, &old_sa);

    in_fclose_guard = 1;
    int ret = 0;
    if (sigsetjmp(fclose_jmp, 1) == 0) {
        ret = real_fclose(fp);
    } else {
        ret = 0;
    }
    in_fclose_guard = 0;

    sigaction(SIGSEGV, &old_sa, NULL);
    return ret;
}

FILE *fopen(const char *path, const char *mode) {
    if (!real_fopen)
        real_fopen = dlsym(RTLD_NEXT, "fopen");
    if (path && strcmp(path, "/proc/self/stat") == 0) {
        int pid = getpid();
        char buf[512];
        char tmppath[128];
        snprintf(tmppath, sizeof(tmppath), "/tmp/.vcs_stat_%d", pid);
        int fd = open(tmppath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            int len = snprintf(buf, sizeof(buf),
                "%d (vcs1) S 1 %d %d 0 -1 4194304 0 0 0 0 0 0 0 0 20 0 1 0 0 0 0 -1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n",
                pid, pid, pid);
            write(fd, buf, len);
            close(fd);
            return real_fopen(tmppath, mode);
        }
    }
    return real_fopen(path, mode);
}

FILE *fopen64(const char *path, const char *mode) {
    if (!real_fopen64)
        real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    if (path && strcmp(path, "/proc/self/stat") == 0) {
        return fopen(path, mode);
    }
    return real_fopen64(path, mode);
}
