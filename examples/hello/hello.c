/* Smallest possible NuttX FDPIC module.
 *
 * Nothing is linked in: printf comes from the firmware's exported symbol
 * table, resolved when the module is loaded.
 */

#include <stdio.h>

int main(int argc, char *argv[])
{
  printf("hello from an FDPIC module, argc=%d\n", argc);
  return 0;
}
