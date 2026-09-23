#define _GNU_SOURCE

#include <fcntl.h>
#include <stdio.h>

#ifdef __APPLE__
#define SWAP_DIRECTORIES(a, b) \
  renameatx_np(AT_FDCWD, (a), AT_FDCWD, (b), RENAME_SWAP)
#elif defined(__linux__)
#include <linux/fs.h>
#include <sys/syscall.h>
#include <unistd.h>
#define SWAP_DIRECTORIES(a, b) \
  syscall(SYS_renameat2, AT_FDCWD, (a), AT_FDCWD, (b), RENAME_EXCHANGE)
#else
#error Atomic tree swap is supported only on macOS and Linux.
#endif

int main(int argc, char **argv) {
  if (argc != 3) {
    fputs("usage: otzaria-atomic-swap installed prepared\n", stderr);
    return 2;
  }
  if (SWAP_DIRECTORIES(argv[1], argv[2]) != 0) {
    perror("atomic directory swap");
    return 1;
  }
  return 0;
}
