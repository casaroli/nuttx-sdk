/* Uses libcounter.so.  Two instances run concurrently: if the library's
 * data were shared between them the totals would interleave.
 */

#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

extern int counter_bump(int by);
extern int counter_total(void);

int main(int argc, char *argv[])
{
  int seed = (argc > 1) ? atoi(argv[1]) : 0;
  int i;

  for (i = 0; i < 3; i++)
    {
      counter_bump(seed);
      usleep(100000);
    }

  syslog(LOG_INFO, "[user %d] library total = %d (expected %d)\n",
         seed, counter_total(), seed * 3);
  return 0;
}
