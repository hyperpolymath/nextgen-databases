// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal test - just call fdb_version

#include <stdio.h>

extern int fdb_version(void);

int main() {
    printf("Calling fdb_version...\n");
    int version = fdb_version();
    printf("Version: %d\n", version);
    return 0;
}
