'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - Mode A: native DOUBLE escape-time iteration
'' ---------------------------------------------------------------------------
#include once "common.bi"

'' Smooth (continuous) iteration value for an orbit whose first point
'' outside the bailout radius R is z_n with |z_n|^2 = mag:
''   nu = n + 1 - log2( ln|z_n| / ln R )          (R = 256, ln R = 8 ln 2)
'' nu is continuous across the n -> n+1 boundary, which removes banding.
#define SMOOTH_NU(n, mag) (cdbl(n) + 1.0 - log2(log2(mag) * 0.0625))

'' Closed-form interior tests for the two largest components.  A safety
'' margin keeps boundary points out, so the answer is exact despite rounding.
function KnownInterior(byval cr as double, byval ci as double) as boolean
	dim y2 as double = ci * ci
	dim xq as double = cr - 0.25
	dim q as double = xq * xq + y2
	if q * (q + xq) < 0.25 * y2 - 1e-13 then return true      '' main cardioid
	dim x1 as double = cr + 1.0
	if x1 * x1 + y2 < 0.0625 - 1e-13 then return true          '' period-2 bulb
	return false
end function

'' Plain textbook escape count with the |z|^2 > 4 criterion: index n of the
'' first z_n outside radius 2, or -1 when no z_1..z_maxIter escapes.
function EscapeCountR2(byval cr as double, byval ci as double, byval maxIter as long) as long
	dim as double zr = 0, zi = 0, t
	for n as long = 1 to maxIter
		t = zr * zr - zi * zi + cr
		zi = 2 * zr * zi + ci
		zr = t
		if zr * zr + zi * zi > 4.0 then return n
	next
	return -1
end function

'' Smooth iteration value for c, or NU_INTERIOR / NU_KNOWN_IN.
'' The optional periodicity check (Brent) stops as soon as the orbit returns
'' to an exactly identical state: the double iteration is deterministic, so
'' such an orbit can never escape and the result equals the unchecked one.
function EscapeTimeDouble(byval cr as double, byval ci as double, byval maxIter as long, _
		byval periodicity as long) as double
	dim as double zr = 0, zi = 0, zr2 = 0, zi2 = 0
	dim as double sr = 0, si = 0
	dim as long n = 0, cnt = 0, chk = 8
	do
		zi = (zr + zr) * zi + ci
		zr = zr2 - zi2 + cr
		zr2 = zr * zr
		zi2 = zi * zi
		n += 1
		if zr2 + zi2 > BAILOUT_R2 then return SMOOTH_NU(n, zr2 + zi2)
		if n >= maxIter then return NU_INTERIOR
		if periodicity then
			if zr = sr andalso zi = si then return NU_KNOWN_IN
			cnt += 1
			if cnt = chk then
				cnt = 0
				if chk < 1048576 then chk += chk
				sr = zr
				si = zi
			end if
		end if
	loop
end function

function PixelDouble(byref job as RenderJob, byval px as long, byval py as long) as double
	dim cr as double = job.cxd + (px - (job.w - 1) * 0.5) * job.psd
	dim ci as double = job.cyd - (py - (job.h - 1) * 0.5) * job.psd
	if KnownInterior(cr, ci) then return NU_KNOWN_IN
	return EscapeTimeDouble(cr, ci, job.maxIter, job.periodicity)
end function
