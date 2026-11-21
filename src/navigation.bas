'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - arbitrary precision numbers, view state, navigation
''
'' The view (centre + half height) lives exclusively in MPFR variables.
'' Nothing here converts a coordinate to DOUBLE except for *relative*
'' quantities (pixel offsets, ratios) where double precision is exact enough.
'' ---------------------------------------------------------------------------
#include once "common.bi"

const LOG10_2 as double = 0.30102999566398120

'' ---- number <-> string --------------------------------------------------------

'' Decimal string of x.  digits = 0 writes enough digits to round-trip the
'' full precision of x.
function HpToStr(byval x as mpfr_ptr, byval digits as long = 0) as string
	if mpfr_number_p(x) = 0 then return "nan"
	if mpfr_zero_p(x) then return "0"
	dim n as long = digits
	if n <= 0 then n = int(mpfr_get_prec(x) * LOG10_2) + 3
	dim e as mpfr_exp_t
	dim p as zstring ptr = mpfr_get_str(0, @e, 10, n, x, MPFR_RNDN)
	if p = 0 then return "nan"
	dim s as string = *p
	mpfr_free_str(p)
	dim neg as boolean = (left(s, 1) = "-")
	if neg then s = mid(s, 2)
	dim l as long = len(s)
	while l > 1 andalso s[l - 1] = asc("0")
		l -= 1
	wend
	s = left(s, l)
	'' value = 0.s * 10^e
	dim r as string
	if e > -6 andalso e <= 21 then
		if e <= 0 then
			r = "0." & string(-e, "0") & s
		elseif e >= len(s) then
			r = s & string(e - len(s), "0")
		else
			r = left(s, e) & "." & mid(s, e + 1)
		end if
	else
		r = left(s, 1)
		if len(s) > 1 then r &= "." & mid(s, 2)
		r &= "e" & str(e - 1)
	end if
	if neg then r = "-" & r
	return r
end function

'' Strict decimal parser.  The precision of x becomes at least minPrec and
'' large enough for every digit in the string.  Returns false for anything
'' that is not a finite decimal number (x is then left untouched).
function HpFromStr(byval x as mpfr_ptr, byref txt as string, byval minPrec as long = 64) as boolean
	dim s as string = trim(txt, any " " & chr(9) & chr(13) & chr(10))
	if len(s) = 0 orelse len(s) > 2000000 then return false
	dim digits as long = 0, seenE as boolean = false, mant as long = 0
	for i as long = 0 to len(s) - 1
		select case s[i]
		case asc("0") to asc("9")
			if seenE = false then mant += 1
			digits += 1
		case asc("+"), asc("-")
			if i > 0 andalso s[i - 1] <> asc("e") andalso s[i - 1] <> asc("E") then return false
		case asc(".")
			if seenE then return false
		case asc("e"), asc("E")
			if seenE orelse mant = 0 then return false
			seenE = true
		case else
			return false
		end select
	next
	if mant = 0 then return false
	dim prec as long = int(mant / LOG10_2) + 32
	if prec < minPrec then prec = minPrec
	dim tmp as mpfr_t
	mpfr_init2(@tmp, prec)
	dim ok as boolean = (mpfr_set_str(@tmp, strptr(s), 10, MPFR_RNDN) = 0)
	if ok then ok = (mpfr_number_p(@tmp) <> 0)
	if ok then
		mpfr_set_prec(x, prec)
		mpfr_set(x, @tmp, MPFR_RNDN)
	end if
	mpfr_clear(@tmp)
	return ok
end function

'' Shortest decimal string that reads back to exactly the same value at the
'' precision of x (used for the 64-bit view scale, so 1.25e-60 prints as such).
function HpToStrShortest(byval x as mpfr_ptr) as string
	dim full as long = int(mpfr_get_prec(x) * LOG10_2) + 3
	dim t as mpfr_t
	mpfr_init2(@t, mpfr_get_prec(x))
	dim r as string
	for n as long = 1 to full
		r = HpToStr(x, n)
		if mpfr_set_str(@t, strptr(r), 10, MPFR_RNDN) = 0 then
			if mpfr_cmp(@t, x) = 0 then exit for
		end if
	next
	mpfr_clear(@t)
	return r
end function

'' Short scientific notation for display, e.g. 1.234e+45
function HpShort(byval x as mpfr_ptr, byval sig as long = 4) as string
	if mpfr_number_p(x) = 0 then return "nan"
	if mpfr_zero_p(x) then return "0"
	dim e as mpfr_exp_t
	dim p as zstring ptr = mpfr_get_str(0, @e, 10, sig, x, MPFR_RNDN)
	if p = 0 then return "nan"
	dim s as string = *p
	mpfr_free_str(p)
	dim sign as string
	if left(s, 1) = "-" then sign = "-" : s = mid(s, 2)
	if e >= 1 andalso e <= sig then
		'' plain number
		dim r as string = left(s, e)
		dim fr as string = mid(s, e + 1)
		dim l as long = len(fr)
		while l > 0 andalso fr[l - 1] = asc("0")
			l -= 1
		wend
		if l > 0 then r &= "." & left(fr, l)
		return sign & r
	end if
	dim ex as longint = e - 1
	return sign & left(s, 1) & "." & mid(s, 2) & "e" & iif(ex >= 0, "+", "") & str(ex)
end function

'' ---- view -------------------------------------------------------------------

sub View_Init(byref v as ViewState, byval prec as long = 128)
	mpfr_init2(@v.cx, prec)
	mpfr_init2(@v.cy, prec)
	mpfr_init2(@v.halfh, 64)
	v.prec = prec
	v.valid = 1
	mpfr_set_d(@v.cx, -0.5, MPFR_RNDN)
	mpfr_set_d(@v.cy, 0.0, MPFR_RNDN)
	mpfr_set_d(@v.halfh, HOME_HALFH, MPFR_RNDN)
end sub

sub View_Clear(byref v as ViewState)
	if v.valid then
		mpfr_clear(@v.cx)
		mpfr_clear(@v.cy)
		mpfr_clear(@v.halfh)
		v.valid = 0
	end if
end sub

sub View_Copy(byref dst as ViewState, byref src as ViewState)
	if dst.valid = 0 then View_Init(dst, src.prec)
	mpfr_set_prec(@dst.cx, src.prec)
	mpfr_set_prec(@dst.cy, src.prec)
	mpfr_set_prec(@dst.halfh, 64)
	mpfr_set(@dst.cx, @src.cx, MPFR_RNDN)
	mpfr_set(@dst.cy, @src.cy, MPFR_RNDN)
	mpfr_set(@dst.halfh, @src.halfh, MPFR_RNDN)
	dst.prec = src.prec
end sub

sub View_Reset(byref v as ViewState)
	mpfr_set_prec(@v.cx, 128)
	mpfr_set_prec(@v.cy, 128)
	v.prec = 128
	mpfr_set_d(@v.cx, -0.5, MPFR_RNDN)
	mpfr_set_d(@v.cy, 0.0, MPFR_RNDN)
	mpfr_set_d(@v.halfh, HOME_HALFH, MPFR_RNDN)
end sub

'' Number of bits needed to resolve one pixel: ceil(log2(1 / pixel size)).
function View_ZoomBits(byref v as ViewState, byval hpx as long) as long
	dim e as clong
	dim m as double = mpfr_get_d_2exp(@e, @v.halfh, MPFR_RNDN)
	if m <= 0 then return 0
	dim lg as double = log2(m) + e          '' log2(halfh)
	dim zb as double = -lg - 1 + log2(cdbl(iif(hpx < 2, 2, hpx)))
	return clng(ceil(zb))
end function

'' Automatic precision policy: 2 integer bits + pixel resolution + guard bits.
function PrecisionFor(byval zbits as long, byval guard as long) as long
	dim p as long = 2 + zbits + guard
	p = ((p + 31) \ 32) * 32
	if p < 64 then p = 64
	return p
end function

'' Smallest precision that can still tell neighbouring pixels apart.
function PrecisionMinimum(byval zbits as long) as long
	return zbits + 2 + 8
end function

'' Grow (never shrink) the precision of the centre coordinates.
sub View_EnsurePrec(byref v as ViewState, byval bits as long)
	if bits > v.prec then
		mpfr_prec_round(@v.cx, bits, MPFR_RNDN)
		mpfr_prec_round(@v.cy, bits, MPFR_RNDN)
		v.prec = bits
	end if
end sub

'' Make sure the centre has enough bits for the current zoom on a hpx screen.
sub View_AutoPrec(byref v as ViewState, byval hpx as long)
	dim need as long = PrecisionFor(View_ZoomBits(v, hpx), 64) + 64
	View_EnsurePrec(v, need)
end sub

'' pixel size = 2 * halfh / h   (result precision 64 bits is plenty: it is a
'' scale factor, its relative error only scales the picture by 1 + 2^-64)
sub View_PixelSize(byref v as ViewState, byval hpx as long, byval ps as mpfr_ptr)
	mpfr_mul_2ui(ps, @v.halfh, 1, MPFR_RNDN)
	mpfr_div_d(ps, ps, cdbl(hpx), MPFR_RNDN)
end sub

'' Complex coordinate of the (possibly fractional) pixel position px,py.
sub View_PixelToComplex(byref v as ViewState, byval w as long, byval h as long, _
		byval px as double, byval py as double, byval ox as mpfr_ptr, byval oy as mpfr_ptr)
	dim ps as mpfr_t, t as mpfr_t
	mpfr_init2(@ps, 64)
	mpfr_init2(@t, 64)
	View_PixelSize(v, h, @ps)
	mpfr_set_prec(ox, v.prec)
	mpfr_set_prec(oy, v.prec)
	mpfr_mul_d(@t, @ps, px - (w - 1) * 0.5, MPFR_RNDN)
	mpfr_add(ox, @v.cx, @t, MPFR_RNDN)
	mpfr_mul_d(@t, @ps, py - (h - 1) * 0.5, MPFR_RNDN)
	mpfr_sub(oy, @v.cy, @t, MPFR_RNDN)
	mpfr_clear(@ps)
	mpfr_clear(@t)
end sub

const MAX_ZOOM_BITS = 3000000   '' sanity limit, about 10^900000

'' Zoom by "factor" (>1 zooms in) keeping the point under pixel px,py fixed.
'' Returns false when the zoom limit was hit.
function View_ZoomAt(byref v as ViewState, byval w as long, byval h as long, _
		byval px as double, byval py as double, byval factor as double) as boolean
	if factor <= 0 orelse factor <> factor then return false
	dim nh as mpfr_t
	mpfr_init2(@nh, 64)
	mpfr_div_d(@nh, @v.halfh, factor, MPFR_RNDN)
	if mpfr_cmp_d(@nh, 8.0) > 0 then mpfr_set_d(@nh, 8.0, MPFR_RNDN)
	if -mpfr_get_exp(@nh) > MAX_ZOOM_BITS then
		mpfr_clear(@nh)
		return false
	end if
	'' new centre = centre + offset * (ps_old - ps_new), offset in pixels
	dim psOld as mpfr_t, psNew as mpfr_t, t as mpfr_t
	mpfr_init2(@psOld, 64)
	mpfr_init2(@psNew, 64)
	mpfr_init2(@t, 64)
	View_PixelSize(v, h, @psOld)
	mpfr_set(@v.halfh, @nh, MPFR_RNDN)
	View_AutoPrec(v, h)
	View_PixelSize(v, h, @psNew)
	mpfr_sub(@psOld, @psOld, @psNew, MPFR_RNDN)
	mpfr_mul_d(@t, @psOld, px - (w - 1) * 0.5, MPFR_RNDN)
	mpfr_add(@v.cx, @v.cx, @t, MPFR_RNDN)
	mpfr_mul_d(@t, @psOld, py - (h - 1) * 0.5, MPFR_RNDN)
	mpfr_sub(@v.cy, @v.cy, @t, MPFR_RNDN)
	mpfr_clear(@nh)
	mpfr_clear(@psOld)
	mpfr_clear(@psNew)
	mpfr_clear(@t)
	return true
end function

'' Move the view by a pixel delta (dx > 0 moves the picture to the right).
sub View_Pan(byref v as ViewState, byval h as long, byval dx as double, byval dy as double)
	dim ps as mpfr_t, t as mpfr_t
	mpfr_init2(@ps, 64)
	mpfr_init2(@t, 64)
	View_AutoPrec(v, h)
	View_PixelSize(v, h, @ps)
	mpfr_mul_d(@t, @ps, dx, MPFR_RNDN)
	mpfr_sub(@v.cx, @v.cx, @t, MPFR_RNDN)
	mpfr_mul_d(@t, @ps, dy, MPFR_RNDN)
	mpfr_add(@v.cy, @v.cy, @t, MPFR_RNDN)
	'' keep the centre in a sane box
	if mpfr_cmp_d(@v.cx, 8.0) > 0 then mpfr_set_d(@v.cx, 8.0, MPFR_RNDN)
	if mpfr_cmp_d(@v.cx, -8.0) < 0 then mpfr_set_d(@v.cx, -8.0, MPFR_RNDN)
	if mpfr_cmp_d(@v.cy, 8.0) > 0 then mpfr_set_d(@v.cy, 8.0, MPFR_RNDN)
	if mpfr_cmp_d(@v.cy, -8.0) < 0 then mpfr_set_d(@v.cy, -8.0, MPFR_RNDN)
	mpfr_clear(@ps)
	mpfr_clear(@t)
end sub

'' Centre the view on pixel px,py.
sub View_CenterOn(byref v as ViewState, byval w as long, byval h as long, byval px as double, byval py as double)
	View_Pan(v, h, (w - 1) * 0.5 - px, (h - 1) * 0.5 - py)
end sub

'' Magnification relative to the home view, as a display string.
function View_ZoomStr(byref v as ViewState, byval sig as long = 4) as string
	dim z as mpfr_t
	mpfr_init2(@z, 64)
	mpfr_d_div(@z, HOME_HALFH, @v.halfh, MPFR_RNDN)
	function = HpShort(@z, sig)
	mpfr_clear(@z)
end function

'' log10 of the magnification (double is fine: it is only an exponent).
function View_ZoomLog10(byref v as ViewState) as double
	dim e as clong
	dim m as double = mpfr_get_d_2exp(@e, @v.halfh, MPFR_RNDN)
	if m <= 0 then return 0
	return log10(HOME_HALFH) - (log10(m) + e * LOG10_2)
end function

'' Set the view from decimal strings.  halfhStr is the half height; when it
'' is empty zoomStr (magnification) is used instead.  On failure the view is
'' unchanged and errMsg explains why.
function View_SetFromStrings(byref v as ViewState, byref xs as string, byref ys as string, _
		byref halfhStr as string, byref zoomStr as string, byref errMsg as string) as boolean
	dim as mpfr_t nx, ny, nh
	mpfr_init2(@nx, 64)
	mpfr_init2(@ny, 64)
	mpfr_init2(@nh, 64)
	dim ok as boolean = true
	if HpFromStr(@nx, xs, 128) = false then ok = false : errMsg = "invalid X coordinate"
	if ok andalso HpFromStr(@ny, ys, 128) = false then ok = false : errMsg = "invalid Y coordinate"
	if ok then
		if len(trim(halfhStr)) > 0 then
			if HpFromStr(@nh, halfhStr, 64) = false then ok = false : errMsg = "invalid half height"
		else
			if HpFromStr(@nh, zoomStr, 64) = false orelse mpfr_sgn(@nh) <= 0 then
				ok = false : errMsg = "invalid zoom"
			else
				mpfr_d_div(@nh, HOME_HALFH, @nh, MPFR_RNDN)
			end if
		end if
	end if
	if ok then
		if mpfr_sgn(@nh) <= 0 orelse mpfr_cmp_d(@nh, 8.0) > 0 _
		   orelse -mpfr_get_exp(@nh) > MAX_ZOOM_BITS then
			ok = false : errMsg = "zoom out of range"
		elseif mpfr_cmp_d(@nx, 8.0) > 0 orelse mpfr_cmp_d(@nx, -8.0) < 0 _
		   orelse mpfr_cmp_d(@ny, 8.0) > 0 orelse mpfr_cmp_d(@ny, -8.0) < 0 then
			ok = false : errMsg = "coordinates out of range (-8..8)"
		end if
	end if
	if ok then
		dim p as long = mpfr_get_prec(@nx)
		if mpfr_get_prec(@ny) > p then p = mpfr_get_prec(@ny)
		mpfr_set_prec(@v.cx, p)
		mpfr_set_prec(@v.cy, p)
		v.prec = p
		mpfr_set(@v.cx, @nx, MPFR_RNDN)
		mpfr_set(@v.cy, @ny, MPFR_RNDN)
		'' the scale is always a 64-bit value
		mpfr_set_prec(@v.halfh, 64)
		mpfr_set(@v.halfh, @nh, MPFR_RNDN)
	end if
	mpfr_clear(@nx)
	mpfr_clear(@ny)
	mpfr_clear(@nh)
	return ok
end function

'' Describe how the picture of view "a" (wa x ha pixels) appears inside view
'' "b" (wb x hb pixels): scale k and the screen position (sx, sy) of the
'' centre of a.  Returns false when the relation is not representable.
function View_Relate(byref a as ViewState, byval wa as long, byval ha as long, _
		byref b as ViewState, byval wb as long, byval hb as long, _
		byref k as double, byref sx as double, byref sy as double) as boolean
	dim as mpfr_t psA, psB, t
	mpfr_init2(@psA, 64)
	mpfr_init2(@psB, 64)
	dim tp as long = iif(a.prec > b.prec, a.prec, b.prec)
	mpfr_init2(@t, tp)
	View_PixelSize(a, ha, @psA)
	View_PixelSize(b, hb, @psB)
	mpfr_div(@psA, @psA, @psB, MPFR_RNDN)
	k = mpfr_get_d(@psA, MPFR_RNDN)
	mpfr_sub(@t, @a.cx, @b.cx, MPFR_RNDN)
	mpfr_div(@t, @t, @psB, MPFR_RNDN)
	sx = (wb - 1) * 0.5 + mpfr_get_d(@t, MPFR_RNDN)
	mpfr_sub(@t, @a.cy, @b.cy, MPFR_RNDN)
	mpfr_div(@t, @t, @psB, MPFR_RNDN)
	sy = (hb - 1) * 0.5 - mpfr_get_d(@t, MPFR_RNDN)
	mpfr_clear(@psA)
	mpfr_clear(@psB)
	mpfr_clear(@t)
	if k <> k orelse sx <> sx orelse sy <> sy then return false
	if k < 1e-4 orelse k > 1e4 then return false
	if abs(sx) > 1e7 orelse abs(sy) > 1e7 then return false
	return true
end function
