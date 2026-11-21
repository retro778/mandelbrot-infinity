'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - locating mini-Mandelbrot nuclei
''
'' A nucleus of period p is a root of z_p(c) = 0.  It is found in two steps:
''   1. period detection ("ball" method): iterate z and dz/dc at the centre
''      of a disc of radius R; the first n with |z_n| < R |dz_n/dc| is the
''      period of a nucleus expected inside the disc;
''   2. Newton's method on z_p(c) in MPFR:  c <- c - z_p / (dz_p/dc).
'' The size of the mini-set follows from the standard estimate
''   size = 1 / (beta * lambda^2),  lambda = prod 2 z_k,  beta = sum 1/lambda_k
'' Because Newton converges to full working precision, the coordinates
'' produced here are verified nuclei, usable as deep-zoom presets.
'' ---------------------------------------------------------------------------
#include once "common.bi"

type NucCtx
	prec as long
	cr as mpfr_t : ci as mpfr_t
	zr as mpfr_t : zi as mpfr_t
	dr as mpfr_t : di as mpfr_t
	t1 as mpfr_t : t2 as mpfr_t : t3 as mpfr_t : t4 as mpfr_t
	sr as mpfr_t : si as mpfr_t
end type

private sub Nuc_Init(byref n as NucCtx, byval prec as long)
	n.prec = prec
	mpfr_init2(@n.cr, prec) : mpfr_init2(@n.ci, prec)
	mpfr_init2(@n.zr, prec) : mpfr_init2(@n.zi, prec)
	mpfr_init2(@n.dr, prec) : mpfr_init2(@n.di, prec)
	mpfr_init2(@n.t1, prec) : mpfr_init2(@n.t2, prec)
	mpfr_init2(@n.t3, prec) : mpfr_init2(@n.t4, prec)
	mpfr_init2(@n.sr, prec) : mpfr_init2(@n.si, prec)
end sub

private sub Nuc_Clear(byref n as NucCtx)
	mpfr_clear(@n.cr) : mpfr_clear(@n.ci) : mpfr_clear(@n.zr) : mpfr_clear(@n.zi)
	mpfr_clear(@n.dr) : mpfr_clear(@n.di) : mpfr_clear(@n.t1) : mpfr_clear(@n.t2)
	mpfr_clear(@n.t3) : mpfr_clear(@n.t4) : mpfr_clear(@n.sr) : mpfr_clear(@n.si)
end sub

'' (rr, ri) = (ar, ai) * (br, bi); t1, t2 are scratch and must not alias inputs
private sub CMul(byval rr as mpfr_ptr, byval ri as mpfr_ptr, byval ar as mpfr_ptr, byval ai as mpfr_ptr, _
		byval br as mpfr_ptr, byval bi as mpfr_ptr, byval t1 as mpfr_ptr, byval t2 as mpfr_ptr)
	mpfr_mul(t1, ar, br, MPFR_RNDN)
	mpfr_mul(t2, ai, bi, MPFR_RNDN)
	mpfr_sub(t1, t1, t2, MPFR_RNDN)
	mpfr_mul(t2, ar, bi, MPFR_RNDN)
	mpfr_mul(ri, ai, br, MPFR_RNDN)
	mpfr_add(ri, ri, t2, MPFR_RNDN)
	mpfr_set(rr, t1, MPFR_RNDN)
end sub

'' (rr, ri) = (ar, ai) / (br, bi); t1..t3 scratch
private sub CDiv(byval rr as mpfr_ptr, byval ri as mpfr_ptr, byval ar as mpfr_ptr, byval ai as mpfr_ptr, _
		byval br as mpfr_ptr, byval bi as mpfr_ptr, byval t1 as mpfr_ptr, byval t2 as mpfr_ptr, _
		byval t3 as mpfr_ptr)
	mpfr_sqr(t3, br, MPFR_RNDN)
	mpfr_sqr(t1, bi, MPFR_RNDN)
	mpfr_add(t3, t3, t1, MPFR_RNDN)             '' |b|^2
	mpfr_mul(t1, ar, br, MPFR_RNDN)
	mpfr_mul(t2, ai, bi, MPFR_RNDN)
	mpfr_add(t1, t1, t2, MPFR_RNDN)             '' re(a conj b)
	mpfr_mul(t2, ai, br, MPFR_RNDN)
	mpfr_mul(ri, ar, bi, MPFR_RNDN)
	mpfr_sub(ri, t2, ri, MPFR_RNDN)             '' im(a conj b)
	mpfr_div(rr, t1, t3, MPFR_RNDN)
	mpfr_div(ri, ri, t3, MPFR_RNDN)
end sub

'' z_p(c) and dz_p/dc for the c stored in n.cr / n.ci.
private function Nuc_Orbit(byref n as NucCtx, byval period as long, byval cancel as long ptr) as boolean
	mpfr_set_zero(@n.zr, 1) : mpfr_set_zero(@n.zi, 1)
	mpfr_set_zero(@n.dr, 1) : mpfr_set_zero(@n.di, 1)
	for k as long = 1 to period
		'' d = 2 z d + 1
		CMul(@n.dr, @n.di, @n.zr, @n.zi, @n.dr, @n.di, @n.t1, @n.t2)
		mpfr_mul_2ui(@n.dr, @n.dr, 1, MPFR_RNDN)
		mpfr_mul_2ui(@n.di, @n.di, 1, MPFR_RNDN)
		mpfr_add_d(@n.dr, @n.dr, 1.0, MPFR_RNDN)
		'' z = z^2 + c
		mpfr_sqr(@n.t1, @n.zr, MPFR_RNDN)
		mpfr_sqr(@n.t2, @n.zi, MPFR_RNDN)
		mpfr_mul(@n.zi, @n.zr, @n.zi, MPFR_RNDN)
		mpfr_mul_2ui(@n.zi, @n.zi, 1, MPFR_RNDN)
		mpfr_add(@n.zi, @n.zi, @n.ci, MPFR_RNDN)
		mpfr_sub(@n.zr, @n.t1, @n.t2, MPFR_RNDN)
		mpfr_add(@n.zr, @n.zr, @n.cr, MPFR_RNDN)
		if (k and 255) = 0 then
			if cancel andalso *cancel then return false
		end if
	next
	return true
end function

'' Newton iteration from the c in n.cr/n.ci.  Returns true when the step
'' size dropped below 2^-(prec-12) (converged to working precision).
private function Nuc_Newton(byref n as NucCtx, byval period as long, byval cancel as long ptr) as boolean
	for it as long = 1 to 80
		if Nuc_Orbit(n, period, cancel) = false then return false
		if mpfr_zero_p(@n.dr) andalso mpfr_zero_p(@n.di) then return false
		CDiv(@n.sr, @n.si, @n.zr, @n.zi, @n.dr, @n.di, @n.t1, @n.t2, @n.t3)
		if mpfr_number_p(@n.sr) = 0 orelse mpfr_number_p(@n.si) = 0 then return false
		mpfr_sub(@n.cr, @n.cr, @n.sr, MPFR_RNDN)
		mpfr_sub(@n.ci, @n.ci, @n.si, MPFR_RNDN)
		if mpfr_cmp_d(@n.cr, 4.0) > 0 orelse mpfr_cmp_d(@n.cr, -4.0) < 0 then return false
		if mpfr_cmp_d(@n.ci, 4.0) > 0 orelse mpfr_cmp_d(@n.ci, -4.0) < 0 then return false
		'' converged?
		dim small as boolean = true
		if mpfr_zero_p(@n.sr) = 0 then
			if mpfr_get_exp(@n.sr) > -(n.prec - 12) then small = false
		end if
		if mpfr_zero_p(@n.si) = 0 then
			if mpfr_get_exp(@n.si) > -(n.prec - 12) then small = false
		end if
		if small then return true
	next
	return false
end function

'' |size| of the period-p mini-set at the nucleus in n.cr/n.ci -> osize.
private sub Nuc_Size(byref n as NucCtx, byval period as long, byval osize as mpfr_ptr)
	dim as mpfr_t lr, li, br, bi, ir, ii, one, zero
	mpfr_init2(@lr, 64) : mpfr_init2(@li, 64) : mpfr_init2(@br, 64) : mpfr_init2(@bi, 64)
	mpfr_init2(@ir, 64) : mpfr_init2(@ii, 64) : mpfr_init2(@one, 64) : mpfr_init2(@zero, 64)
	mpfr_set_d(@lr, 1, MPFR_RNDN) : mpfr_set_zero(@li, 1)
	mpfr_set_d(@br, 1, MPFR_RNDN) : mpfr_set_zero(@bi, 1)
	mpfr_set_d(@one, 1, MPFR_RNDN) : mpfr_set_zero(@zero, 1)
	mpfr_set_zero(@n.zr, 1) : mpfr_set_zero(@n.zi, 1)
	for k as long = 1 to period - 1
		mpfr_sqr(@n.t1, @n.zr, MPFR_RNDN)
		mpfr_sqr(@n.t2, @n.zi, MPFR_RNDN)
		mpfr_mul(@n.zi, @n.zr, @n.zi, MPFR_RNDN)
		mpfr_mul_2ui(@n.zi, @n.zi, 1, MPFR_RNDN)
		mpfr_add(@n.zi, @n.zi, @n.ci, MPFR_RNDN)
		mpfr_sub(@n.zr, @n.t1, @n.t2, MPFR_RNDN)
		mpfr_add(@n.zr, @n.zr, @n.cr, MPFR_RNDN)
		'' l = 2 z l ;  b = b + 1 / l
		CMul(@lr, @li, @n.zr, @n.zi, @lr, @li, @n.t1, @n.t2)
		mpfr_mul_2ui(@lr, @lr, 1, MPFR_RNDN)
		mpfr_mul_2ui(@li, @li, 1, MPFR_RNDN)
		CDiv(@ir, @ii, @one, @zero, @lr, @li, @n.t1, @n.t2, @n.t3)
		mpfr_add(@br, @br, @ir, MPFR_RNDN)
		mpfr_add(@bi, @bi, @ii, MPFR_RNDN)
	next
	'' size = 1 / (b * l^2)
	CMul(@ir, @ii, @lr, @li, @lr, @li, @n.t1, @n.t2)
	CMul(@ir, @ii, @ir, @ii, @br, @bi, @n.t1, @n.t2)
	mpfr_sqr(@n.t1, @ir, MPFR_RNDN)
	mpfr_sqr(@n.t2, @ii, MPFR_RNDN)
	mpfr_add(@n.t1, @n.t1, @n.t2, MPFR_RNDN)
	mpfr_sqrt(@n.t1, @n.t1, MPFR_RNDN)
	mpfr_set_prec(osize, 64)
	mpfr_d_div(osize, 1.0, @n.t1, MPFR_RNDN)
	mpfr_clear(@lr) : mpfr_clear(@li) : mpfr_clear(@br) : mpfr_clear(@bi)
	mpfr_clear(@ir) : mpfr_clear(@ii) : mpfr_clear(@one) : mpfr_clear(@zero)
end sub

'' Search the disc (cx, cy, radius rad) for the lowest-period nucleus.
'' On success ox/oy receive the nucleus (precision chosen so that it is
'' accurate far below the mini-set size), osize its size and period its
'' period.  cancel may be 0.
function Nucleus_Find(byval cx as mpfr_ptr, byval cy as mpfr_ptr, byval rad as mpfr_ptr, _
		byval maxPeriod as long, byval cancel as long ptr, byval ox as mpfr_ptr, _
		byval oy as mpfr_ptr, byval osize as mpfr_ptr, byref period as long) as boolean
	if mpfr_sgn(rad) <= 0 then return false
	dim prec as long = -mpfr_get_exp(rad) * 2 + 128
	if prec < 128 then prec = 128
	dim found as boolean = false
	dim as mpfr_t zr, zi, dr, di, t1, t2, m1, m2, r2
	mpfr_init2(@zr, prec) : mpfr_init2(@zi, prec)
	mpfr_init2(@dr, 64) : mpfr_init2(@di, 64)
	mpfr_init2(@t1, prec) : mpfr_init2(@t2, prec)
	mpfr_init2(@m1, 64) : mpfr_init2(@m2, 64) : mpfr_init2(@r2, 64)
	mpfr_sqr(@r2, rad, MPFR_RNDN)
	mpfr_set_zero(@zr, 1) : mpfr_set_zero(@zi, 1)
	mpfr_set_zero(@dr, 1) : mpfr_set_zero(@di, 1)
	dim nc as NucCtx
	Nuc_Init(nc, prec)
	dim tries as long = 0
	for n as long = 1 to maxPeriod
		'' d = 2 z d + 1 (64 bit mantissa is enough for a magnitude test)
		mpfr_mul(@m1, @zr, @dr, MPFR_RNDN)
		mpfr_mul(@m2, @zi, @di, MPFR_RNDN)
		mpfr_sub(@m1, @m1, @m2, MPFR_RNDN)
		mpfr_mul(@m2, @zr, @di, MPFR_RNDN)
		mpfr_mul(@di, @zi, @dr, MPFR_RNDN)
		mpfr_add(@di, @di, @m2, MPFR_RNDN)
		mpfr_mul_2ui(@di, @di, 1, MPFR_RNDN)
		mpfr_mul_2ui(@dr, @m1, 1, MPFR_RNDN)
		mpfr_add_d(@dr, @dr, 1.0, MPFR_RNDN)
		'' z = z^2 + c
		mpfr_sqr(@t1, @zr, MPFR_RNDN)
		mpfr_sqr(@t2, @zi, MPFR_RNDN)
		mpfr_mul(@zi, @zr, @zi, MPFR_RNDN)
		mpfr_mul_2ui(@zi, @zi, 1, MPFR_RNDN)
		mpfr_add(@zi, @zi, cy, MPFR_RNDN)
		mpfr_sub(@zr, @t1, @t2, MPFR_RNDN)
		mpfr_add(@zr, @zr, cx, MPFR_RNDN)
		'' |z|^2 and R^2 |d|^2
		mpfr_sqr(@m1, @zr, MPFR_RNDN)
		mpfr_sqr(@m2, @zi, MPFR_RNDN)
		mpfr_add(@m1, @m1, @m2, MPFR_RNDN)
		if mpfr_cmp_d(@m1, 1e6) > 0 then exit for            '' centre escaped
		mpfr_sqr(@m2, @dr, MPFR_RNDN)
		mpfr_sqr(@t1, @di, MPFR_RNDN)
		mpfr_add(@m2, @m2, @t1, MPFR_RNDN)
		mpfr_mul(@m2, @m2, @r2, MPFR_RNDN)
		if (n and 127) = 0 then
			if cancel andalso *cancel then exit for
		end if
		if mpfr_cmp(@m1, @m2) < 0 then
			'' candidate period n: refine with Newton from the disc centre
			mpfr_set(@nc.cr, cx, MPFR_RNDN)
			mpfr_set(@nc.ci, cy, MPFR_RNDN)
			if Nuc_Newton(nc, n, cancel) then
				'' inside (twice) the disc?
				mpfr_sub(@t1, @nc.cr, cx, MPFR_RNDN)
				mpfr_sub(@t2, @nc.ci, cy, MPFR_RNDN)
				mpfr_sqr(@m1, @t1, MPFR_RNDN)
				mpfr_sqr(@m2, @t2, MPFR_RNDN)
				mpfr_add(@m1, @m1, @m2, MPFR_RNDN)
				mpfr_mul_2ui(@m2, @r2, 2, MPFR_RNDN)
				if mpfr_cmp(@m1, @m2) <= 0 then
					period = n
					found = true
					exit for
				end if
			end if
			if cancel andalso *cancel then exit for
			tries += 1
			if tries >= 12 then exit for
		end if
	next
	if found then
		Nuc_Size(nc, period, osize)
		'' make the nucleus accurate well below the mini-set size
		dim need as long = -mpfr_get_exp(osize) * 2 + 192
		if need > 4000000 then need = 4000000
		if need > prec then
			dim n2 as NucCtx
			Nuc_Init(n2, need)
			mpfr_set(@n2.cr, @nc.cr, MPFR_RNDN)
			mpfr_set(@n2.ci, @nc.ci, MPFR_RNDN)
			if Nuc_Newton(n2, period, cancel) then
				Nuc_Size(n2, period, osize)
				mpfr_set_prec(ox, need) : mpfr_set_prec(oy, need)
				mpfr_set(ox, @n2.cr, MPFR_RNDN)
				mpfr_set(oy, @n2.ci, MPFR_RNDN)
			else
				found = false
			end if
			Nuc_Clear(n2)
		else
			mpfr_set_prec(ox, prec) : mpfr_set_prec(oy, prec)
			mpfr_set(ox, @nc.cr, MPFR_RNDN)
			mpfr_set(oy, @nc.ci, MPFR_RNDN)
		end if
	end if
	Nuc_Clear(nc)
	mpfr_clear(@zr) : mpfr_clear(@zi) : mpfr_clear(@dr) : mpfr_clear(@di)
	mpfr_clear(@t1) : mpfr_clear(@t2) : mpfr_clear(@m1) : mpfr_clear(@m2) : mpfr_clear(@r2)
	return found
end function
