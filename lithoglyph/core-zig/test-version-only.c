// SPDX-License-Identifier: PMPL-1.0-or-later
// Minimal test - just call lith_version

#include <stdio.h>

extern int lith_version(void);

int main() {
    printf("Calling lith_version...\n");
    int version = lith_version();
    printf("Version: %d\n", version);
    return 0;
}
