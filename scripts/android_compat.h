/* Android Bionic compatibility shims for PHP cross-compilation */
#pragma once

#ifdef __ANDROID__

#include <sys/resource.h>

/* getdtablesize() — returns max number of open file descriptors */
static inline int getdtablesize(void) {
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) == 0) {
        return (int)limit.rlim_cur;
    }
    return 1024;
}

#endif /* __ANDROID__ */
