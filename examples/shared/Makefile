# A shared library and a module that uses it.
#
# The library is built exactly like a module except that it has no entry
# point and is named by its SONAME, which is what the consumer records in
# DT_NEEDED and what the loader searches for at run time.

NUTTX_DIR ?= $(error set NUTTX_DIR)
SDK       := ../..

all: libcounter.so user.fdpic

libcounter.so: libcounter.c
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=libcounter SRCS=libcounter.c \
	    NUTTX_DIR=$(NUTTX_DIR) ENTRY=0 \
	    EXTRA_LDFLAGS="-soname libcounter.so"
	mv libcounter.fdpic libcounter.so

user.fdpic: user.c libcounter.so
	$(MAKE) -f $(SDK)/nuttx-fdpic.mk MODULE=user SRCS=user.c \
	    NUTTX_DIR=$(NUTTX_DIR) LIBS=libcounter.so

clean:
	rm -f *.o *.fdpic *.so .nuttx-exports
