/* A shared library with its own state.
 *
 * g_calls is the interesting part: it lives in the library's writable
 * segment, and each task that loads the library gets a private copy.  The
 * library's code, meanwhile, is mapped once and executed in place.
 */

#include <syslog.h>

static int g_calls;

int counter_bump(int by);
int counter_total(void);

int counter_bump(int by)
{
  g_calls += by;
  return g_calls;
}

int counter_total(void)
{
  return g_calls;
}
