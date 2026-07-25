// SPDX-License-Identifier: Apache-2.0
// Fixed-signature host wrappers used by the bootstrap frontend.

#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>

int weave_rt_open_write_trunc(const char *path, int mode)
{
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);
}
