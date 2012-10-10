# Linux/386 SPITBOL
#


# SPITBOL Version:
VERS=   linux
DEBUG=	1

# Minimal source directory.
MINPATH=./

OSINT=./osint

vpath %.c $(OSINT)



CC=     gcc
AS=nasm
ifeq	($(DEBUG),0)
CFLAGS= -m32 -O2 -fno-leading-underscore -mfpmath=387
else
CFLAGS= -g -m32 -fno-leading-underscore -mfpmath=387
endif

# Assembler info -- Intel 32-bit syntax
ifeq	($(DEBUG),0)
ASFLAGS = -f elf
else
ASFLAGS = -f elf -g
endif

# Tools for processing Minimal source file.
TOK=	token.spt
COD=    ncodlinux.spt
ERR=    err386.spt
SPIT=   ./bin/spitbol

# Implicit rule for building objects from C files.

./%.o: %.c
#.c.o:
	$(CC) -c $(CFLAGS) -o$@ $(OSINT)/$*.c

# Implicit rule for building objects from assembly language files.
.s.o:
	$(AS) -l=$*.lst -o $@ $(ASFLAGS) $*.s

# C Headers common to all versions and all source files of SPITBOL:
CHDRS =	$(OSINT)/osint.h $(OSINT)/port.h $(OSINT)/sproto.h $(OSINT)/spitio.h $(OSINT)/spitblks.h $(OSINT)/globals.h

# C Headers unique to this version of SPITBOL:
UHDRS=	$(OSINT)/systype.h $(OSINT)/extern32.h $(OSINT)/blocks32.h $(OSINT)/system.h

# Headers common to all C files.
HDRS=	$(CHDRS) $(UHDRS)

# Headers for Minimal source translation:
VHDRS=	$(VERS).cnd $(VERS).def $(VERS).hdr hdrdata.inc hdrcode.inc

# OSINT objects:
SYSOBJS=sysax.o sysbs.o sysbx.o syscm.o sysdc.o sysdt.o sysea.o \
	sysef.o sysej.o sysem.o sysen.o sysep.o sysex.o sysfc.o \
	sysgc.o syshs.o sysid.o sysif.o sysil.o sysin.o sysio.o \
	sysld.o sysmm.o sysmx.o sysou.o syspl.o syspp.o sysrw.o \
	sysst.o sysstdio.o systm.o systty.o sysul.o sysxi.o trace.o

# Other C objects:
COBJS =	arg2scb.o break.o checkfpu.o compress.o cpys2sc.o doexec.o \
	doset.o dosys.o fakexit.o float.o flush.o gethost.o getshell.o \
	int.o lenfnm.o math.o optfile.o osclose.o \
	osopen.o ospipe.o osread.o oswait.o oswrite.o prompt.o rdenv.o \
	sioarg.o st2d.o stubs.o swcinp.o swcoup.o syslinux.o testty.o\
	trypath.o wrtaout.o 

# Assembly langauge objects common to all versions:
CAOBJS = errors.o ninter.o 

# Objects for SPITBOL's HOST function:
#HOBJS=	hostrs6.o scops.o kbops.o vmode.o
HOBJS=

# Objects for SPITBOL's LOAD function.  AIX 4 has dlxxx function library.
#LOBJS=  load.o
#LOBJS=  dlfcn.o load.o
LOBJS=

# main objects:
MOBJS=	main.o getargs.o

# All assembly language objects
AOBJS = $(CAOBJS)

# Minimal source object file:
VOBJS =	v38.o 

# All objects:
OBJS=	$(AOBJS) $(COBJS) $(HOBJS) $(LOBJS) $(SYSOBJS) $(VOBJS) $(MOBJS)

# main program
spitbol: $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -lm  -ospitbol -Wl,-M,-Map,spitbol.map

# Assembly language dependencies:

# SPITBOL Minimal source
v38.s:	v38.tok $(VHDRS) $(COD) 
	  $(SPIT) -u "v38:$(VERS):comments" $(COD)

v38.tok: $(MINPATH)v38.min $(VERS).cnd $(TOK)
	 $(SPIT) -u "$(MINPATH)v38:$(VERS):v38" $(TOK)

v38.err: v38.s

errors.s: $(VERS).cnd $(ERR) v38.s
	   $(SPIT) -1=v38.err -2=errors.s $(ERR)

# make osint objects
cobjs:	$(COBJS)

# C language header dependencies:
$(COBJS): $(HDRS)
$(MOBJS): $(HDRS)
$(SYSOBJS): $(HDRS)
main.o: $(OSINT)/save.h
sysgc.o: $(OSINT)/save.h
sysxi.o: $(OSINT)/save.h
dlfcn.o: dlfcn.h

boot:
	cp -p bootstrap/v38.s bootstrap/v38.tok bootstrap/errors.s .

install:
	sudo cp spitbol /usr/local/bin
clean:
	rm -f $(OBJS) *.lst *.map *.err v38.tok v38.tmp v38.s errors.s
