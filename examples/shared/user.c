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
