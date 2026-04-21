/*
 * snpslmd_ptrace_wrapper.c
 * Uses ptrace to intercept getdents/fstat syscalls and modify their results
 * to hide Docker container indicators from snpslmd_bin.
 *
 * This runs as a parent process that ptrace-traces snpslmd_bin,
 * intercepting getdents and fstat on the root directory to fake inode=2.
 *
 * Compile: gcc -o snpslmd_ptrace snpslmd_ptrace_wrapper.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/limits.h>

/* Read a null-terminated string from traced process memory */
static int read_string(pid_t pid, unsigned long addr, char *buf, int maxlen) {
    int i;
    for (i = 0; i < maxlen - 1; i += sizeof(long)) {
        long val = ptrace(PTRACE_PEEKDATA, pid, addr + i, NULL);
        memcpy(buf + i, &val, sizeof(long));
        if (memchr(&val, 0, sizeof(long))) break;
    }
    buf[maxlen - 1] = '\0';
    return 0;
}

/* Write data to traced process memory */
static void write_data(pid_t pid, unsigned long addr, void *data, int len) {
    int i;
    for (i = 0; i < len; i += sizeof(long)) {
        long val = 0;
        int chunk = (len - i < (int)sizeof(long)) ? (len - i) : (int)sizeof(long);
        if (chunk < (int)sizeof(long))
            val = ptrace(PTRACE_PEEKDATA, pid, addr + i, NULL);
        memcpy(&val, (char*)data + i, chunk);
        ptrace(PTRACE_POKEDATA, pid, addr + i, val);
    }
}

/* Modify getdents buffer: set inode=2 for "." and "..", remove ".dockerenv" */
static long fix_getdents(pid_t pid, unsigned long buf_addr, long nread) {
    char *buf;
    long bpos;
    long new_nread = nread;

    if (nread <= 0) return nread;
    buf = malloc(nread);
    if (!buf) return nread;

    /* Read buffer from traced process */
    {
        int i;
        for (i = 0; i < nread; i += sizeof(long)) {
            long val = ptrace(PTRACE_PEEKDATA, pid, buf_addr + i, NULL);
            int chunk = (nread - i < (int)sizeof(long)) ? (nread - i) : (int)sizeof(long);
            memcpy(buf + i, &val, chunk);
        }
    }

    bpos = 0;
    while (bpos < new_nread) {
        unsigned long *d_ino = (unsigned long*)(buf + bpos);
        unsigned short *d_reclen = (unsigned short*)(buf + bpos + sizeof(unsigned long) + sizeof(unsigned long));
        char *d_name = buf + bpos + sizeof(unsigned long) + sizeof(unsigned long) + sizeof(unsigned short);

        if (strcmp(d_name, ".") == 0 || strcmp(d_name, "..") == 0) {
            *d_ino = 2;
        }
        if (strcmp(d_name, ".dockerenv") == 0) {
            int reclen = *d_reclen;
            memmove(buf + bpos, buf + bpos + reclen, new_nread - bpos - reclen);
            new_nread -= reclen;
            continue;
        }
        bpos += *d_reclen;
    }

    /* Write modified buffer back */
    write_data(pid, buf_addr, buf, new_nread);
    free(buf);
    return new_nread;
}

int main(int argc, char **argv) {
    pid_t child;
    int status;
    int root_fd = -1;
    char real_bin[] = "/usr/synopsys/11.9/amd64/bin/snpslmd_bin";

    child = fork();
    if (child == 0) {
        /* Child: trace self, then exec snpslmd_bin */
        ptrace(PTRACE_TRACEME, 0, NULL, NULL);
        execv(real_bin, argv);
        perror("execv");
        exit(1);
    }

    /* Parent: trace the child */
    waitpid(child, &status, 0);
    ptrace(PTRACE_SETOPTIONS, child, NULL,
           PTRACE_O_TRACESYSGOOD | PTRACE_O_EXITKILL);

    while (1) {
        struct user_regs_struct regs;

        /* Syscall entry */
        ptrace(PTRACE_SYSCALL, child, NULL, NULL);
        waitpid(child, &status, 0);
        if (WIFEXITED(status)) break;

        ptrace(PTRACE_GETREGS, child, NULL, &regs);
        long syscall_nr = regs.orig_rax;

        /* Syscall exit */
        ptrace(PTRACE_SYSCALL, child, NULL, NULL);
        waitpid(child, &status, 0);
        if (WIFEXITED(status)) break;

        ptrace(PTRACE_GETREGS, child, NULL, &regs);

        /* Track openat("/") → save fd */
        if (syscall_nr == SYS_openat && (long)regs.rax >= 0) {
            char path[256];
            read_string(child, regs.rsi, path, sizeof(path));
            if (strcmp(path, "/") == 0)
                root_fd = (int)regs.rax;
        }

        /* Fix fstat on root fd: set st_ino = 2 */
        if (syscall_nr == SYS_fstat && (int)regs.rdi == root_fd &&
            root_fd >= 0 && (long)regs.rax == 0) {
            unsigned long ino = 2;
            /* st_ino is at offset 8 in struct stat on x86_64 */
            write_data(child, regs.rsi + 8, &ino, sizeof(ino));
        }

        /* Fix getdents on root fd */
        if ((syscall_nr == SYS_getdents || syscall_nr == SYS_getdents64) &&
            (int)regs.rdi == root_fd && root_fd >= 0 && (long)regs.rax > 0) {
            long new_nread = fix_getdents(child, regs.rsi, (long)regs.rax);
            if (new_nread != (long)regs.rax) {
                regs.rax = new_nread;
                ptrace(PTRACE_SETREGS, child, NULL, &regs);
            }
        }
    }

    return WEXITSTATUS(status);
}
