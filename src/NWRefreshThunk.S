// arm64 C -> the pinned app's Swift instance method.
// Input: x0 = retained adapter, x1 = checked native refresh entry point.
// Swift refresh takes its object in x20 and a nil optional callback in x0/x1.
.text
.p2align 2
.globl _NWInvokeRefresh
_NWInvokeRefresh:
    stp x20, x30, [sp, #-16]!
    mov x16, x1
    mov x20, x0
    mov x0, xzr
    mov x1, xzr
    blr x16
    ldp x20, x30, [sp], #16
    ret
