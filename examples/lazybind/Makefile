# A module whose imports live in DT_JMPREL rather than DT_REL.
#
# This one is deliberately built the wrong way.  Every other example links
# through the gcc driver, which passes -z now, and that is what puts an
# imported function's descriptor in DT_REL.  Here the linker is invoked
# directly and -z now is left off, so the same descriptors go to the lazy
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
