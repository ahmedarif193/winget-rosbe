
#pragma once

struct _SEH$$_EXCEPTION_RECORD
{
    unsigned long ExceptionCode;
    unsigned long ExceptionFlags;
    struct _EXCEPTION_RECORD *ExceptionRecord;
    void* ExceptionAddress;
    unsigned long NumberParameters;
    unsigned long long ExceptionInformation[15];
};

struct _SEH$$_EXCEPTION_POINTERS
{
    struct _SEH$$_EXCEPTION_RECORD *ExceptionRecord;
    struct _CONTEXT *ContextRecord;
};

#define STRINGIFY(a) #a
#define _SEH2_GLOBAL_FILTER_EPILOGUE_OFFSET "76"
#define EMIT_PRAGMA_(params) \
    _Pragma( STRINGIFY(params) )
#define EMIT_PRAGMA(type,line) \
    EMIT_PRAGMA_(REACTOS seh(type,line))

#define _SEH3$_EMIT_DEFS_AND_PRAGMA__(Line, Type)                                   \
    /* Emit assembler constants with line number to be individual */                \
    __asm__ __volatile__ goto ("\n"                                                 \
        "\t__seh2$$begin_try__" #Line "=%l0\n" /* Begin of tried code */            \
        "\t__seh2$$end_try__" #Line "=%l1 + 1\n" /* End of tried code */            \
        "\t# Keep filter block %l2\n"                                              \
        "\t# Keep handler block %l3\n"                                             \
            : /* No output */                                                       \
            : /* No input */                                                        \
            : /* No clobber */                                                      \
            : __seh2$$begin_try__,                                                  \
              __seh2$$end_try__,                                                    \
              __seh2$$filter_entry__,                                               \
              __seh2$$handler_entry__);                                             \
    /* Call our home-made pragma */                                                 \
    EMIT_PRAGMA(Type,Line)

#define _SEH3$_EMIT_DEFS_AND_PRAGMA_(Line, Type) _SEH3$_EMIT_DEFS_AND_PRAGMA__(Line, Type)
#define _SEH3$_EMIT_DEFS_AND_PRAGMA(Type) _SEH3$_EMIT_DEFS_AND_PRAGMA_(__LINE__, Type)

/*
 * Put the externally referenced filter symbol inside the asm statement.  A C
 * label before an extended asm is not a safe Windows funclet entry point: GCC
 * may schedule register spills between that label and the asm, before the
 * trampoline has restored the guarded function's frame pointer.
 */
#define _SEH3$_EMIT_FILTER_TRAMPOLINE__(Line, Target)                              \
    __asm__ __volatile__ goto(                                                     \
        "\t__seh2$$filter__" #Line ":\n"                                           \
        "\tleaq %l0(%%rip), %%r8\n"                                                \
        "\tjmp __seh2_global_filter_func\n"                                        \
        : /* No output */                                                          \
        : /* No input */                                                           \
        : "%r8"                                                                   \
        : Target)

#define _SEH3$_EMIT_FILTER_TRAMPOLINE_(Line, Target) \
    _SEH3$_EMIT_FILTER_TRAMPOLINE__(Line, Target)
#define _SEH3$_EMIT_FILTER_TRAMPOLINE(Target) \
    _SEH3$_EMIT_FILTER_TRAMPOLINE_(__LINE__, Target)

/*
 * Enter an __except body through an asm-goto edge which clobbers every
 * register except rsp/rbp.  Although RtlUnwindEx restores the nonvolatile
 * registers, their values belong to the interrupted path, not necessarily to
 * the compiler edge that contains this externally entered continuation.
 */
#define _SEH3$_EMIT_HANDLER_TRAMPOLINE__(Line, Target)                             \
    __asm__ __volatile__ goto(                                                     \
        "\t__seh2$$begin_except__" #Line ":\n"                                    \
        "\tjmp %l0\n"                                                             \
        : /* No output */                                                          \
        : /* No input */                                                           \
        : "%rax", "%rbx", "%rcx", "%rdx", "%rdi", "%rsi",                    \
          "%r8", "%r9", "%r10", "%r11", "%r12", "%r13", "%r14", "%r15",    \
          "memory", "cc"                                                         \
        : Target)

#define _SEH3$_EMIT_HANDLER_TRAMPOLINE_(Line, Target) \
    _SEH3$_EMIT_HANDLER_TRAMPOLINE__(Line, Target)
#define _SEH3$_EMIT_HANDLER_TRAMPOLINE(Target) \
    _SEH3$_EMIT_HANDLER_TRAMPOLINE_(__LINE__, Target)

#define _SEH2_TRY                                                                   \
{                                                                                   \
    __label__ __seh2$$filter_entry__;                                               \
    __label__ __seh2$$handler_entry__;                                              \
    __label__ __seh2$$handler_body__;                                               \
    __label__ __seh2$$begin_try__;                                                  \
    __label__ __seh2$$end_try__;                                                    \
    struct __seh2$$scope_context__                                                  \
    {                                                                               \
        int abnormal_termination;                                                   \
    };                                                                              \
    auto void __seh2$$cleanup_action__(                                             \
        struct __seh2$$scope_context__ *__seh2$$context__);                         \
    auto inline void __seh2$$scope_cleanup__(                                       \
        struct __seh2$$scope_context__ *__seh2$$context__)                          \
        __attribute__((always_inline));                                             \
    struct __seh2$$scope_context__ __seh2$$scope_context__                          \
        __attribute__((cleanup(__seh2$$scope_cleanup__))) = { 0 };                  \
    {                                                                               \
    __label__ __seh2$$leave_scope__;                                                \
    /*                                                                              \
     * We close the current SEH block for this function and install our own.        \
     * At this point GCC emitted its prologue, and if it saves more                 \
     * registers, the relevant instruction will be valid for our scope as well.     \
     * We also count the number of try blocks at assembly level                     \
     * to properly set the handler data when we're done.                            \
     */                                                                             \
__seh2$$begin_try__:                                                                \
    {                                                                               \
        __asm__ __volatile__ goto ("" : : : : __seh2$$leave_scope__);

#define _SEH2_EXCEPT(...) _SEH2_EXCEPT_(__COUNTER__, __VA_ARGS__)
#define _SEH2_EXCEPT_(Id, ...) _SEH2_EXCEPT__(Id, __VA_ARGS__)
#define _SEH2_EXCEPT__(Id, ...)                                                                 \
__seh2$$leave_scope__: __MINGW_ATTRIB_UNUSED;                                                   \
        __seh2$$scope_context__.abnormal_termination = 0;                                       \
    }                                                                                           \
    }                                                                                           \
    goto __seh2$$end_try__;                                                                     \
    volatile long __MINGW_ATTRIB_UNUSED __seh2$$exception_code__;                              \
    struct _SEH$$_EXCEPTION_POINTERS* __seh2$$exception_ptr__;                                 \
    auto long __seh2$$filter_action__(                                                         \
        struct _SEH$$_EXCEPTION_POINTERS *__seh2$$incoming_exception_ptr__)                    \
        __attribute__((noinline, noipa));                                                      \
    long __seh2$$filter_action__(                                                              \
        struct _SEH$$_EXCEPTION_POINTERS *__seh2$$incoming_exception_ptr__)                    \
    {                                                                                          \
        __seh2$$exception_ptr__ = __seh2$$incoming_exception_ptr__;                            \
        __seh2$$exception_code__ = __seh2$$exception_ptr__->ExceptionRecord->ExceptionCode;   \
        unsigned long __seh2$$original_exception_flags__ =                                     \
            __seh2$$exception_ptr__->ExceptionRecord->ExceptionFlags;                          \
        volatile int *__seh2$$filter_depth__ =                                                \
            &__seh2$$scope_context__.abnormal_termination;                                    \
        if (*__seh2$$filter_depth__ > 0)                                                     \
            __seh2$$exception_ptr__->ExceptionRecord->ExceptionFlags |= 0x10;                  \
        ++*__seh2$$filter_depth__;                                                             \
        long __seh2$$filter_result__ = ((__VA_ARGS__));                                        \
        __seh2$$exception_ptr__->ExceptionRecord->ExceptionFlags =                             \
            __seh2$$original_exception_flags__;                                                \
        --*__seh2$$filter_depth__;                                                             \
        return __seh2$$filter_result__;                                                        \
    }                                                                                          \
    if (0)                                                                                      \
    {                                                                                           \
        /* Add our handlers to the list */                                                      \
        /* Jump to the global filter. Tell it where the filter funclet lies */                  \
        __label__ __seh2$$filter_funclet__;                                                     \
        __seh2$$filter_entry__: __MINGW_ATTRIB_UNUSED;                                         \
        _SEH3$_EMIT_FILTER_TRAMPOLINE_(Id, __seh2$$filter_funclet__);                          \
        /* Actually declare our filter funclet */                                               \
        __seh2$$filter_funclet__:                                                               \
        struct _SEH$$_EXCEPTION_POINTERS *__seh2$$incoming_exception_ptr__;                    \
        /* At this point, the compiler can't count on any register being valid */               \
        __asm__ __volatile__(""                                                                 \
            : "=c"(__seh2$$incoming_exception_ptr__) /* First filter argument */               \
            : /* No input */                                                                    \
            : /* Everything */                                                                  \
            "%rax", "%rbx", "%rdx", "%rdi", "%rsi",                                      \
            "%r8", "%r9", "%r10", "%r11", "%r12", "%r13", "%r14", "%r15");          \
        /* Run the user expression in a real function with its own unwind info. */               \
        long __seh2$$filter_funclet_ret =                                                       \
            __seh2$$filter_action__(__seh2$$incoming_exception_ptr__);                          \
        /* Go back to the global filter function with result in eax */                          \
        /* Use the COMDAT section's base symbol plus the checked epilogue offset.               \
         * GNU ld double-applies a non-zero COFF symbol value to this cross-section             \
         * REL32 relocation, so referencing the epilogue symbol directly is incorrect. */      \
        __asm__ __volatile__("jmp __seh2_global_filter_func + "                                \
                             _SEH2_GLOBAL_FILTER_EPILOGUE_OFFSET                                \
            : /* No output */                                                                   \
            : "a"(__seh2$$filter_funclet_ret)                                                   \
            : "memory");                                                                        \
    }                                                                                           \
__seh2$$end_try__:(void)0;                                                                      \
    /* Keep the filter adapter in-range so nested filter exceptions re-enter                   \
     * this scope with EXCEPTION_NESTED_CALL, as native x64 SEH does. */                         \
    _SEH3$_EMIT_DEFS_AND_PRAGMA_(Id, __seh$$except);                                            \
    /* Normal control skips this statement; __C_specific_handler jumps to its label. */         \
    enum                                                                                        \
    {                                                                                           \
        __seh2$$abnormal_termination__ = 0                                                      \
    };                                                                                          \
    if (0)                                                                                      \
        __seh2$$handler_entry__:                                                                \
            _SEH3$_EMIT_HANDLER_TRAMPOLINE_(Id, __seh2$$handler_body__);                       \
    inline void __seh2$$scope_cleanup__(                                                       \
        struct __seh2$$scope_context__ *__seh2$$context__)                                     \
    {                                                                                          \
        (void)__seh2$$context__;                                                               \
    }                                                                                          \
    auto inline void __seh2$$cleanup_action__(                                                  \
        struct __seh2$$scope_context__ *__seh2$$context__)                                      \
        __attribute__((always_inline));                                                         \
    inline void __seh2$$cleanup_action__(                                                       \
        struct __seh2$$scope_context__ *__seh2$$context__)                                      \
    {                                                                                           \
        (void)__seh2$$context__;                                                                \
    }                                                                                           \
    if (0)                                                                                      \
        __seh2$$handler_body__: if (1)

#define _SEH2_FINALLY _SEH2_FINALLY_(__COUNTER__)
#define _SEH2_FINALLY_(Id) _SEH2_FINALLY__(Id)
#define _SEH2_FINALLY__(Id)                                                                \
__seh2$$leave_scope__: __MINGW_ATTRIB_UNUSED;                                               \
        __seh2$$scope_context__.abnormal_termination = 0;                                   \
    }                                                                                       \
    }                                                                                       \
__seh2$$end_try__:                                                                          \
    /* Call our home-made pragma */                                                         \
    _SEH3$_EMIT_DEFS_AND_PRAGMA_(Id, __seh$$finally);                                       \
    if (0)                                                                                  \
    {                                                                                       \
        __label__ __seh2$$begin_finally__;                                                  \
        /* Jump to the global trampoline. Tell it where the unwind code really lies. */      \
        __seh2$$filter_entry__: __MINGW_ATTRIB_UNUSED;                                      \
        __seh2$$handler_entry__: __MINGW_ATTRIB_UNUSED;                                     \
        _SEH3$_EMIT_FILTER_TRAMPOLINE_(Id, __seh2$$begin_finally__);                        \
        __seh2$$begin_finally__:                                                            \
        __asm__ __volatile__(""                                                             \
            : "=c" (__seh2$$scope_context__.abnormal_termination)                           \
            : /* No input */                                                                \
            : /* Everything - We came from __C_specific_handler here */                     \
            "%rax", "%rbx", "%rdx", "%rdi", "%rsi",                                  \
            "%r8", "%r9", "%r10", "%r11", "%r12", "%r13", "%r14", "%r15");       \
        __seh2$$cleanup_action__(&__seh2$$scope_context__);                                  \
        /* The asm is a real non-fallthrough edge.  The memory clobber keeps the              \
         * termination action ahead of it without emitting a barrier instruction. */         \
        __asm__ __volatile__("jmp __seh2_global_filter_func + "                             \
                             _SEH2_GLOBAL_FILTER_EPILOGUE_OFFSET                             \
            : /* No output */                                                                 \
            : /* No input */                                                                  \
            : "memory");                                                                      \
    }                                                                                       \
    inline void __seh2$$scope_cleanup__(                                                   \
        struct __seh2$$scope_context__ *__seh2$$context__)                                 \
    {                                                                                      \
        __seh2$$cleanup_action__(__seh2$$context__);                                      \
    }                                                                                      \
    auto void __seh2$$cleanup_action__(                                                    \
        struct __seh2$$scope_context__ *__seh2$$context__)                                 \
        __attribute__((noinline, noipa));                                                  \
    void __seh2$$cleanup_action__(                                                          \
        struct __seh2$$scope_context__ *__seh2$$context__)

#define _SEH2_END                                                                   \
}

#define _SEH2_GetExceptionInformation() ((struct _EXCEPTION_POINTERS*)__seh2$$exception_ptr__)
#define _SEH2_GetExceptionCode() __seh2$$exception_code__
#define _SEH2_AbnormalTermination() (__seh2$$context__->abnormal_termination & 1)
#define _SEH2_LEAVE goto __seh2$$leave_scope__
#define _SEH2_YIELD(__stmt) __stmt
#define _SEH2_VOLATILE volatile

#ifndef __cplusplus
#undef __try // undef from GCC's stl
#define __try _SEH2_TRY
#define __except _SEH2_EXCEPT
#define __finally _SEH2_FINALLY
#define __endtry _SEH2_END
#define __leave goto __seh2$$leave_scope__
#endif
#define _exception_info() ((struct _EXCEPTION_POINTERS*)__seh2$$exception_ptr__)
#define _exception_code() __seh2$$exception_code__
#define _abnormal_termination() (__seh2$$context__->abnormal_termination & 1)
