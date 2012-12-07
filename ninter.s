;	SPITBOL ASSEMBLY-LANGUAGE TO C-LANGUAGE O/S INTERFACE
; Copyright 1987-2012 Robert B. K. Dewar and Mark Emmer.
; 
; This file is part of Macro SPITBOL.
; 
;     Macro SPITBOL is free software: you can redistribute it and/or modify
;     it under the terms of the GNU General Public License as published by
;     the Free Software Foundation, either version 3 of the License, or
;     (at your option) any later version.
; 
;     Macro SPITBOL is distributed in the hope that it will be useful,
;     but WITHOUT ANY WARRANTY; without even the implied warranty of
;     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;     GNU General Public License for more details.
; 
;     You should have received a copy of the GNU General Public License
;     along with Macro SPITBOL.  If not, see <http://www.gnu.org/licenses/>.
;
%define globals 1                       ;ASM globals defined here
        %include        "systype.nh"
        %include        "osint.inc"

;
;       File: inter.s           Version: 1.46
;       ---------------------------------------
;
;       This file contains the assembly language routines that interface
;       the Macro SPITBOL compiler written in 80386 assembly language to its
;       operating system interface functions written in C.
;
;       Contents:
;
;       o Overview
;       o Global variables accessed by OSINT functions
;       o Interface routines between compiler and OSINT functions
;       o C callable function startup
;       o C callable function get_fp
;       o C callable function restart
;       o C callable function makeexec
;       o Routines for Minimal opcodes CHK and CVD
;       o Math functions for integer multiply, divide, and remainder
;       o Math functions for real operation
;
;-----------
;
;       Overview
;
;       The Macro SPITBOL compiler relies on a set of operating system
;       interface functions to provide all interaction with the host
;       operating system.  These functions are referred to as OSINT
;       functions.  A typical call to one of these OSINT functions takes
;       the following form in the 80386 version of the compiler:
;
;               ...code to put arguments in registers...
;               call    SYSXX           ; call osint function
;               dd      EXIT_1          ; address of exit point 1
;               dd      EXIT_2          ; address of exit point 2
;               ...     ...             ; ...
;               dd      EXIT_n          ; address of exit point n
;               ...instruction following call...
;
;       The OSINT function 'SYSXX' can then return in one of n+1 ways:
;       to one of the n exit points or to the instruction following the
;       last exit.  This is not really very complicated - the call places
;       the return address on the stack, so all the interface function has
;       to do is add the appropriate offset to the return address and then
;       pick up the exit address and jump to it OR do a normal return via
;       an ret instruction.
;
;       Unfortunately, a C function cannot handle this scheme.  So, an
;       intermediary set of routines have been established to allow the
;       interfacing of C functions.  The mechanism is as follows:
;
;       (1) The compiler calls OSINT functions as described above.
;
;       (2) A set of assembly language interface routines is established,
;           one per OSINT function, named accordingly.  Each interface
;           routine ...
;
;           (a) saves all compiler registers in global variables
;               accessible by C functions
;           (b) calls the OSINT function written in C
;           (c) restores all compiler registers from the global variables
;           (d) inspects the OSINT function's return value to determine
;               which of the n+1 returns should be taken and does so
;
;       (3) A set of C language OSINT functions is established, one per
;           OSINT function, named differently than the interface routines.
;           Each OSINT function can access compiler registers via global
;           variables.  NO arguments are passed via the call.
;
;           When an OSINT function returns, it must return a value indicating
;           which of the n+1 exits should be taken.  These return values are
;           defined in header file 'inter.h'.
;
;       Note:  in the actual implementation below, the saving and restoring
;       of registers is actually done in one common routine accessed by all
;       interface routines.
;
;       Other notes:
;
;       Some C ompilers transform "internal" global names to
;       "external" global names by adding a leading underscore at the front
;       of the internal name.  Thus, the function name 'osopen' becomes
;       '_osopen'.  However, not all C compilers follow this convention.
;
;------------
;
;       Global Variables
;
	segment	.text
	extern	swcoupj

        segment	.data
	extern	stacksiz
	extern	lmodstk
	extern	lowsp
	extern	outptr
	extern	calltab
%if direct == 0
        extern     valtab
%endif

        %include "extrn386.inc"


; Words saved during exit(-3)
;
        align 4
	global	reg_block
	global	reg_wa
	global	reg_wb
	global	reg_ia
	global	reg_wc
	global	reg_xr
	global	reg_xl
	global	reg_cp
	global	reg_ra
reg_block:
reg_wa:	dd	0		; WA in ECX
reg_wb:	dd	0		; WB in EBX
reg_ia:
reg_wc:	dd	0		; WC and IA are same (EDX)
reg_xr:	dd	0		; XR in EDI
reg_xl:	dd	0		; XL in ESI
reg_cp:	dd	0	
reg_ra:	dd	0.0
;
; These locations save information needed to return after calling OSINT
; and after a restart from EXIT()
;
	global	reg_pc		; return PC from caller
reg_pc:	dd	0
	global	reg_pp
reg_pp	dd	0		; number of bytes of PPMS (probably dead)
	global	reg_xs
reg_xs:	dd	0		; MINIMAL stack pointer
;
r_size	equ 	$-reg_block
	global	reg_size
reg_size:	dd	r_size
;
; end of words saved during exit(-3)
;

;
;  Constants
;
ten:    dd      10              ; constant 10
	global	inf
inf:	dd	0
        dd      0x7ff00000      ; double precision infinity

sav_block: times r_size db 0     ; Save Minimal registers during push/pop reg
;
        align 4
ppoff:  dd      0               ; offset for ppm exits
compsp: dd      0               ; 1.39 compiler's stack pointer
sav_compsp:
        dd      0               ; save compsp here
osisp:  dd      0               ; 1.39 OSINT's stack pointer
	global	_rc_
_rc_:	dd	0 		; return code from osint procedure

%define SETREAL 0
;
;       Setup a number of internal addresses in the compiler that cannot
;       be directly accessed from within C because of naming difficulties.
;
        pubdef  ID1,dd   ,0
%if SETREAL == 1
        dd       2
        .ascii  "1x\x00\x00"
.else
        dd       1
        .ascii  "1x\x00\x00\x00"
%endif
;
	global	ID2BLK
	dd	52
        dd      0
	times	52 db 0

	global	TICBLK
IICBLK	dd	0
        dd      0

	global	TSCBLK
TSCBLK	dd	512
        dd      0
	times	512 db 0

;
;       Standard input buffer block.
;
	global	INPBUF
INPBUF:	dd	0		; type word
        dd      0               ; block length
        dd      1024            ; buffer size
        dd      0               ; remaining chars to read
        dd      0               ; offset to next character to read
        dd      0               ; file position of buffer
        dd      0               ; physical position in file
	times	1024 db 0	; buffer
;
	global	TTYBUF
TTYBUF:	dd	0		; type word
        dd      0               ; block length
        dd      260             ; buffer size  (260 OK in MS-DOS with cinread())
        dd      0               ; remaining chars to read
        dd      0               ; offset to next char to read
        dd      0               ; file position of buffer
        dd      0               ; physical position in file
	times	260 db 0	; buffer


	segment	.text
;
;-----------
;
;       Save and restore MINIMAL and interface registers on stack.
;       Used by any routine that needs to call back into the MINIMAL
;       code in such a way that the MINIMAL code might trigger another
;       SYSxx call before returning.
;
;       Note 1:  pushregs returns a collectable value in XL, safe
;       for subsequent call to memory allocation routine.
;
;       Note 2:  these are not recursive routines.  Only reg_xl is
;       saved on the stack, where it is accessible to the garbage
;       collector.  Other registers are just moved to a temp area.
;
;       Note 3:  popregs does not restore REG_CP, because it may have
;       been modified by the Minimal routine called between pushregs
;       and popregs as a result of a garbage collection.  Calling of
;       another SYSxx routine in between is not a problem, because
;       CP will have been preserved by Minimal.
;
;       Note 4:  if there isn't a compiler stack yet, we don't bother
;       saving XL.  This only happens in call of nextef from sysxi when
;       reloading a save file.
;
;
	global	pushregs
pushregs:
	pushad
	lea	esi,[reg_block]
	lea	edi,[sav_block]
	mov	ecx,r_size/4
	cld
   rep	movsd

        mov     edi,dword [compsp]
        or      edi,edi                         ; 1.39 is there a compiler stack
        je      push1                     ; 1.39 jump if none yet
        sub     edi,4                           ;push onto compiler's stack
        mov     esi,dword [reg_xl]                      ;collectable XL
	mov	dword [edi],esi
        mov     dword [compsp],edi                      ;smashed if call OSINT again (SYSGC)
        mov     dword [sav_compsp],edi                  ;used by popregs

push1:	popad
	ret

       
	global	popregs
popregs						;bashes eax,ebx,ecx:
	pushad
        mov     eax,dword [reg_cp]                      ;don't restore CP
	cld
	lea	esi,dword [sav_block]
        lea     edi,dword [reg_block]                   ;unload saved registers
	mov	ecx,r_size/4
   rep  movsd                                   ;restore from temp area
	mov	dword [reg_cp],eax

        mov     edi,dword [sav_compsp]                  ;saved compiler's stack
        or      edi,edi                         ;1.39 is there one?
        je      pop1                      ;1.39 jump if none yet
        mov     esi,dword [edid]                       ;retrieve collectable XL
        mov     dword [reg_xl],esi                      ;update XL
        add     edi,4                           ;update compiler's sp
        mov     dword [compsp],edi

pop1:	popad
	ret

;
;-----------
;
;       Interface routines
;
;       Each interface routine takes the following form:
;
;               SYSXX   call    ccaller         ; call common interface
;                     dd        zysxx           ; address of C OSINT function
;                       db      n               ; offset to instruction after
;                                               ;   last procedure exit
;
;       In an effort to achieve portability of C OSINT functions, we
;       do not take take advantage of any "internal" to "external"
;       transformation of names by C compilers.  So, a C OSINT function
;       representing sysxx is named _zysxx.  This renaming should satisfy
;       all C compilers.
;
;       IMPORTANT  ONE interface routine, SYSFC, is passed arguments on
;       the stack.  These items are removed from the stack before calling
;       ccaller, as they are not needed by this implementation.
;
;
;-----------
;
;       CCALLER is called by the OS interface routines to call the
;       real C OS interface function.
;
;       General calling sequence is
;
;               call    ccaller
;               dd      address_of_C_function
;               db      2*number_of_exit_points
;
;       Control IS NEVER returned to a interface routine.  Instead, control
;       is returned to the compiler (THE caller of the interface routine).
;
;       The C function that is called MUST ALWAYS return an integer
;       indicating the procedure exit to take or that a normal return
;       is to be performed.
;
;               C function      Interpretation
;               return value
;               ------------    -------------------------------------------
;                    <0         Do normal return to instruction past
;                               last procedure exit (distance passed
;                               in by dummy routine and saved on stack)
;                     0         Take procedure exit 1
;                     4         Take procedure exit 2
;                     8         Take procedure exit 3
;                    ...        ...
;
	global	ccaller

;       (1) Save registers in global variables
;
ccaller;
        mov     dword [reg_wa],ecx              ; save registers
	mov	dword [reg_wb],ebx
        mov     dword [reg_wc],edx              ; (also _reg_ia)
	mov	dword [reg_xr],edi
	mov	dword [reg_xl],esi
        mov     dword [reg_cp],ebp              ; Needed in image saved by sysxi

;       (2) Get pointer to arg list
;
        pop     esi                     ; point to arg list
;
;       (3) Fetch address of C function, fetch offset to 1st instruction
;           past last procedure exit, and call C function.
;
        cs                              ; CS segment override
        lodsd                           ; point to C function entry point
;       lodsd   cs:ccaller              ; point to C function entry point
        movzx   ebx,byte [esi]   	; save normal exit adjustment
;
        mov     dword [reg_pp],ebx	; in memory
        pop     dword [reg_pc]          ; save return PC past "CALL SYSXX"
;
;       (3a) Save compiler stack and switch to OSINT stack
;
; DS 12/22/12 Note that needn't save and restore stack ptrs if not using
; 	save files or load modules
         mov     dword [compsp],esp	; 1.39 save compiler's stack pointer
         mov     esp,dword [osisp]	; 1.39 load OSINT's stack pointer
;
;       (3b) Make call to OSINT
;
        call    eax                     ; call C interface function

	mov	dword [_rc_],eax	; save return code from function
;
;       (4) Restore registers after C function returns.
;

cc1:    
 	mov     dword [osisp],esp       ; 1.39 save OSINT's stack pointer
        mov     esp,dword [compsp]      ; 1.39 restore compiler's stack pointer
        mov     ecx,dword [reg_wa]	; restore registers
	mov	ebx,dword [reg_wb]
        mov     edx,dword [reg_wc]	; (also reg_ia)
	mov	edi,dword [reg_xr]
	mov	esi,dword [reg_xl]
	mov	ebp,dword [reg_cp]

	cld

	mov	eax,dword [reg_pc]
	jmp	eax

;
;---------------
;
;       Individual OSINT routine entry points
;
        global SYSAX
	extern	zysax
SYSAX:	call	ccaller
        dd   zysax
        db   0
;
        global SYSBS
	extern	zysbs
SYSBS:	call	ccaller
        dd   zysbs
        db   0
;
        global SYSBX
	extern	zysbx
SYSBX:	mov	reg_xs,esp
	call	ccaller
        dd      zysbx
        db   0
;
%if SETREAL == 1
        global SYSCR
	extern	zyscr
SYSCR:  call    ccaller
        dd      zyscr
        db   0
;
%endif
        global SYSDC
	extern	zysdc
SYSDC:	call	ccaller
        dd      zysdc
        db   0
;
        global SYSDM
	extern	zysdm
SYSDM:	call	ccaller
        dd      zysdm
        db   0
;
        global SYSDT
	extern	zysdt
SYSDT:	call	ccaller
        dd      zysdt
        db   0
;
        global SYSEA
	extern	zysea
SYSEA:	call	ccaller
        dd      zysea
        db   0
;
        global SYSEF
	extern	zysef
SYSEF:	call	ccaller
        dd      zysef
        db   0
;
        global SYSEJ
	extern	zysej
SYSEJ:	call	ccaller
        dd      zysej
        db   0
;
        global SYSEM
	extern	zysem
SYSEM:	call	ccaller
        dd      zysem
        db   0
;
        global SYSEN
	extern	zysen
SYSEN:	call	ccaller
        dd      zysen
        db   0
;
        global SYSEP
	extern	zysep
SYSEP:	call	ccaller
        dd      zysep
        db   0
;
        global SYSEX
	extern	zysex
SYSEX:	mov	reg_xs,esp
	call	ccaller
        dd      zysex
        db   0
;
        global SYSFC
	extern	zysfc
SYSFC:  pop     eax             ; <<<<remove stacked SCBLK>>>>
	lea	esp,[esp+edx*4]
	push	eax
	call	ccaller
        dd      zysfc
        db   0
;
        global SYSGC
	extern	zysgc
SYSGC:	call	ccaller
        dd      zysgc
        db   0
;
        global SYSHS
	extern	zyshs
SYSHS:	mov	reg_xs,esp
	call	ccaller
        dd      zyshs
        db   0
;
        global SYSID
	extern	zysid
SYSID:	call	ccaller
        dd      zysid
        db   0
;
        global SYSIF
	extern	zysif
SYSIF:	call	ccaller
        dd      zysif
        db   0
;
        global SYSIL
	extern	zysil
SYSIL:  call    ccaller
        dd      zysil
        db   0
;
        global SYSIN
	extern	zysin
SYSIN:	call	ccaller
        dd      zysin
        db   0
;
        global SYSIO
	extern	zysio
SYSIO:	call	ccaller
        dd      zysio
        db   0
;
        global SYSLD
	extern	zysld
SYSLD:  call    ccaller
        dd      zysld
        db   0
;
        global SYSMM
	extern	zysmm
SYSMM:	call	ccaller
        dd      zysmm
        db   0
;
        global SYSMX
	extern	zysmx
SYSMX:	call	ccaller
        dd      zysmx
        db   0
;
        global SYSOU
	extern	zysou
SYSOU:	call	ccaller
        dd      zysou
        db   0
;
        global SYSPI
	extern	zyspi
SYSPI:	call	ccaller
        dd      zyspi
        db   0
;
        global SYSPL
	extern	zyspl
SYSPL:	call	ccaller
        dd      zyspl
        db   0
;
        global SYSPP
	extern	zyspp
SYSPP:	call	ccaller
        dd      zyspp
        db   0
;
        global SYSPR
	extern	zyspr
SYSPR:	call	ccaller
        dd      zyspr
        db   0
;
        global SYSRD
	extern	zysrd
SYSRD:	call	ccaller
        dd      zysrd
        db   0
;
        global SYSRI
	extern	zysri
SYSRI:	call	ccaller
        dd      zysri
        db   0
;
        global SYSRW
	extern	zysrw
SYSRW:	call	ccaller
        dd      zysrw
        db   0
;
        global SYSST
	extern	zysst
SYSST:	call	ccaller
        dd      zysst
        db   0
;
        global SYSTM
	extern	zystm
SYSTM:	call	ccaller
systm_p: dd      zystm
        db   0
;
        global SYSTT
	extern	zystt
SYSTT:	call	ccaller
        dd      zystt
        db   0
;
        global SYSUL
	extern	zysul
SYSUL:	call	ccaller
        dd      zysul
        db   0
;
        global SYSXI
	extern	zysxi
SYSXI:	mov	reg_xs,esp
	call	ccaller
sysxi_p: dd      zysxi
        db   0

;
;-----------
;
;       startup( char *dummy1, char *dummy2) - startup compiler
;
;       An OSINT C function calls startup to transfer control
;       to the compiler.
;
;       (XR) = basemem
;       (XL) = topmem - sizeof(WORD)
;
;	Note: This function never returns.
;


	global	startup
startup:
        pop     eax                     ; discard return
        pop     eax                     ; discard dummy1
        pop     eax                     ; discard dummy2
	call	stackinit               ; initialize MINIMAL stack
        mov     eax,dword [compsp]	; get MINIMAL's stack pointer
        SET_WA  eax                     ; startup stack pointer
	cld                             ; default to UP direction for string ops
;        GETOFF  eax,DFFNC               ; get address of PPM offset
        mov     dword [ppoff],eax	; save for use later
;
        mov     esp,dword [osisp]	; switch to new C stack
        MINIMAL START                   ; load regs, switch stack, start compiler


;
;-----------
;
;	stackinit  -- initialize LOWSPMIN from sp.
;
;	Input:  sp - current C stack
;		stacksiz - size of desired Minimal stack in bytes
;
;	Uses:	eax
;
;	Output: register WA, sp, LOWSPMIN, compsp, osisp set up per diagram:
;
;	(high)	+----------------+
;		|  old C stack   |
;	  	|----------------| <-- incoming sp, resultant WA (future XS)
;		|	     ^	 |
;		|	     |	 |
;		/ stacksiz bytes /
;		|	     |	 |
;		|            |	 |
;		|----------- | --| <-- resultant LOWSPMIN
;		| 400 bytes  v   |
;	  	|----------------| <-- future C stack pointer, osisp
;		|  new C stack	 |
;	(low)	|                |
;
;
;

stackinit:
	mov	eax,esp
        mov     dword [compsp],eax	; save as MINIMAL's stack pointer
	sub	eax,dword [stacksiz]	; end of MINIMAL stack is where C stack will start
        mov     dword [osisp],eax	; save new C stack pointer
	add	eax,4*100               ; 100 words smaller for CHK
        SETMINR  LOWSPMIN,eax            ; Set LOWSPMIN
	ret

;
;-----------
;
;       mimimal -- call MINIMAL function from C
;
;       Usage:  extern void minimal(WORD callno)
;
;       where:
;         callno is an ordinal defined in osint.h, osint.inc, and calltab.
;
;       Minimal registers WA, WB, WC, XR, and XL are loaded and
;       saved from/to the register block.
;
;       Note that before restart is called, we do not yet have compiler
;       stack to switch to.  In that case, just make the call on the
;       the OSINT stack.
;

	global	minimal

minimal:
        pushad                          ; save all registers for C
        mov     eax,[esp+32+4]          ; get ordinal
        mov     ecx,dword [reg_wa]	; restore registers
	mov	ebx,dword [reg_wb]
        mov     edx,dword [reg_wc]	; (also _reg_ia)
	mov	edi,dword [reg_xr]
	mov	esi,dword [reg_xl]
	mov	ebp,dword [reg_cp]

        mov     osisp,esp               ; save OSINT stack pointer
        cmp     dword [compsp],0	; is there a compiler stack?
        je      min1			; jump if none yet
        mov     esp,dword [compsp]	; switch to compiler stack

min1:   callc   calltab[eax*4],0        ; off to the Minimal code

        mov     esp,dword [osisp]	; switch to OSINT stack
        mov     dword [reg_wa],ecx      ; save registers
	mov	dword [reg_wb],ebx
	mov	dword [reg_wc],edx
	mov	dword [reg_xr],edi
	mov	dword [reg_xl],esi
	mov	dword [reg_cp],ebp
	popad
	ret



%if	direct == 0
;
;-----------
;
;       minoff -- obtain address of MINIMAL variable
;
;       Usage:  extern WORD *minoff(WORD valno)
;
;       where:
;         valno is an ordinal defined in osint.h, osint.inc and valtab.
;

	global	minoff

minoff:
        mov     eax,dword [esp+4]             ; get ordinal
        mov     eax,dword [valtab+eax*4]       ; get address of Minimal value
	ret

%endif


;
;-----------
;
;       get_fp  - get C caller's FP (frame pointer)
;
;       get_fp() returns the frame pointer for the C function that called
;       this function.  HOWEVER, THIS FUNCTION IS ONLY CALLED BY ZYSXI.
;
;       C function zysxi calls this function to determine the lowest USEFUL
;       word on the stack, so that only the useful part of the stack will be
;       saved in the load module.
;
;       The flow goes like this:
;
;       (1) User's spitbol program calls EXIT function
;
;       (2) spitbol compiler calls interface routine sysxi to handle exit
;
;       (3) Interface routine sysxi passes control to ccaller which then
;           calls C function zysxi
;
;       (4) C function zysxi will write a load module, but needs to save
;           a copy of the current stack in the load module.  The base of
;           the part of the stack to be saved begins with the frame of our
;           caller, so that the load module can execute a return to ccaller.
;
;           This will allow the load module to pretend to be returning from
;           C function zysxi.  So, C function zysxi calls this function,
;           get_fp, to determine the BASE OF THE USEFUL PART OF THE STACK.
;
;           We cheat just a little bit here.  C function zysxi can (and does)
;           have local variables, but we won't save them in the load module.
;           Only the portion of the frame established by the 80386 call
;           instruction, from BP up, is saved.  These local variables
;           aren't needed, because the load module will not be going back
;           to C function zysxi.  Instead when function restart returns, it
;           will act as if C function zysxi is returning.
;
;       (5) After writing the load module, C function zysxi calls C function
;           zysej to terminate spitbol's execution.
;
;       (6) When the resulting load module is executed, C function main
;           calls function restart.  Function restart restores the stack
;           and then does a return.  This return will act as if it is
;           C function zysxi doing the return and the user's program will
;           continue execution following its call to EXIT.
;
;       On entry to _get_fp, the stack looks like
;
;               /      ...      /
;       (high)  |               |
;               |---------------|
;       ZYSXI   |    old PC     |  --> return point in CCALLER
;         +     |---------------|  USEFUL part of stack
;       frame   |    old BP     |  <<<<-- BP of get_fp's caller
;               |---------------|     -
;               |     ZYSXI's   |     -
;               /     locals    /     - NON-USEFUL part of stack
;               |               |     ------
;       ======= |---------------|
;       SP-->   |    old PC     |  --> return PC in C function ZYSXI
;       (low)   +---------------+
;
;       On exit, return EBP in EAX. This is the lower limit on the
;       size of the stack.


	global	get_fp
	

get_fp:
        mov     eax,dword [reg_xs]      ; Minimal's XS
        add     eax,4           	; pop return from call to SYSBX or SYSXI
        ret	    			; done


;
;-----------
;
;       restart - restart for load module
;
;       restart( char *dummy, char *stackbase ) - startup compiler
;
;       The OSINT main function calls restart when resuming execution
;       of a program from a load module.  The OSINT main function has
;       reset global variables except for the stack and any associated
;       variables.
;
;       Before restoring stack, set up values for proper checking of
;       stack overflow. (initial sp here will most likely differ
;       from initial sp when compile was done.)
;
;       It is also necessary to relocate any addresses in the the stack
;       that point within the stack itself.  An adjustment factor is
;       calculated as the difference between the STBAS at exit() time,
;       and STBAS at restart() time.  As the stack is transferred from
;       TSCBLK to the active stack, each word is inspected to see if it
;       points within the old stack boundaries.  If so, the adjustment
;       factor is subtracted from it.
;
;       We use Minimal's INSTA routine to initialize static variables
;       not saved in the Save file.  These values were not saved so as
;       to minimize the size of the Save file.
;
	extern	rereloc

	pubname	restart
	global	restart
restart:
        pop     eax                     ; discard return
        pop     eax                     ; discard dummy
        pop     eax                     ; get lowest legal stack value

        add     eax,dword [stacksiz]	; top of compiler's stack
        mov     esp,eax                 ; switch to this stack
	call	stackinit               ; initialize MINIMAL stack

                                        ; set up for stack relocation
        lea     eax,[TSCBLK+scstr]	; top of saved stack
        mov     ebx,dword [lmodstk]	; bottom of saved stack
        GETMIN  ecx,STBAS               ; ecx = stbas from exit() time
        sub     ebx,eax                 ; ebx = size of saved stack
	mov	edx,ecx
        sub     edx,ebx                 ; edx = stack bottom from exit() time
	mov	ebx,ecx
        sub     ebx,esp                 ; ebx = old stbas - new stbas

        SETMINR  STBAS,esp               ; save initial sp
;        GETOFF  eax,DFFNC               ; get address of PPM offset
        mov     dword [ppoff],eax	; save for use later
;
;       restore stack from TSCBLK.
;
        mov     esi,dword [lmodstk]             ; -> bottom word of stack in TSCBLK
        lea     edi,[TSCBLK+scstr]        ; -> top word of stack
        cmp     esi,edi                 ; Any stack to transfer?
        je      re3               ;  skip if not
	sub	esi,4
	std
re1:    lodsd                           ; get old stack word to eax
        cmp     eax,edx                 ; below old stack bottom?
        jb      re2               ;   j. if eax < edx
        cmp     eax,ecx                 ; above old stack top?
        ja      re2               ;   j. if eax > ecx
        sub     eax,ebx                 ; within old stack, perform relocation
re2:    push    eax                     ; transfer word of stack
        cmp     esi,edi                 ; if not at end of relocation then
        jae     re1                     ;    loop back

re3:	cld
        mov     dword [compsp],esp              ; 1.39 save compiler's stack pointer
        mov     esp,dword [osisp]               ; 1.39 back to OSINT's stack pointer
        callc   rereloc,0               ; V1.08 relocate compiler pointers into stack
        GETMIN  eax,STATB               ; V1.34 start of static region to XR
	SET_XR  eax
        MINIMAL INSTA                   ; V1.34 initialize static region

;
;       Now pretend that we're executing the following C statement from
;       function zysxi:
;
;               return  NORMAL_RETURN;
;
;       If the load module was invoked by EXIT(), the return path is
;       as follows:  back to ccaller, back to S$EXT following SYSXI call,
;       back to user program following EXIT() call.
;
;       Alternately, the user specified -w as a command line option, and
;       SYSBX called MAKEEXEC, which in turn called SYSXI.  The return path
;       should be:  back to ccaller, back to MAKEEXEC following SYSXI call,
;       back to SYSBX, back to MINIMAL code.  If we allowed this to happen,
;       then it would require that stacked return address to SYSBX still be
;       valid, which may not be true if some of the C programs have changed
;       size.  Instead, we clear the stack and execute the restart code that
;       simulates resumption just past the SYSBX call in the MINIMAL code.
;       We distinguish this case by noting the variable STAGE is 4.
;
        callc   startbrk,0              ; start control-C logic

        GETMIN  eax,STAGE               ; is this a -w call?
	cmp	eax,4
        je      re4	               ; yes, do a complete fudge

;
;       Jump back to cc1 with return value = NORMAL_RETURN
	mov	eax,-1
        jmp     cc1                     ; jump back

;       Here if -w produced load module.  simulate all the code that
;       would occur if we naively returned to sysbx.  Clear the stack and
;       go for it.
;
re4:	GETMIN	eax,STBAS
        mov     dword [compsp],eax	; empty the stack

;       Code that would be executed if we had returned to makeexec:
;
        SETMIN  GBCNT,0                 ; reset garbage collect count
        callc   zystm,0                 ; Fetch execution time to reg_ia
        mov     eax,dword [reg_ia]	; Set time into compiler
	SETMINR	TIMSX,eax

;       Code that would be executed if we returned to sysbx:
;
        push    outptr                  ; swcoup(outptr)
	callc	swcoup,4

;       Jump to Minimal code to restart a save file.

        MINIMAL RSTRT                   ; no return
