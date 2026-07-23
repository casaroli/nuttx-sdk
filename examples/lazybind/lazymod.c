/* Linked without -z now, so its imported function descriptors land in
 * DT_JMPREL instead of DT_REL.
 */
#include <syslog.h>
#include <stdlib.h>

int main(int argc, char *argv[])
{
  int seed = (argc > 1) ? atoi(argv[1]) : 1;

  syslog(LOG_INFO, "[lazymod] called through a DT_JMPREL descriptor, "
         "seed %d\n", seed);
  return 0;
}
