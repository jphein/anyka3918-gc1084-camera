#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
    printf("hello from a binary we built ourselves\n");
    printf("  argc=%d  pid=%d  uid=%d\n", argc, (int)getpid(), (int)getuid());
    return 0;
}
