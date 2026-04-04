#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>

typedef ssize_t (*orig_read_t)(int fd, void *buf, size_t count);

static int check_maps_fd(int fd) {
    char fdpath[64];
    char linkbuf[256];
    ssize_t len;
    snprintf(fdpath, sizeof(fdpath), "/proc/self/fd/%d", fd);
    len = readlink(fdpath, linkbuf, sizeof(linkbuf) - 1);
    if (len > 0) {
        linkbuf[len] = '\0';
        if (strstr(linkbuf, "/maps"))
            return 1;
    }
    return 0;
}

ssize_t read(int fd, void *buf, size_t count) {
    static orig_read_t orig_read = NULL;
    if (!orig_read) {
        orig_read = (orig_read_t)dlsym(RTLD_NEXT, "read");
    }

    ssize_t ret = orig_read(fd, buf, count);

    if (ret > 0 && check_maps_fd(fd)) {
        char *s = (char *)buf;
        ssize_t i;
        for (i = 0; i < ret; i++) {
            if (s[i] == '\n' && i + 1 < ret) {
                char *line = &s[i+1];
                char *end = memchr(line, '\n', ret - i - 1);
                if (!end) end = s + ret;
                int linelen = end - line;
                if (linelen > 0 && line[0] != ' ') {
                    char *dash = memchr(line, '-', linelen);
                    if (!dash) {
                        memmove(line, end, (s + ret) - end);
                        ret -= (end - line);
                    }
                }
            }
        }
    }
    return ret;
}
