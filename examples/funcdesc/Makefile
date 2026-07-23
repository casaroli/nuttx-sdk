# A module that exercises R_ARM_FUNCDESC.
#
# Built the ordinary way -- there is nothing special about the link.  What
# makes it different is the source: it takes the *address* of imported
# functions, which is what makes the linker ask the loader to manufacture
# descriptors rather than laying them out itself.

NUTTX_DIR ?= $(error set NUTTX_DIR)
SDK       := ../..

all: funcdesc.fdpic

funcdesc.fdpic: funcdesc.c
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=funcdesc SRCS=funcdesc.c \
	    NUTTX_DIR=$(NUTTX_DIR)

clean:
	rm -f *.o *.fdpic .nuttx-exports
