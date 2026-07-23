/* Demonstrates the two things worth knowing about NuttX FDPIC modules.
 *
 * 1. qsort() runs in the firmware and calls back into compare(), which
 *    lives here.  That works because the firmware reserves the FDPIC
 *    register, so this module's data base survives the call in, and
 *    because libc resolves the callback descriptor on the way back out.
 *
 * 2. g_data is module data.  Every running instance gets a private copy,
 *    while the code itself is shared and executed in place from flash.
 */

#include <stdlib.h>
#include <syslog.h>
#include <unistd.h>

#define N 8

static int compare(const void *a, const void *b)
{
  return *(const int *)a - *(const int *)b;
}

static int g_data[N];

int main(int argc, char *argv[])
{
  int seed = (argc > 1) ? atoi(argv[1]) : 0;
  int i;

  for (i = 0; i < N; i++)
    {
      g_data[i] = (N - i) * 10 + seed;
    }

  /* Overlap with any other instance, so shared data would show up as
   * corruption rather than passing by luck.
   */

  usleep(300000);

  qsort(g_data, N, sizeof(int), compare);

  syslog(LOG_INFO, "[inst %d] %d %d %d %d %d %d %d %d\n", seed,
         g_data[0], g_data[1], g_data[2], g_data[3],
         g_data[4], g_data[5], g_data[6], g_data[7]);
  return 0;
}
