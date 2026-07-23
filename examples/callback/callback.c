/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Copyright 2026 Marco Casaroli
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Hands a module function to the firmware, four different ways.
 *
 * In FDPIC a function pointer is the address of a two-word descriptor, not
 * a code address, and that descriptor lives in the module's writable
 * segment in RAM.  Firmware that stores such a pointer and later branches to
 * it therefore jumps into the module's *data* and faults -- unless the entry
 * point it came through resolved the descriptor first.
 *
 * qsort and bsearch have always done that.  pthread_create, signal and
 * task_create did not, which made them look usable and then take the board
 * down.  This module is what keeps all of them honest.
 *
 * Everything is checked by observing a side effect the callback itself
 * produces, because a callback that never runs is the failure being tested
 * for -- and on this target the alternative failure is a HardFault, which
 * reports nothing at all.
 */

#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#define FAIL_QSORT    0x01
#define FAIL_PTHREAD  0x02
#define FAIL_SIGNAL   0x04
#define FAIL_TASK     0x08

/* Written by the callbacks, read by main.  These live in the module's
 * writable segment, which is what the callback can only reach if it was
 * entered with this module's data base in the FDPIC register.
 */

static volatile int g_qsort_calls;
static volatile int g_thread_ran;
static volatile int g_signal_ran;
static volatile int g_task_ran;

static int cmp_int(const void *a, const void *b)
{
  g_qsort_calls++;
  return *(const int *)a - *(const int *)b;
}

static void *thread_main(void *arg)
{
  g_thread_ran = (int)(intptr_t)arg;
  return NULL;
}

static void sig_handler(int signo)
{
  g_signal_ran = signo;
}

static int task_main(int argc, char *argv[])
{
  g_task_ran = 1;
  return 0;
}

int main(int argc, char *argv[])
{
  int v[5] = { 5, 3, 1, 4, 2 };
  pthread_t tid;
  int fails = 0;
  int i;

  /* qsort -- the path that always worked */

  qsort(v, 5, sizeof(int), cmp_int);
  if (g_qsort_calls == 0 || v[0] != 1 || v[4] != 5)
    {
      fails |= FAIL_QSORT;
    }

  /* pthread_create.  The thread inherits this module's D-Space, so it can
   * reach g_thread_ran only if it was entered at the right address.
   */

  if (pthread_create(&tid, NULL, thread_main, (void *)(intptr_t)7) != 0)
    {
      fails |= FAIL_PTHREAD;
    }
  else
    {
      pthread_join(tid, NULL);
      if (g_thread_ran != 7)
        {
          fails |= FAIL_PTHREAD;
        }
    }

  /* signal, delivered to this task */

  if (signal(SIGUSR1, sig_handler) == SIG_ERR)
    {
      fails |= FAIL_SIGNAL;
    }
  else
    {
      /* raise() rather than kill(getpid(), ...): getpid is not in the
       * firmware's export list, and raise targets the calling thread, which
       * is exactly what this is checking.
       */

      raise(SIGUSR1);

      for (i = 0; i < 50 && g_signal_ran == 0; i++)
        {
          usleep(10000);
        }

      if (g_signal_ran != SIGUSR1)
        {
          fails |= FAIL_SIGNAL;
        }
    }

  /* task_create.  A separate task, but the same D-Space. */

  if (task_create("cbtask", SCHED_PRIORITY_DEFAULT, 2048, task_main,
                  NULL) < 0)
    {
      fails |= FAIL_TASK;
    }
  else
    {
      for (i = 0; i < 50 && g_task_ran == 0; i++)
        {
          usleep(10000);
        }

      if (g_task_ran == 0)
        {
          fails |= FAIL_TASK;
        }
    }

  syslog(LOG_INFO, "[callback] qsort=%d pthread=%d signal=%d task=%d -- %s\n",
         g_qsort_calls, g_thread_ran, g_signal_ran, g_task_ran,
         fails == 0 ? "PASS" : "FAIL");

  return fails;
}
