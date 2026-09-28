.section __TEXT,__text,regular,pure_instructions
.globl _cave_start
.p2align 2
_cave_start:
    pacibsp
    stp x19, x20, [sp, #-32]!
    stp x21, x30, [sp, #16]
    sub sp, sp, #0x2000

    // Resolve this helper's physical path into buffer A.
    .long 0x94000000         // patched call: getpid
    mov x1, sp
    mov w2, #0x1000
    .long 0x94000000         // patched call: proc_pidpath
    mov w19, w0
    cmp w19, #33
    b.lo denied
    sub w21, w19, #33
    mov x0, sp
    add x0, x0, x21
    adr x1, helper_suffix
    mov w2, #33
    .long 0x94000000         // patched call: memcmp
    cbnz w0, denied

    // Resolve the parent path into buffer B.
    .long 0x94000000         // patched call: getppid
    add x1, sp, #0x1000
    mov w2, #0x1000
    .long 0x94000000         // patched call: proc_pidpath
    mov w20, w0
    add w0, w21, #45
    cmp w20, w0
    b.ne denied

    // Parent and helper must be in the same randomized RootHide root.
    mov x0, sp
    add x1, sp, #0x1000
    mov w2, w21
    .long 0x94000000         // patched call: memcmp
    cbnz w0, denied

    // The parent must be exactly the expected app executable (legacy path retained).
    add x0, sp, #0x1000
    add x0, x0, x21
    adr x1, app_suffix
    mov w2, #45
    .long 0x94000000         // patched call: memcmp
    cbnz w0, denied
    mov w0, #0
    b finished

denied:
    mov w0, #1
finished:
    add sp, sp, #0x2000
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #32
    retab

helper_suffix:
    .ascii "/usr/libexec/harpy-reloaded/aegis"
app_suffix:
    .ascii "/Applications/HarpyReloaded.app/HarpyReloaded"

