# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2026 Marco Casaroli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# A module whose imports live in DT_JMPREL rather than DT_REL.
#
# This one is deliberately built the wrong way.  Every other example passes
# -z now, and that is what keeps an imported function's descriptor in
# DT_REL.  Here it is left off, so the same descriptors go to the lazy
# binding table instead -- and for this module there is no DT_REL at all.
#
# The loader has no lazy resolver, so a DT_JMPREL table it did not walk was
# not deferred work: the descriptors simply stayed unrelocated and the first
# call into the firmware branched to an unrelocated address.  The symptom
# was an INVSTATE UsageFault escalated to a HardFault -- a blinking LED, a
# dead console, and no crash dump.  Binding both tables eagerly is what
# makes this module run, and this example is here so that stays true.
#
# Nothing else should be built this way.  It exists to be the awkward case.

NUTTX_DIR ?= $(error set NUTTX_DIR)

CPU       ?= cortex-m33
FDPIC_LD  ?= arm-uclinuxfdpiceabi-ld

# ?= is not enough: make has a built-in default for CC, so it never fires
# and the host compiler gets the job.

ifeq ($(origin CC),default)
  CC := arm-none-eabi-gcc
endif

all: lazymod.fdpic

lazymod.o: lazymod.c
	$(CC) -mcpu=$(CPU) -mthumb -mfdpic -fPIC -Os -fno-builtin -Wall \
	    -D__STDC_NO_ATOMICS__ -I$(NUTTX_DIR)/include -D__NuttX__ \
	    -c $< -o $@

lazymod.fdpic: lazymod.o
	$(FDPIC_LD) -m armelf_linux_fdpiceabi -shared -e main -o $@ $<
	@echo "--- expect JMPREL/PLTRELSZ and no RELSZ:"
	@arm-uclinuxfdpiceabi-readelf -d $@ | grep -E 'JMPREL|PLTREL|RELSZ' || true

clean:
	rm -f lazymod.o lazymod.fdpic
