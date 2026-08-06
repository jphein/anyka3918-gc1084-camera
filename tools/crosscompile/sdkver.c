/* Proves a binary WE built can dynamically link the vendor SDK and call into it.
   Both functions are pure getters (two instructions, return a string pointer):
   no ioctl, no GPIO, no ISP, no side effects of any kind. */
#include <stdio.h>
const char *ak_drv_ir_get_version(void);
const char *ak_common_get_version(void);
int main(void) {
    printf("libplat_drv    ak_drv_ir_get_version() = %s\n", ak_drv_ir_get_version());
    printf("libplat_common ak_common_get_version() = %s\n", ak_common_get_version());
    return 0;
}
