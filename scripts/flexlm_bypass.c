/*
 * flexlm_bypass.c
 * Comprehensive FlexLM Container Detection Bypass
 * Compatible with gcc 4.4+ (C89/C90 style)
 *
 * Compile:
 *   gcc -shared -fPIC -o flexlm_bypass.so flexlm_bypass.c -ldl
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>

static int is_listing_root = 0;

static DIR* (*real_opendir)(const char*) = NULL;
static int (*real_closedir)(DIR*) = NULL;
static struct dirent* (*real_readdir)(DIR*) = NULL;
static int (*real_open)(const char*, int, ...) = NULL;
static int (*real_openat)(int, const char*, int, ...) = NULL;
static FILE* (*real_fopen)(const char*, const char*) = NULL;
static int (*real_access)(const char*, int) = NULL;
static int (*real___xstat)(int, const char*, struct stat*) = NULL;
static int (*real___lxstat)(int, const char*, struct stat*) = NULL;
static int (*real___fxstat)(int, int, struct stat*) = NULL;

/* Track root dir fd */
static int root_dir_fd = -1;

static const char FAKE_CGROUP[] =
    "12:blkio:/\n"
    "11:devices:/\n"
    "10:hugetlb:/\n"
    "9:net_cls,net_prio:/\n"
    "8:freezer:/\n"
    "7:cpuset:/\n"
    "6:memory:/\n"
    "5:perf_event:/\n"
    "4:pids:/\n"
    "3:cpu,cpuacct:/\n"
    "2:rdma:/\n"
    "1:name=systemd:/init.scope\n"
    "0::/init.scope\n";

static const char FAKE_MOUNTINFO[] =
    "1 0 8:1 / / rw,relatime - ext4 /dev/sda1 rw\n"
    "22 1 0:21 / /proc rw,nosuid,nodev,noexec - proc proc rw\n"
    "23 1 0:22 / /sys rw,nosuid,nodev,noexec - sysfs sysfs rw\n"
    "24 1 0:5 / /dev rw,nosuid - devtmpfs udev rw\n";

static void init_funcs(void) {
    if (!real_opendir) {
        real_opendir = dlsym(RTLD_NEXT, "opendir");
        real_closedir = dlsym(RTLD_NEXT, "closedir");
        real_readdir = dlsym(RTLD_NEXT, "readdir");
        real_open = dlsym(RTLD_NEXT, "open");
        real_openat = dlsym(RTLD_NEXT, "openat");
        real_fopen = dlsym(RTLD_NEXT, "fopen");
        real_access = dlsym(RTLD_NEXT, "access");
        real___xstat = dlsym(RTLD_NEXT, "__xstat");
        real___lxstat = dlsym(RTLD_NEXT, "__lxstat");
        real___fxstat = dlsym(RTLD_NEXT, "__fxstat");
    }
}

/*
 * Returns: 1=cgroup, 2=mountinfo, 3=dockerenv, 4=cpuset, 0=normal
 */
static int detect_type(const char *path) {
    if (!path) return 0;
    if (strstr(path, "/proc/") != NULL && strstr(path, "/cgroup") != NULL) return 1;
    if (strstr(path, "/proc/") != NULL && strstr(path, "/mountinfo") != NULL) return 2;
    if (strcmp(path, "/.dockerenv") == 0) return 3;
    if (strstr(path, "/proc/") != NULL && strstr(path, "/cpuset") != NULL) return 4;
    return 0;
}

static int make_fake_fd(int type) {
    char tmppath[64];
    int fd;
    const char *content;

    strcpy(tmppath, "/tmp/flxbyp_XXXXXX");
    fd = mkstemp(tmppath);
    if (fd < 0) return -1;
    unlink(tmppath);

    if (type == 1 || type == 4)
        content = FAKE_CGROUP;
    else
        content = FAKE_MOUNTINFO;

    write(fd, content, strlen(content));
    lseek(fd, 0, SEEK_SET);
    return fd;
}

/* === opendir / readdir / closedir hooks (root inode faking) === */

DIR* opendir(const char *name) {
    init_funcs();
    if (name && strcmp(name, "/") == 0)
        is_listing_root = 1;
    return real_opendir(name);
}

int closedir(DIR *dirp) {
    init_funcs();
    is_listing_root = 0;
    return real_closedir(dirp);
}

/* === openat hook — track when root dir is opened === */
int openat(int dirfd, const char *pathname, int flags, ...) {
    int fd;
    init_funcs();

    if (detect_type(pathname) == 3) {
        errno = ENOENT;
        return -1;
    }

    if (flags & O_CREAT) {
        va_list ap;
        mode_t mode;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
        fd = real_openat(dirfd, pathname, flags, mode);
    } else {
        fd = real_openat(dirfd, pathname, flags);
    }

    if (fd >= 0 && pathname && strcmp(pathname, "/") == 0)
        root_dir_fd = fd;

    return fd;
}

/* === fstat hook — fake root inode === */
int __fxstat(int ver, int fd, struct stat *buf) {
    int ret;
    init_funcs();
    if (real___fxstat) {
        ret = real___fxstat(ver, fd, buf);
        if (ret == 0 && fd == root_dir_fd && root_dir_fd >= 0) {
            buf->st_ino = 2;
        }
        return ret;
    }
    errno = ENOSYS;
    return -1;
}

/* === getdents hook — hide .dockerenv from raw directory listing === */
struct linux_dirent {
    unsigned long  d_ino;
    unsigned long  d_off;
    unsigned short d_reclen;
    char           d_name[];
};

static long (*real_getdents)(unsigned int, struct linux_dirent*, unsigned int) = NULL;

long getdents(unsigned int fd, struct linux_dirent *dirp, unsigned int count) {
    long nread;
    long bpos;
    struct linux_dirent *d;
    char *buf;

    if (!real_getdents)
        real_getdents = dlsym(RTLD_NEXT, "getdents");

    nread = real_getdents(fd, dirp, count);
    if (nread <= 0) return nread;

    if ((int)fd != root_dir_fd || root_dir_fd < 0) return nread;

    /* Modify entries in the buffer */
    buf = (char*)dirp;
    for (bpos = 0; bpos < nread; ) {
        d = (struct linux_dirent*)(buf + bpos);

        /* Fake root inode for . and .. */
        if (strcmp(d->d_name, ".") == 0 || strcmp(d->d_name, "..") == 0) {
            d->d_ino = 2;
        }

        /* Remove .dockerenv by shifting remaining entries */
        if (strcmp(d->d_name, ".dockerenv") == 0) {
            int reclen = d->d_reclen;
            memmove(buf + bpos, buf + bpos + reclen, nread - bpos - reclen);
            nread -= reclen;
            continue;
        }

        bpos += d->d_reclen;
    }

    return nread;
}

struct dirent* readdir(DIR *dirp) {
    struct dirent *entry;
    init_funcs();
    entry = real_readdir(dirp);
    if (entry && is_listing_root) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            entry->d_ino = 2;
        }
        if (strcmp(entry->d_name, ".dockerenv") == 0)
            return readdir(dirp);
    }
    /* Also fix inode for root when not explicitly listing root
       but the inode check happens via stat("/") */
    return entry;
}

/* Hook stat to fake root inode */
int __xstat(int ver, const char *path, struct stat *buf) {
    int ret;
    init_funcs();
    if (path && strcmp(path, "/.dockerenv") == 0) {
        errno = ENOENT;
        return -1;
    }
    if (real___xstat) {
        ret = real___xstat(ver, path, buf);
        if (ret == 0 && path && strcmp(path, "/") == 0) {
            buf->st_ino = 2;
        }
        return ret;
    }
    errno = ENOSYS;
    return -1;
}

int __lxstat(int ver, const char *path, struct stat *buf) {
    int ret;
    init_funcs();
    if (path && strcmp(path, "/.dockerenv") == 0) {
        errno = ENOENT;
        return -1;
    }
    if (real___lxstat) {
        ret = real___lxstat(ver, path, buf);
        if (ret == 0 && path && strcmp(path, "/") == 0) {
            buf->st_ino = 2;
        }
        return ret;
    }
    errno = ENOSYS;
    return -1;
}

/* === open hook === */

int open(const char *pathname, int flags, ...) {
    int type;
    init_funcs();
    type = detect_type(pathname);

    if (type == 3) {
        errno = ENOENT;
        return -1;
    }
    if (type == 1 || type == 2 || type == 4) {
        return make_fake_fd(type);
    }

    if (flags & O_CREAT) {
        va_list ap;
        mode_t mode;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

/* open64 alias */
int open64(const char *pathname, int flags, ...) {
    int type;
    init_funcs();
    type = detect_type(pathname);

    if (type == 3) {
        errno = ENOENT;
        return -1;
    }
    if (type == 1 || type == 2 || type == 4) {
        return make_fake_fd(type);
    }

    if (flags & O_CREAT) {
        va_list ap;
        mode_t mode;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
        return real_open(pathname, flags, mode);
    }
    return real_open(pathname, flags);
}

/* === fopen hook === */

FILE* fopen(const char *pathname, const char *mode) {
    int type;
    init_funcs();
    type = detect_type(pathname);

    if (type == 3) {
        errno = ENOENT;
        return NULL;
    }
    if (type == 1 || type == 2 || type == 4) {
        FILE *tmp = tmpfile();
        if (tmp) {
            const char *content;
            if (type == 1 || type == 4)
                content = FAKE_CGROUP;
            else
                content = FAKE_MOUNTINFO;
            fputs(content, tmp);
            rewind(tmp);
            return tmp;
        }
    }
    return real_fopen(pathname, mode);
}

FILE* fopen64(const char *pathname, const char *mode) {
    return fopen(pathname, mode);
}

/* === access hook === */

int access(const char *pathname, int mode) {
    init_funcs();
    if (pathname && strcmp(pathname, "/.dockerenv") == 0) {
        errno = ENOENT;
        return -1;
    }
    return real_access(pathname, mode);
}

/* stat hooks moved into readdir section above */

/* === syscall hook — intercept raw getdents/fstat syscalls === */
#include <sys/syscall.h>

static long (*real_syscall)(long, ...) = NULL;

long syscall(long number, ...) {
    va_list ap;
    long a1, a2, a3, a4, a5, a6;
    long ret;

    if (!real_syscall)
        real_syscall = dlsym(RTLD_NEXT, "syscall");

    va_start(ap, number);
    a1 = va_arg(ap, long);
    a2 = va_arg(ap, long);
    a3 = va_arg(ap, long);
    a4 = va_arg(ap, long);
    a5 = va_arg(ap, long);
    a6 = va_arg(ap, long);
    va_end(ap);

    ret = real_syscall(number, a1, a2, a3, a4, a5, a6);

    /* Intercept SYS_getdents on root dir fd */
    if ((number == SYS_getdents || number == SYS_getdents64) &&
        (int)a1 == root_dir_fd && root_dir_fd >= 0 && ret > 0) {
        char *buf = (char*)a2;
        long bpos = 0;
        while (bpos < ret) {
            struct linux_dirent *d = (struct linux_dirent*)(buf + bpos);
            if (strcmp(d->d_name, ".") == 0 || strcmp(d->d_name, "..") == 0) {
                d->d_ino = 2;
            }
            if (strcmp(d->d_name, ".dockerenv") == 0) {
                int reclen = d->d_reclen;
                memmove(buf + bpos, buf + bpos + reclen, ret - bpos - reclen);
                ret -= reclen;
                continue;
            }
            bpos += d->d_reclen;
        }
    }

    /* Intercept SYS_fstat on root dir fd */
    if (number == SYS_fstat && (int)a1 == root_dir_fd && root_dir_fd >= 0 && ret == 0) {
        struct stat *buf = (struct stat*)a2;
        buf->st_ino = 2;
    }

    return ret;
}

/* constructor */
static void __attribute__((constructor)) bypass_init(void) {
    init_funcs();
    unlink("/.dockerenv");
}
