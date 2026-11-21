'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - Mode B: arbitrary precision reference renderer
''
'' Every pixel is iterated with MPFR at the job precision.  This is the
'' slow, straightforward renderer that all optimised paths are checked
'' against.  Each worker thread owns one MpfrCtx so no MPFR variable is
'' allocated inside the pixel loop.
'' ---------------------------------------------------------------------------
#include once "common.bi"

type MpfrCtx
	inited as long
	prec as long
	cr as mpfr_t
	ci as mpfr_t
	zr as mpfr_t
	zi as mpfr_t
	zr2 as mpfr_t
	zi2 as mpfr_t
	t as mpfr_t
end type

sub MpfrCtx_Init(byref c as MpfrCtx, byval prec as long)
	if c.inited then
		if c.prec = prec then exit sub
		mpfr_clear(@c.cr) : mpfr_clear(@c.ci) : mpfr_clear(@c.zr) : mpfr_clear(@c.zi)
		mpfr_clear(@c.zr2) : mpfr_clear(@c.zi2) : mpfr_clear(@c.t)
	end if
	mpfr_init2(@c.cr, prec) : mpfr_init2(@c.ci, prec)
	mpfr_init2(@c.zr, prec) : mpfr_init2(@c.zi, prec)
	mpfr_init2(@c.zr2, prec) : mpfr_init2(@c.zi2, prec)
	mpfr_init2(@c.t, prec)
	c.prec = prec
	c.inited = 1
end sub

sub MpfrCtx_Clear(byref c as MpfrCtx)
	if c.inited = 0 then exit sub
	mpfr_clear(@c.cr) : mpfr_clear(@c.ci) : mpfr_clear(@c.zr) : mpfr_clear(@c.zi)
	mpfr_clear(@c.zr2) : mpfr_clear(@c.zi2) : mpfr_clear(@c.t)
	c.inited = 0
end sub

'' Iterate z -> z^2 + c for the c stored in ctx.cr / ctx.ci.
'' Returns the smooth iteration value, NU_INTERIOR, or NU_PENDING when the
'' cancel flag was raised.
function IterateMpfr(byref c as MpfrCtx, byval maxIter as long, byval cancel as long ptr) as double
	dim n as long = 0
	dim mag as double
	mpfr_set_zero(@c.zr, 1)
	mpfr_set_zero(@c.zi, 1)
	mpfr_set_zero(@c.zr2, 1)
	mpfr_set_zero(@c.zi2, 1)
	do
		mpfr_mul(@c.zi, @c.zr, @c.zi, MPFR_RNDN)
		mpfr_mul_2ui(@c.zi, @c.zi, 1, MPFR_RNDN)
		mpfr_add(@c.zi, @c.zi, @c.ci, MPFR_RNDN)
		mpfr_sub(@c.zr, @c.zr2, @c.zi2, MPFR_RNDN)
		mpfr_add(@c.zr, @c.zr, @c.cr, MPFR_RNDN)
		mpfr_sqr(@c.zr2, @c.zr, MPFR_RNDN)
		mpfr_sqr(@c.zi2, @c.zi, MPFR_RNDN)
		n += 1
		mag = mpfr_get_d(@c.zr2, MPFR_RNDN) + mpfr_get_d(@c.zi2, MPFR_RNDN)
		if mag > BAILOUT_R2 then return SMOOTH_NU(n, mag)
		if n >= maxIter then return NU_INTERIOR
		if (n and 255) = 0 then
			if cancel andalso *cancel then return NU_PENDING
		end if
	loop
end function

'' c = centre + pixel offset * pixel size, all in MPFR at the job precision.
sub PixelCoordMpfr(byref job as RenderJob, byref c as MpfrCtx, byval px as double, byval py as double)
	mpfr_mul_d(@c.t, @job.ps, px - (job.w - 1) * 0.5, MPFR_RNDN)
	mpfr_add(@c.cr, @job.view.cx, @c.t, MPFR_RNDN)
	mpfr_mul_d(@c.t, @job.ps, py - (job.h - 1) * 0.5, MPFR_RNDN)
	mpfr_sub(@c.ci, @job.view.cy, @c.t, MPFR_RNDN)
end sub

function PixelMpfr(byref job as RenderJob, byref c as MpfrCtx, byval px as long, byval py as long) as double
	PixelCoordMpfr(job, c, px, py)
	if job.zbits <= 40 then
		if KnownInterior(mpfr_get_d(@c.cr, MPFR_RNDN), mpfr_get_d(@c.ci, MPFR_RNDN)) then return NU_KNOWN_IN
	end if
	return IterateMpfr(c, job.maxIter, @job.cancel)
end function
