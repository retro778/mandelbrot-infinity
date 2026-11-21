'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - minimal FreeBASIC binding for GNU MPFR 4.x
''
'' FreeBASIC ships no mpfr.bi, so the declarations below were transcribed by
'' hand from /usr/include/mpfr.h (MPFR 4.2.2, x86_64 Linux).  Only functions
'' that are real exported symbols of libmpfr are declared - several names in
'' mpfr.h (mpfr_cmp, mpfr_set ...) are also macros; where the macro maps onto
'' a differently named symbol the binding declares the underlying symbol.
''
'' Type mapping on x86_64 Linux (_MPFR_PREC_FORMAT = 3):
''   mpfr_prec_t = long  -> clong (64 bit)
''   mpfr_exp_t  = long  -> clong (64 bit)
''   mpfr_sign_t = int   -> long  (32 bit in FreeBASIC)
''   mpfr_rnd_t  = enum  -> long
'' ---------------------------------------------------------------------------
#pragma once
#include once "crt/long.bi"

#inclib "mpfr"
#inclib "gmp"

type mpfr_prec_t as clong
type mpfr_exp_t as clong

type __mpfr_struct
	_mpfr_prec as mpfr_prec_t
	_mpfr_sign as long
	_mpfr_exp as mpfr_exp_t
	_mpfr_d as any ptr
end type

type mpfr_t as __mpfr_struct
type mpfr_ptr as __mpfr_struct ptr

const MPFR_RNDN as long = 0   '' round to nearest
const MPFR_RNDZ as long = 1   '' round toward zero
const MPFR_RNDU as long = 2   '' round toward +Inf
const MPFR_RNDD as long = 3   '' round toward -Inf

extern "C"

declare function mpfr_get_version() as const zstring ptr
declare function mpfr_buildopt_tls_p() as long

declare sub mpfr_init2(byval x as mpfr_ptr, byval prec as mpfr_prec_t)
declare sub mpfr_clear(byval x as mpfr_ptr)
declare sub mpfr_set_prec(byval x as mpfr_ptr, byval prec as mpfr_prec_t)
declare function mpfr_get_prec(byval x as mpfr_ptr) as mpfr_prec_t
declare function mpfr_prec_round(byval x as mpfr_ptr, byval prec as mpfr_prec_t, byval rnd as long) as long
declare function mpfr_get_exp(byval x as mpfr_ptr) as mpfr_exp_t

declare function mpfr_set(byval rop as mpfr_ptr, byval op as mpfr_ptr, byval rnd as long) as long
declare function mpfr_set_d(byval rop as mpfr_ptr, byval op as double, byval rnd as long) as long
declare function mpfr_set_si(byval rop as mpfr_ptr, byval op as clong, byval rnd as long) as long
declare function mpfr_set_ui(byval rop as mpfr_ptr, byval op as culong, byval rnd as long) as long
declare function mpfr_set_str(byval rop as mpfr_ptr, byval s as const zstring ptr, byval nbase as long, byval rnd as long) as long
declare sub mpfr_set_zero(byval rop as mpfr_ptr, byval sign as long)
declare sub mpfr_swap(byval a as mpfr_ptr, byval b as mpfr_ptr)

declare function mpfr_get_d(byval op as mpfr_ptr, byval rnd as long) as double
declare function mpfr_get_d_2exp(byval e as clong ptr, byval op as mpfr_ptr, byval rnd as long) as double
declare function mpfr_get_si(byval op as mpfr_ptr, byval rnd as long) as clong
declare function mpfr_get_str(byval s as zstring ptr, byval e as mpfr_exp_t ptr, byval nbase as long, byval n as uinteger, byval op as mpfr_ptr, byval rnd as long) as zstring ptr
declare sub mpfr_free_str(byval s as zstring ptr)

declare function mpfr_add(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as mpfr_ptr, byval rnd as long) as long
declare function mpfr_sub(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as mpfr_ptr, byval rnd as long) as long
declare function mpfr_mul(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as mpfr_ptr, byval rnd as long) as long
declare function mpfr_div(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as mpfr_ptr, byval rnd as long) as long
declare function mpfr_sqr(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long
declare function mpfr_sqrt(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long
declare function mpfr_neg(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long
declare function mpfr_abs(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long

declare function mpfr_add_d(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as double, byval rnd as long) as long
declare function mpfr_sub_d(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as double, byval rnd as long) as long
declare function mpfr_mul_d(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as double, byval rnd as long) as long
declare function mpfr_div_d(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as double, byval rnd as long) as long
declare function mpfr_d_div(byval rop as mpfr_ptr, byval a as double, byval b as mpfr_ptr, byval rnd as long) as long
declare function mpfr_mul_si(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as clong, byval rnd as long) as long
declare function mpfr_mul_2ui(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as culong, byval rnd as long) as long
declare function mpfr_mul_2si(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as clong, byval rnd as long) as long
declare function mpfr_div_2ui(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval b as culong, byval rnd as long) as long

declare function mpfr_log2(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long
declare function mpfr_log10(byval rop as mpfr_ptr, byval a as mpfr_ptr, byval rnd as long) as long

'' mpfr_cmp(a,b) is a macro for mpfr_cmp3(a,b,1)
declare function mpfr_cmp3(byval a as mpfr_ptr, byval b as mpfr_ptr, byval s as long) as long
declare function mpfr_cmp_d(byval a as mpfr_ptr, byval b as double) as long
declare function mpfr_cmpabs(byval a as mpfr_ptr, byval b as mpfr_ptr) as long
declare function mpfr_sgn(byval a as mpfr_ptr) as long
declare function mpfr_zero_p(byval a as mpfr_ptr) as long
declare function mpfr_nan_p(byval a as mpfr_ptr) as long
declare function mpfr_inf_p(byval a as mpfr_ptr) as long
declare function mpfr_number_p(byval a as mpfr_ptr) as long

end extern

#define mpfr_cmp(a, b) mpfr_cmp3((a), (b), 1)
