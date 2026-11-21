'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - perturbation renderer
''
'' One reference orbit Z_n is computed at the view centre with MPFR and
'' stored as doubles.  Every pixel then iterates only its difference
'' delta_n = z_n - Z_n in hardware floating point:
''
''     delta_(n+1) = 2 Z_n delta_n + delta_n^2 + delta_c
''
'' Glitch handling uses rebasing: whenever |Z_m + delta| < |delta| (the
'' pixel orbit is closer to 0 than to the reference) or the reference orbit
'' ends, delta is replaced by the full value z and the reference index
'' restarts at 0.  That is exact (Z_0 = 0) and removes the cancellation that
'' causes perturbation glitches, so no second reference is required.
''
'' Zooms beyond the double exponent range (about 1e-300) use a scaled
'' representation delta = w * 2^E with w kept near 1 ("extended exponent").
'' While delta is that small the orbit cannot escape or rebase unless the
'' reference itself is tiny; the few reference entries below 1e-60 are kept
'' with their own exponent and go through a slow, fully general step.
''
'' Series approximation (optional): delta_n is a polynomial in delta_c.  Its
'' first three coefficients are iterated along the reference and used to
'' skip the first iterations for all pixels.  The skip length is limited by
'' comparing the series against directly iterated probe orbits on the
'' circle that encloses the image (the truncation error is analytic in
'' delta_c, so its maximum over the disc lies on that circle).
'' ---------------------------------------------------------------------------
#include once "common.bi"

const TINY_Z as double = 1e-60        '' reference entries below this are "tiny"
const SA_PROBES = 16
const SA_TOL as double = 1e-12

sub Ref_Free(byref r as RefOrbit)
	if r.zr then deallocate(r.zr) : r.zr = 0
	if r.zi then deallocate(r.zi) : r.zi = 0
	if r.tinyIdx then deallocate(r.tinyIdx) : r.tinyIdx = 0
	if r.tinyR then deallocate(r.tinyR) : r.tinyR = 0
	if r.tinyI then deallocate(r.tinyI) : r.tinyI = 0
	if r.tinyE then deallocate(r.tinyE) : r.tinyE = 0
	r.cap = 0 : r.tinyCap = 0 : r.n = 0 : r.nTiny = 0
	if r.inited then
		mpfr_clear(@r.mcr) : mpfr_clear(@r.mci) : mpfr_clear(@r.mzr)
		mpfr_clear(@r.mzi) : mpfr_clear(@r.t1) : mpfr_clear(@r.t2)
		r.inited = 0
	end if
end sub

private function Ref_AddTiny(byref r as RefOrbit, byval idx as long, byval mr as double, _
		byval er as long, byval mi as double, byval ei as long) as boolean
	if r.nTiny >= r.tinyCap then
		dim nc as long = r.tinyCap * 2 + 64
		dim p1 as any ptr = reallocate(r.tinyIdx, nc * sizeof(long))
		if p1 = 0 then return false
		r.tinyIdx = p1
		p1 = reallocate(r.tinyR, nc * sizeof(double))
		if p1 = 0 then return false
		r.tinyR = p1
		p1 = reallocate(r.tinyI, nc * sizeof(double))
		if p1 = 0 then return false
		r.tinyI = p1
		p1 = reallocate(r.tinyE, nc * sizeof(long))
		if p1 = 0 then return false
		r.tinyE = p1
		r.tinyCap = nc
	end if
	dim e as long
	if mr = 0 andalso mi = 0 then
		e = 0
	elseif mr = 0 then
		e = ei
	elseif mi = 0 then
		e = er
	else
		e = iif(er > ei, er, ei)
	end if
	dim sr as long = er - e, si as long = ei - e
	if sr < -1200 then sr = -1200
	if si < -1200 then si = -1200
	r.tinyIdx[r.nTiny] = idx
	r.tinyR[r.nTiny] = iif(mr = 0, 0.0, ldexp(mr, sr))
	r.tinyI[r.nTiny] = iif(mi = 0, 0.0, ldexp(mi, si))
	r.tinyE[r.nTiny] = e
	r.nTiny += 1
	return true
end function

'' Compute (or extend) the reference orbit of c = (cx, cy) up to maxIter.
'' Returns false when cancelled or out of memory (errMsg set in that case).
function Ref_Compute(byref r as RefOrbit, byval cx as mpfr_ptr, byval cy as mpfr_ptr, _
		byval prec as long, byval maxIter as long, byval cancel as long ptr, _
		byval progress as long ptr, byref errMsg as string) as boolean
	dim cont as boolean = false
	if r.inited andalso r.prec = prec andalso r.n >= 1 then
		'' same centre at the same precision -> the orbit can be extended
		mpfr_set(@r.t1, cx, MPFR_RNDN)
		mpfr_set(@r.t2, cy, MPFR_RNDN)
		if mpfr_cmp(@r.t1, @r.mcr) = 0 andalso mpfr_cmp(@r.t2, @r.mci) = 0 then cont = true
	end if
	'' a longer stored orbit is simply used as is (pixels stop at maxIter)
	if cont then
		if r.escaped <> 0 orelse r.n >= maxIter then return true
	end if
	if cont = false then
		if r.inited then
			mpfr_clear(@r.mcr) : mpfr_clear(@r.mci) : mpfr_clear(@r.mzr)
			mpfr_clear(@r.mzi) : mpfr_clear(@r.t1) : mpfr_clear(@r.t2)
		end if
		mpfr_init2(@r.mcr, prec) : mpfr_init2(@r.mci, prec)
		mpfr_init2(@r.mzr, prec) : mpfr_init2(@r.mzi, prec)
		mpfr_init2(@r.t1, prec) : mpfr_init2(@r.t2, prec)
		r.inited = 1
		r.prec = prec
		mpfr_set(@r.mcr, cx, MPFR_RNDN)
		mpfr_set(@r.mci, cy, MPFR_RNDN)
		mpfr_set_zero(@r.mzr, 1)
		mpfr_set_zero(@r.mzi, 1)
		r.n = 0
		r.nTiny = 0
		r.escaped = 0
	end if
	r.saSkip = 0
	if maxIter + 2 > r.cap then
		dim nc as long = maxIter + 2
		dim p1 as any ptr = reallocate(r.zr, nc * sizeof(double))
		if p1 then r.zr = p1
		dim p2 as any ptr = reallocate(r.zi, nc * sizeof(double))
		if p2 then r.zi = p2
		if p1 = 0 orelse p2 = 0 then
			errMsg = "out of memory for the reference orbit (" & maxIter & " iterations)"
			r.inited = 0
			mpfr_clear(@r.mcr) : mpfr_clear(@r.mci) : mpfr_clear(@r.mzr)
			mpfr_clear(@r.mzi) : mpfr_clear(@r.t1) : mpfr_clear(@r.t2)
			return false
		end if
		r.cap = nc
	end if
	if r.n = 0 then
		r.zr[0] = 0 : r.zi[0] = 0
		if Ref_AddTiny(r, 0, 0, 0, 0, 0) = false then errMsg = "out of memory" : return false
	end if
	dim as double dr, di
	for k as long = r.n + 1 to maxIter
		mpfr_sqr(@r.t1, @r.mzr, MPFR_RNDN)
		mpfr_sqr(@r.t2, @r.mzi, MPFR_RNDN)
		mpfr_mul(@r.mzi, @r.mzr, @r.mzi, MPFR_RNDN)
		mpfr_mul_2ui(@r.mzi, @r.mzi, 1, MPFR_RNDN)
		mpfr_add(@r.mzi, @r.mzi, @r.mci, MPFR_RNDN)
		mpfr_sub(@r.mzr, @r.t1, @r.t2, MPFR_RNDN)
		mpfr_add(@r.mzr, @r.mzr, @r.mcr, MPFR_RNDN)
		dr = mpfr_get_d(@r.mzr, MPFR_RNDN)
		di = mpfr_get_d(@r.mzi, MPFR_RNDN)
		r.zr[k] = dr
		r.zi[k] = di
		r.n = k
		if abs(dr) < TINY_Z andalso abs(di) < TINY_Z then
			dim as clong er, ei
			dim mr as double = mpfr_get_d_2exp(@er, @r.mzr, MPFR_RNDN)
			dim mi as double = mpfr_get_d_2exp(@ei, @r.mzi, MPFR_RNDN)
			if er < -2000000000 then er = -2000000000
			if ei < -2000000000 then ei = -2000000000
			if Ref_AddTiny(r, k, mr, er, mi, ei) = false then errMsg = "out of memory" : return false
		end if
		if dr * dr + di * di > BAILOUT_R2 then
			r.escaped = 1
			exit for
		end if
		if (k and 255) = 0 then
			if progress then *progress = k
			if cancel andalso *cancel then
				'' keep the partial orbit: it stays extendable
				return false
			end if
		end if
	next
	return true
end function

'' ---- series approximation ------------------------------------------------------

'' Determine how many iterations can be skipped for an image whose enclosing
'' circle has radius R = Rm * 2^Rexp in the complex plane.
''
'' Everything is kept in units of R so nothing under- or overflows:
''     delta_n / R = a t + b t^2 + c t^3,   t = delta_c / R,  |t| <= 1
''     a' = 2 Z a + 1,   b' = 2 Z b + R a^2,   c' = 2 Z c + 2 R a b
'' When R itself is below the double range the quadratic terms vanish
'' identically; the skip is then limited to the stretch where delta^2 is
'' below double rounding of 2 Z delta, where the linear term is exact.
sub Ref_SeriesSetup(byref r as RefOrbit, byval Rm as double, byval Rexp as long)
	r.saSkip = 0
	r.saR = Rm
	r.saE = Rexp
	if r.n < 32 orelse Rm <= 0 then exit sub
	dim Rd as double = 0
	if Rexp > -960 then Rd = ldexp(Rm, Rexp)
	dim as double ar = 1, ai = 0, br = 0, bi = 0, cr = 0, ci = 0
	dim as double pr(0 to SA_PROBES - 1), pi_(0 to SA_PROBES - 1)
	dim as double tr(0 to SA_PROBES - 1), ti(0 to SA_PROBES - 1)
	for j as long = 0 to SA_PROBES - 1
		dim th as double = (j + 0.37) * 6.283185307179586 / SA_PROBES
		tr(j) = cos(th) : ti(j) = sin(th)
		pr(j) = tr(j) : pi_(j) = ti(j)
	next
	dim best as long = 0
	for n as long = 1 to r.n - 2
		'' coefficients and probes describe index n: is the series still good?
		dim ok as boolean = true
		dim maxd2 as double = 0
		for j as long = 0 to SA_PROBES - 1
			'' s = t*(a + t*(b + t*c))
			dim as double xr = br + tr(j) * cr - ti(j) * ci, xi = bi + tr(j) * ci + ti(j) * cr
			dim as double yr = ar + tr(j) * xr - ti(j) * xi, yi = ai + tr(j) * xi + ti(j) * xr
			dim as double sr = tr(j) * yr - ti(j) * yi, si = tr(j) * yi + ti(j) * yr
			dim as double d2 = pr(j) * pr(j) + pi_(j) * pi_(j)
			dim as double e2 = (sr - pr(j)) * (sr - pr(j)) + (si - pi_(j)) * (si - pi_(j))
			if not (e2 <= SA_TOL * SA_TOL * d2) then ok = false : exit for
			if d2 > maxd2 then maxd2 = d2
		next
		if ok = false then exit for
		if not (maxd2 < 1e280) then exit for
		dim as double zr = r.zr[n], zi = r.zi[n]
		dim as double zmag2 = zr * zr + zi * zi
		if Rd > 0 then
			'' stay well away from any possible rebase: |Z_n| > 1000 |delta|
			dim dabs as double = sqr(maxd2) * Rd
			if not (zmag2 > 1e6 * dabs * dabs) then exit for
		else
			'' linear series only: need |delta| < 1e-18 |Z_n|
			dim dabs as double = ldexp(sqr(maxd2) * Rm, iif(Rexp < -1200, -1200, Rexp))
			if not (zmag2 > 1e36 * dabs * dabs) then exit for
			if not (zmag2 > 1e-100) then exit for
		end if
		best = n
		r.cfAr = ar : r.cfAi = ai : r.cfBr = br : r.cfBi = bi : r.cfCr = cr : r.cfCi = ci
		'' advance to n + 1
		dim as double z2r = zr + zr, z2i = zi + zi
		dim as double aRr = ar * Rd, aRi = ai * Rd
		dim as double ncr = z2r * cr - z2i * ci + 2 * (aRr * br - aRi * bi)
		dim as double nci = z2r * ci + z2i * cr + 2 * (aRr * bi + aRi * br)
		dim as double nbr = z2r * br - z2i * bi + ar * aRr - ai * aRi
		dim as double nbi = z2r * bi + z2i * br + ar * aRi + ai * aRr
		dim as double nar = z2r * ar - z2i * ai + 1.0
		dim as double nai = z2r * ai + z2i * ar
		ar = nar : ai = nai : br = nbr : bi = nbi : cr = ncr : ci = nci
		for j as long = 0 to SA_PROBES - 1
			dim as double pRr = pr(j) * Rd, pRi = pi_(j) * Rd
			dim as double qr = z2r * pr(j) - z2i * pi_(j) + pr(j) * pRr - pi_(j) * pRi + tr(j)
			dim as double qi = z2r * pi_(j) + z2i * pr(j) + pr(j) * pRi + pi_(j) * pRr + ti(j)
			pr(j) = qr : pi_(j) = qi
		next
	next
	if best >= 8 then r.saSkip = best
end sub

'' ---- per pixel iteration ---------------------------------------------------------

private function Ref_NextTiny(byref r as RefOrbit, byval m as long) as long
	'' index into the tiny list of the first entry with tinyIdx >= m
	dim as long lo = 0, hi = r.nTiny
	while lo < hi
		dim md as long = (lo + hi) shr 1
		if r.tinyIdx[md] < m then lo = md + 1 else hi = md
	wend
	return lo
end function

'' ox, oy: pixel offset from the image centre (oy positive = up).
'' Returns the smooth iteration value or NU_INTERIOR.
function PerturbIterate(byref job as RenderJob, byval ox as double, byval oy as double, _
		byval useSA as long) as double
	dim byref r as RefOrbit = job.ref
	dim maxIter as long = job.maxIter
	dim refLen as long = r.n
	dim Zr as double ptr = r.zr, Zi as double ptr = r.zi
	dim as double ur = ox * job.psMant, ui = oy * job.psMant   '' delta_c = u * 2^Ec
	dim Ec as long = job.psExp
	dim as double mag, dmag, tr, ti, zr_, zi_

	if ur = 0 andalso ui = 0 then
		'' the pixel is the reference point itself
		if r.escaped andalso refLen <= maxIter then
			mag = Zr[refLen] * Zr[refLen] + Zi[refLen] * Zi[refLen]
			return SMOOTH_NU(refLen, mag)
		end if
		return NU_INTERIOR
	end if

	'' delta_c as a double: exact when representable; when it underflows it is
	'' below 1e-28 of every term it is added to in double mode (|delta| > 1e-140)
	dim as double dcr = 0, dci = 0
	if Ec > -1070 then dcr = ldexp(ur, Ec) : dci = ldexp(ui, Ec)

	dim as double wr, wi, dr, di, S, K
	dim as long E, n, m, tix, nextTiny, ex

	if useSA andalso r.saSkip > 0 then
		dim sc as double = 2.0 / hypot(cdbl(job.w), cdbl(job.h))
		dim as double t1r = ox * sc, t1i = oy * sc
		dim as double xr = r.cfBr + t1r * r.cfCr - t1i * r.cfCi, xi = r.cfBi + t1r * r.cfCi + t1i * r.cfCr
		dim as double yr = r.cfAr + t1r * xr - t1i * xi, yi = r.cfAi + t1r * xi + t1i * xr
		wr = (t1r * yr - t1i * yi) * r.saR
		wi = (t1r * yi + t1i * yr) * r.saR
		E = r.saE
		n = r.saSkip
		m = n
	else
		wr = ur : wi = ui : E = Ec
		n = 1 : m = 1
	end if

ScaledEnter:
	'' wr, wi, E hold delta after the step that produced index m; the
	'' post-step checks for index m have not been made yet.
	scope
		dim mx as double = iif(abs(wr) > abs(wi), abs(wr), abs(wi))
		if mx > 0 then
			frexp(mx, @ex)
			wr = ldexp(wr, -ex)
			wi = ldexp(wi, -ex)
			E += ex
			if E > -430 then
				dr = ldexp(wr, E)
				di = ldexp(wi, E)
				goto DoubleCheck
			end if
		else
			if E > -500 then E = -500
			if Ec < E then E = Ec
		end if
	end scope
	S = iif(E < -1070, 0.0, ldexp(1.0, E))
	ex = Ec - E
	if ex > 1000 then ex = 1000
	K = iif(ex < -1070, 0.0, ldexp(1.0, ex))
	tix = Ref_NextTiny(r, m)
	nextTiny = iif(tix < r.nTiny, r.tinyIdx[tix], &h7FFFFFFF)

ScaledCheck:
	if m >= refLen then
		if r.escaped then
			'' delta (< 1e-90) is negligible: the pixel escapes with the reference
			mag = Zr[refLen] * Zr[refLen] + Zi[refLen] * Zi[refLen]
			return SMOOTH_NU(n, mag)
		end if
		if n >= maxIter then return NU_INTERIOR
		'' reference ended early: continue from the full value
		dr = Zr[refLen] : di = Zi[refLen]
		m = 0
		goto DoubleLoop
	end if
	if m = nextTiny then
		'' rebase test against a tiny reference value
		dim sh as long = r.tinyE[tix] - E
		if sh < 300 then
			if sh < -1200 then sh = -1200
			zr_ = ldexp(r.tinyR[tix], sh) + wr
			zi_ = ldexp(r.tinyI[tix], sh) + wi
			if zr_ * zr_ + zi_ * zi_ < wr * wr + wi * wi then
				wr = zr_ : wi = zi_
				m = 0
				goto ScaledEnter
			end if
		end if
	end if

	while n < maxIter
		if m = nextTiny then
			'' fully general step: delta' = 2 Z delta + delta^2 + delta_c
			dim as double tZr = r.tinyR[tix], tZi = r.tinyI[tix]
			dim as longint e1 = clngint(r.tinyE[tix]) + E + 1, e2 = clngint(E) * 2, e3 = Ec
			dim as double a1r = tZr * wr - tZi * wi, a1i = tZr * wi + tZi * wr
			dim as double a2r = wr * wr - wi * wi, a2i = 2 * wr * wi
			dim as longint em = e3
			if (a1r <> 0 orelse a1i <> 0) andalso e1 > em then em = e1
			if (a2r <> 0 orelse a2i <> 0) andalso e2 > em then em = e2
			dim as longint s1 = e1 - em, s2 = e2 - em, s3 = e3 - em
			if s1 < -1200 then s1 = -1200
			if s2 < -1200 then s2 = -1200
			if s3 < -1200 then s3 = -1200
			if s1 > 0 then s1 = 0
			if s2 > 0 then s2 = 0
			wr = ldexp(a1r, s1) + ldexp(a2r, s2) + ldexp(ur, s3)
			wi = ldexp(a1i, s1) + ldexp(a2i, s2) + ldexp(ui, s3)
			if em < -2000000000 then em = -2000000000
			E = em
			m += 1
			n += 1
			goto ScaledEnter
		end if
		tr = 2 * (Zr[m] * wr - Zi[m] * wi) + (wr * wr - wi * wi) * S + ur * K
		ti = 2 * (Zr[m] * wi + Zi[m] * wr) + 2 * wr * wi * S + ui * K
		wr = tr
		wi = ti
		m += 1
		n += 1
		mag = wr * wr + wi * wi
		if mag > 1e80 orelse mag < 1e-80 then goto ScaledEnter
		if m >= refLen orelse m = nextTiny then goto ScaledCheck
	wend
	return NU_INTERIOR

DoubleCheck:
	zr_ = Zr[m] + dr
	zi_ = Zi[m] + di
	mag = zr_ * zr_ + zi_ * zi_
	if mag > BAILOUT_R2 then return SMOOTH_NU(n, mag)
	dmag = dr * dr + di * di
	if mag < dmag orelse m >= refLen then
		dr = zr_ : di = zi_
		m = 0
		dmag = mag
	end if
	if dmag < 1e-280 then
		wr = dr : wi = di : E = 0
		goto ScaledEnter
	end if

DoubleLoop:
	while n < maxIter
		tr = 2 * (Zr[m] * dr - Zi[m] * di) + dr * dr - di * di + dcr
		ti = 2 * (Zr[m] * di + Zi[m] * dr) + 2 * dr * di + dci
		dr = tr
		di = ti
		m += 1
		n += 1
		zr_ = Zr[m] + dr
		zi_ = Zi[m] + di
		mag = zr_ * zr_ + zi_ * zi_
		if mag > BAILOUT_R2 then return SMOOTH_NU(n, mag)
		dmag = dr * dr + di * di
		if mag < dmag orelse m >= refLen then
			dr = zr_ : di = zi_
			m = 0
			dmag = mag
		end if
		if dmag < 1e-280 then
			wr = dr : wi = di : E = 0
			goto ScaledEnter
		end if
	wend
	return NU_INTERIOR
end function

function PixelPerturb(byref job as RenderJob, byval px as long, byval py as long) as double
	dim ox as double = px - (job.w - 1) * 0.5
	dim oy as double = -(py - (job.h - 1) * 0.5)
	if job.zbits <= 40 then
		if KnownInterior(job.cxd + ox * job.psd, job.cyd + oy * job.psd) then return NU_KNOWN_IN
	end if
	return PerturbIterate(job, ox, oy, job.useSeries)
end function
