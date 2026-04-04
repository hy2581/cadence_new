#include <sys/personality.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: noaslr <command> [args...]\n");
        return 1;
    }
    if (personality(ADDR_NO_RANDOMIZE) == -1) {
        perror("personality");
    }
    execvp(argv[1], &argv[1]);
    perror("execvp");
    return 1;
}
