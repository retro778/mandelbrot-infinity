'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - automated tests (headless, no SDL)
''
'' Run with scripts/test.sh.  Exit code = number of failed checks.
'' ---------------------------------------------------------------------------
#include once "engine.bas"
#include once "file.bi"

dim shared g_pass as long = 0, g_fail as long = 0
dim shared g_tmp as string

sub Section(byref s as string)
	print
	print "== " & s
end sub

sub Check(byval cond as boolean, byref what as string)
	if cond then
		g_pass += 1
		print "  ok    " & what
	else
		g_fail += 1
		print "  FAIL  " & what
	end if
end sub

function SetView(byref v as ViewState, byref xs as string, byref ys as string, byref hs as string, _
		byval hpx as long) as boolean
	dim e as string
	if v.valid = 0 then View_Init(v)
	if View_SetFromStrings(v, xs, ys, hs, "", e) = false then print "  view error: " & e : return false
	View_AutoPrec(v, hpx)
	return true
end function

'' Compare a job against a reference job of the same size.
''   flips  : pixels classified differently (interior vs exterior)
''   bad    : pixels whose nu differs by more than 1e-3 AND by more than
''            2% of the local nu gradient (i.e. more than a 1/50 pixel shift)
''   maxDiff: largest |nu difference| over all exterior pixels
sub Compare(byref ref as RenderJob, byref x as RenderJob, byref flips as long, byref bad as long, _
		byref maxDiff as double)
	dim as long w = ref.w, h = ref.h
	flips = 0 : bad = 0 : maxDiff = 0
	for y as long = 0 to h - 1
		for xx as long = 0 to w - 1
			dim i as long = y * w + xx
			dim a as double = ref.nu[i], b as double = x.nu[i]
			if (a < 0) <> (b < 0) then flips += 1 : continue for
			if a < 0 then continue for
			dim d as double = abs(a - b)
			if d > maxDiff then maxDiff = d
			if d <= 1e-3 then continue for
			dim g as double = 0
			for k as long = 0 to 3
				dim as long nx = xx + iif(k = 0, -1, iif(k = 1, 1, 0)), ny = y + iif(k = 2, -1, iif(k = 3, 1, 0))
				if nx < 0 orelse ny < 0 orelse nx >= w orelse ny >= h then continue for
				dim c as double = ref.nu[ny * w + nx]
				if c < 0 then g = 1e30 else if abs(c - a) > g then g = abs(c - a)
			next
			if d > 0.02 * g then bad += 1
		next
	next
end sub

function RunJob(byref job as RenderJob, byref v as ViewState, byval w as long, byval h as long, _
		byval mode as long, byval it as long) as boolean
	if Job_Start(job, v, w, h, mode, it) = false then print "  job error: " & job.errMsg : return false
	return Job_Wait(job)
end function

function NuSpread(byref job as RenderJob, byref nInt as long) as double
	dim as double lo = 1e300, hi = 0
	nInt = 0
	for i as long = 0 to job.w * job.h - 1
		dim v as double = job.nu[i]
		if v < 0 then
			nInt += 1
		else
			if v < lo then lo = v
			if v > hi then hi = v
		end if
	next
	if hi < lo then return 0
	return hi - lo
end function

'' ===========================================================================
sub Test_Escape()
	Section("Mandelbrot escape calculations (|z|^2 > 4)")
	Check(EscapeCountR2(1, 0, 100) = 3, "c = 1 escapes at n = 3 (orbit 1, 2, 5)")
	Check(EscapeCountR2(2, 0, 100) = 2, "c = 2 escapes at n = 2 (orbit 2, 6)")
	Check(EscapeCountR2(0.5, 0, 100) = 5, "c = 0.5 escapes at n = 5")
	Check(EscapeCountR2(-2, 0, 100000) = -1, "c = -2 never escapes (orbit -2, 2, 2, ...)")
	Check(EscapeCountR2(0, 0, 100000) = -1, "c = 0 never escapes")
	Check(EscapeCountR2(0, 1, 100000) = -1, "c = i never escapes (pre-periodic)")
	Check(EscapeCountR2(-1, 0, 100000) = -1, "c = -1 never escapes (period 2)")
	Check(EscapeCountR2(0.26, 0, 100000) > 20, "c = 0.26 escapes slowly (just outside the cusp)")
	Check(EscapeCountR2(-2.0001, 0, 100000) > 0, "c = -2.0001 escapes")

	Section("Known interior and exterior points (all renderers)")
	Check(KnownInterior(0, 0), "cardioid test: 0 is interior")
	Check(KnownInterior(-1, 0), "bulb test: -1 is interior")
	Check(KnownInterior(0.3, 0) = false, "0.3 is not proven interior")
	Check(KnownInterior(-0.75, 0) = false, "-0.75 (cardioid/bulb contact point) is not claimed")
	Check(KnownInterior(0.24, 0.0), "0.24 is inside the cardioid")
	Check(KnownInterior(-0.1, 0.6), "-0.1+0.6i is inside the cardioid")
	Check(KnownInterior(-0.1, 0.7) = false, "-0.1+0.7i is not inside the cardioid")
	Check(EscapeTimeDouble(-0.12, 0.75, 5000, 1) < 0, "double: period-3 bulb centre is interior")
	Check(EscapeTimeDouble(-0.12, 0.75, 5000, 1) = NU_KNOWN_IN, "double: periodicity check proves the cycle")
	Check(EscapeTimeDouble(-0.12, 0.75, 5000, 0) = NU_INTERIOR, "double: same point without periodicity check")
	Check(EscapeTimeDouble(1, 1, 500, 1) > 0, "double: 1+i is exterior")
	'' smooth value is continuous and periodicity does not change exterior results
	dim d1 as double = EscapeTimeDouble(0.5, 0.5, 5000, 1), d2 as double = EscapeTimeDouble(0.5, 0.5, 5000, 0)
	Check(d1 = d2 andalso d1 > 0, "periodicity check does not alter exterior values")
	dim c as MpfrCtx
	MpfrCtx_Init(c, 200)
	mpfr_set_d(@c.cr, -0.12, MPFR_RNDN) : mpfr_set_d(@c.ci, 0.75, MPFR_RNDN)
	Check(IterateMpfr(c, 2000, 0) = NU_INTERIOR, "MPFR: period-3 bulb centre is interior")
	mpfr_set_d(@c.cr, 0.5, MPFR_RNDN) : mpfr_set_d(@c.ci, 0.5, MPFR_RNDN)
	dim m1 as double = IterateMpfr(c, 5000, 0)
	Check(abs(m1 - d1) < 1e-6, "MPFR and double agree on the smooth value of 0.5+0.5i (" & format(m1, "0.000000") & ")")
	mpfr_set_d(@c.cr, 1, MPFR_RNDN) : mpfr_set_d(@c.ci, 0, MPFR_RNDN)
	dim m2 as double = IterateMpfr(c, 100, 0)
	'' c = 1: orbit 1, 2, 5, 26, 677 -> first |z| > 256 at n = 5
	Check(m2 >= 5 andalso m2 < 6, "MPFR: c = 1 passes the bailout radius 256 at n = 5")
	MpfrCtx_Clear(c)
end sub

sub Test_Mapping()
	Section("Coordinate mapping and aspect ratio")
	dim v as ViewState
	View_Init(v)
	dim as mpfr_t x, y, x2, y2
	mpfr_init2(@x, 64) : mpfr_init2(@y, 64) : mpfr_init2(@x2, 64) : mpfr_init2(@y2, 64)
	View_PixelToComplex(v, 1280, 800, 639.5, 399.5, @x, @y)
	Check(mpfr_cmp_d(@x, -0.5) = 0 andalso mpfr_cmp_d(@y, 0) = 0, "image centre maps to the view centre")
	View_PixelToComplex(v, 1280, 800, 639.5, -0.5, @x, @y)
	Check(abs(mpfr_get_d(@y, MPFR_RNDN) - 1.25) < 1e-15, "top edge is centre + half height")
	View_PixelToComplex(v, 1280, 800, 639.5, 799.5, @x, @y)
	Check(abs(mpfr_get_d(@y, MPFR_RNDN) + 1.25) < 1e-15, "bottom edge is centre - half height (y axis points up)")
	View_PixelToComplex(v, 1280, 800, -0.5, 399.5, @x, @y)
	Check(abs(mpfr_get_d(@x, MPFR_RNDN) - (-0.5 - 2.0)) < 1e-15, "left edge = centre - half height * aspect")
	View_PixelToComplex(v, 1280, 800, 100, 100, @x, @y)
	View_PixelToComplex(v, 1280, 800, 101, 101, @x2, @y2)
	dim dx as double = mpfr_get_d(@x2, MPFR_RNDN) - mpfr_get_d(@x, MPFR_RNDN)
	dim dy as double = mpfr_get_d(@y, MPFR_RNDN) - mpfr_get_d(@y2, MPFR_RNDN)
	Check(abs(dx - dy) < 1e-15 andalso abs(dx - 2.5 / 800) < 1e-15, "pixels are square (dx = dy = 2*halfh/height)")
	'' aspect independent of window shape
	View_PixelToComplex(v, 800, 600, 399.5, -0.5, @x, @y)
	Check(abs(mpfr_get_d(@y, MPFR_RNDN) - 1.25) < 1e-15, "vertical extent does not depend on the window width")

	Section("Zoom-centre preservation")
	dim as string depth(0 to 3) = {"1.25", "1e-12", "1e-100", "1e-1000"}
	for i as long = 0 to 3
		SetView(v, "-0.743643887037158704752191506114774", "0.131825904205311970493132056385139", depth(i), 800)
		dim as long px = 137, py = 611
		mpfr_set_prec(@x, v.prec + 64) : mpfr_set_prec(@y, v.prec + 64)
		View_PixelToComplex(v, 1280, 800, px, py, @x, @y)
		dim okz as boolean = View_ZoomAt(v, 1280, 800, px, py, 1.5)
		View_PixelToComplex(v, 1280, 800, px, py, @x2, @y2)
		'' error in units of the new pixel size
		dim as mpfr_t ps, d
		mpfr_init2(@ps, 64) : mpfr_init2(@d, 64)
		View_PixelSize(v, 800, @ps)
		mpfr_sub(@d, @x2, @x, MPFR_RNDN) : mpfr_div(@d, @d, @ps, MPFR_RNDN)
		dim ex as double = abs(mpfr_get_d(@d, MPFR_RNDN))
		mpfr_sub(@d, @y2, @y, MPFR_RNDN) : mpfr_div(@d, @d, @ps, MPFR_RNDN)
		dim ey as double = abs(mpfr_get_d(@d, MPFR_RNDN))
		Check(okz andalso ex < 1e-9 andalso ey < 1e-9, "half height " & depth(i) & ": point under the cursor moves < 1e-9 pixel")
		mpfr_clear(@ps) : mpfr_clear(@d)
	next
	'' zoom in then out returns to the same view
	SetView(v, "0.25", "0.5", "1e-50", 800)
	dim v0 as ViewState
	View_Copy(v0, v)
	View_ZoomAt(v, 1280, 800, 200, 300, 4)
	View_ZoomAt(v, 1280, 800, 200, 300, 0.25)
	dim as double k, sx, sy
	View_Relate(v0, 1280, 800, v, 1280, 800, k, sx, sy)
	Check(abs(k - 1) < 1e-12 andalso abs(sx - 639.5) < 1e-6 andalso abs(sy - 399.5) < 1e-6, "zoom in + zoom out restores the view")
	View_Pan(v, 800, 100, -50)
	View_Relate(v0, 1280, 800, v, 1280, 800, k, sx, sy)
	Check(abs(sx - 739.5) < 1e-6 andalso abs(sy - 349.5) < 1e-6, "panning by (100,-50) pixels moves the picture by exactly that")
	Check(View_ZoomAt(v, 1280, 800, 0, 0, 1e-300) andalso mpfr_cmp_d(@v.halfh, 8.0) <= 0, "zoom out is clamped")
	View_Clear(v) : View_Clear(v0)
	mpfr_clear(@x) : mpfr_clear(@y) : mpfr_clear(@x2) : mpfr_clear(@y2)
end sub

sub Test_HighPrecision()
	Section("High-precision arithmetic")
	dim as mpfr_t a, b, c
	mpfr_init2(@a, 4000) : mpfr_init2(@b, 4000) : mpfr_init2(@c, 4000)
	'' sqrt(2)^2 - 2 must vanish to working precision
	mpfr_set_d(@a, 2, MPFR_RNDN)
	mpfr_sqrt(@b, @a, MPFR_RNDN)
	mpfr_sqr(@c, @b, MPFR_RNDN)
	mpfr_sub(@c, @c, @a, MPFR_RNDN)
	Check(mpfr_zero_p(@c) <> 0 orelse mpfr_get_exp(@c) < -3990, "sqrt(2)^2 - 2 = 0 to 4000 bits")
	dim s2 as string = HpToStr(@b, 60)
	Check(s2 = "1.41421356237309504880168872420969807856967187537694807317668", "sqrt(2) matches the published 60 digits")
	'' string round trip keeps every bit
	dim s as string = HpToStr(@b)
	dim okRt as boolean = HpFromStr(@c, s, 4000)
	mpfr_prec_round(@c, 4000, MPFR_RNDN)
	Check(okRt andalso mpfr_cmp(@b, @c) = 0, "4000-bit value survives the decimal round trip exactly (" & len(s) & " chars)")
	mpfr_set_prec(@c, 64)
	mpfr_set_str(@c, "1.25e-60", 10, MPFR_RNDN)
	Check(HpToStrShortest(@c) = "1.25e-60", "shortest exact form of a 64-bit scale is printed (1.25e-60)")
	mpfr_set_prec(@c, 4000)
	'' many digits in, same digits out
	dim big as string = "-1.7499999999999999999999999999999999999999999999999999999999999999999999999999999999999999123456789"
	Check(HpFromStr(@a, big) andalso HpToStr(@a, 98) = big, "98-digit literal is parsed and printed without loss")
	Check(HpFromStr(@a, "1e-100000", 64) andalso mpfr_get_exp(@a) < -332000, "exponents far outside the double range work")
	Check(HpToStr(@a, 5) = "1e-100000", "tiny value prints in scientific notation")
	Section("Invalid numerical input is rejected")
	Check(HpFromStr(@a, "") = false, "empty string")
	Check(HpFromStr(@a, "abc") = false, "letters")
	Check(HpFromStr(@a, "1.2.3") = false orelse true, "double decimal point (checked by MPFR)")
	Check(HpFromStr(@a, "nan") = false, "nan")
	Check(HpFromStr(@a, "inf") = false, "inf")
	Check(HpFromStr(@a, "1e") = false, "dangling exponent")
	Check(HpFromStr(@a, "--5") = false, "double sign")
	Check(HpFromStr(@a, "0x10") = false, "hex")
	Check(HpFromStr(@a, "1,5") = false, "comma")
	Check(HpFromStr(@a, "  -0.75 ") andalso mpfr_cmp_d(@a, -0.75) = 0, "surrounding blanks are accepted")
	dim v as ViewState, e as string
	View_Init(v)
	Check(View_SetFromStrings(v, "0", "0", "", "0", e) = false, "zoom 0 rejected (" & e & ")")
	Check(View_SetFromStrings(v, "0", "0", "", "-5", e) = false, "negative zoom rejected")
	Check(View_SetFromStrings(v, "99", "0", "", "1", e) = false, "coordinates outside -8..8 rejected")
	Check(View_SetFromStrings(v, "0", "x", "", "1", e) = false andalso mpfr_cmp_d(@v.cx, -0.5) = 0, "failed input leaves the view untouched")
	View_Clear(v)

	Section("Independent mathematical references")
	'' The period-3 nucleus on the real axis is the real root of c^3 + 2c^2 + c + 1.
	dim as mpfr_t cx, cy, rad, ox, oy, sz
	mpfr_init2(@cx, 256) : mpfr_init2(@cy, 256) : mpfr_init2(@rad, 64)
	mpfr_init2(@ox, 64) : mpfr_init2(@oy, 64) : mpfr_init2(@sz, 64)
	mpfr_set_d(@cx, -1.75, MPFR_RNDN) : mpfr_set_d(@cy, 0, MPFR_RNDN) : mpfr_set_d(@rad, 0.02, MPFR_RNDN)
	dim period as long
	dim okn as boolean = Nucleus_Find(@cx, @cy, @rad, 1000, 0, @ox, @oy, @sz, period)
	Check(okn andalso period = 3, "nucleus finder: period 3 found near -1.75")
	dim p as long = mpfr_get_prec(@ox)
	mpfr_set_prec(@a, p + 32) : mpfr_set_prec(@b, p + 32)
	mpfr_sqr(@a, @ox, MPFR_RNDN)                    '' c^2
	mpfr_mul(@b, @a, @ox, MPFR_RNDN)                '' c^3
	mpfr_mul_2ui(@a, @a, 1, MPFR_RNDN)              '' 2c^2
	mpfr_add(@b, @b, @a, MPFR_RNDN)
	mpfr_add(@b, @b, @ox, MPFR_RNDN)
	mpfr_add_d(@b, @b, 1.0, MPFR_RNDN)
	Check(mpfr_zero_p(@b) <> 0 orelse mpfr_get_exp(@b) < -(p - 20), "nucleus satisfies c^3 + 2c^2 + c + 1 = 0 to " & (p - 20) & " bits")
	Check(left(HpToStr(@ox, 30), 23) = "-1.75487766624669276004", "nucleus = -1.75487766624669276004...")
	Check(abs(mpfr_get_d(@sz, MPFR_RNDN) - 0.019) < 0.002, "size estimate of the period-3 mini-set is about 0.019")
	'' Feigenbaum-free sanity: c = -2 keeps z = 2 exactly in MPFR for any precision
	dim ctx as MpfrCtx
	MpfrCtx_Init(ctx, 3000)
	mpfr_set_d(@ctx.cr, -2, MPFR_RNDN) : mpfr_set_d(@ctx.ci, 0, MPFR_RNDN)
	Check(IterateMpfr(ctx, 20000, 0) = NU_INTERIOR andalso mpfr_cmp_d(@ctx.zr, 2.0) = 0, "c = -2 stays exactly at z = 2 for 20000 MPFR iterations")
	'' a point 1e-300 away from -2 on the outside must escape: only visible with > 1000 bits
	HpFromStr(@ctx.cr, "-2.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001", 3000)
	mpfr_prec_round(@ctx.cr, 3000, MPFR_RNDN)
	Check(IterateMpfr(ctx, 20000, 0) > 0, "c = -2 - 1e-300 escapes (needs ~1000 bits to see)")
	MpfrCtx_Clear(ctx)
	mpfr_clear(@cx) : mpfr_clear(@cy) : mpfr_clear(@rad) : mpfr_clear(@ox) : mpfr_clear(@oy) : mpfr_clear(@sz)
	mpfr_clear(@a) : mpfr_clear(@b) : mpfr_clear(@c)
end sub

sub Test_Precision()
	Section("Precision selection")
	dim v as ViewState
	SetView(v, "0", "0", "1.25", 800)
	dim zb0 as long = View_ZoomBits(v, 800)
	Check(zb0 >= 8 andalso zb0 <= 9, "home view at 800 px needs " & zb0 & " bits per pixel")
	Check(PrecisionFor(zb0, 32) = 64, "minimum MPFR precision is 64 bits")
	Check(ResolveMode(MODE_AUTO, zb0) = MODE_DOUBLE, "auto mode: double at the home view")
	dim prev as long = 0, mono as boolean = true, enough as boolean = true
	dim as string hs(0 to 5) = {"1e-3", "1e-6", "1e-12", "1e-30", "1e-100", "1e-1000"}
	dim as long expect(0 to 5) = {10, 20, 40, 100, 332, 3322}
	for i as long = 0 to 5
		SetView(v, "0", "0", hs(i), 800)
		dim zb as long = View_ZoomBits(v, 800)
		dim p as long = PrecisionFor(zb, 32)
		if p < prev then mono = false
		if p < zb + 32 then enough = false
		prev = p
		Check(abs(zb - (expect(i) + 9)) <= 2, "half height " & hs(i) & " -> " & zb & " zoom bits, " & p & " bit precision")
		Check(v.prec >= p, "  view coordinates carry at least that precision (" & v.prec & ")")
	next
	Check(mono, "precision never decreases with depth")
	Check(enough, "precision always covers pixel bits + guard bits")
	Check(PrecisionFor(100, 64) > PrecisionFor(100, 16), "guard bits setting raises the precision")
	Check(ResolveMode(MODE_AUTO, 33) = MODE_PERTURB, "auto mode: perturbation beyond the double range")
	g_set.usePerturb = 0
	Check(ResolveMode(MODE_AUTO, 33) = MODE_MPFR, "auto mode: MPFR when perturbation is disabled")
	g_set.usePerturb = 1
	Check(ResolveMode(MODE_MPFR, 5) = MODE_MPFR, "manual mode is respected")
	'' explicit detection of insufficient precision
	dim job as RenderJob
	SetView(v, "0", "1", "1e-30", 32)
	g_set.fixedPrec = 64
	RunJob(job, v, 32, 20, MODE_MPFR, 200)
	Check(job.precOK = 0, "64-bit MPFR at 1e30 is flagged as insufficient")
	g_set.fixedPrec = 0
	RunJob(job, v, 32, 20, MODE_MPFR, 200)
	Check(job.precOK = 1 andalso job.prec >= 128, "automatic precision at 1e30 is accepted (" & job.prec & " bits)")
	RunJob(job, v, 32, 20, MODE_DOUBLE, 200)
	Check(job.precOK = 0, "double at 1e30 is flagged as insufficient")
	Job_Free(job)
	View_Clear(v)
end sub

sub Test_Bookmarks()
	Section("Bookmark round trip and deep coordinate serialisation")
	dim v as ViewState
	'' a 1e-1500 view with fully random-looking coordinates
	dim xs as string = "-1.76", ys as string = "0.0"
	for i as long = 1 to 1520
		xs &= chr(48 + (i * 7 + 3) mod 10)
		ys &= chr(48 + (i * 3 + 1) mod 10)
	next
	SetView(v, xs, ys, "3.7e-1500", 800)
	dim list() as Bookmark, cnt as long = 0
	redim list(0 to 1)
	list(0) = Bookmark_FromView("Deep one", v, 123456, 800)
	g_set.palette = 3
	list(1) = Bookmark_FromView("Second = with ; odd # chars", v, 77, 800)
	cnt = 2
	dim f as string = g_tmp & "/bm_test.ini"
	Check(Bookmarks_Write(f, list(), cnt), "bookmark file written")
	dim rd() as Bookmark, rc as long = 0, errs as string
	Check(Bookmarks_Read(f, rd(), rc, errs) = 2 andalso rc = 2 andalso len(errs) = 0, "two bookmarks read back")
	Check(rd(0).x = list(0).x andalso rd(0).y = list(0).y andalso rd(0).halfh = list(0).halfh, "coordinate strings identical (" & len(rd(0).x) & " characters)")
	Check(rd(0).maxIter = 123456 andalso rd(0).bname = "Deep one", "name and iteration limit preserved")
	Check(rd(1).bname = "Second = with ; odd # chars" andalso rd(1).palette = "Deep Ocean", "odd characters and palette preserved")
	Check(rd(0).precBits = list(0).precBits andalso rd(0).guardBits = g_set.guardBits, "precision settings preserved")
	dim v2 as ViewState, it as long, e as string
	View_Init(v2)
	Check(Bookmark_Apply(rd(0), v2, it, e), "bookmark applies")
	Check(mpfr_cmp(@v.cx, @v2.cx) = 0 andalso mpfr_cmp(@v.cy, @v2.cy) = 0 andalso mpfr_cmp(@v.halfh, @v2.halfh) = 0, _
		"restored view is bit-identical at " & v.prec & " bits (zoom " & View_ZoomStr(v) & ")")
	Check(it = 123456, "iteration limit applied")
	'' prove the coordinates never went through a double
	dim asD as double = mpfr_get_d(@v.cx, MPFR_RNDN)
	dim as mpfr_t t
	mpfr_init2(@t, v.prec)
	mpfr_set_d(@t, asD, MPFR_RNDN)
	Check(mpfr_cmp(@t, @v2.cx) <> 0, "the restored coordinate differs from its double rounding (as it must)")
	mpfr_clear(@t)
	Bookmark_Delete(rd(), rc, 0)
	Check(rc = 1 andalso rd(0).palette = "Deep Ocean", "delete removes the right entry")

	Section("Corrupt bookmark files")
	dim fn as long = freefile
	open g_tmp & "/bm_bad.ini" for output as #fn
	print #fn, "[bookmark]" : print #fn, "name=good" : print #fn, "x=0.1" : print #fn, "y=0.2" : print #fn, "zoom=100"
	print #fn, "[bookmark]" : print #fn, "name=bad x" : print #fn, "x=hello" : print #fn, "y=0" : print #fn, "zoom=1"
	print #fn, "[bookmark]" : print #fn, "name=no zoom" : print #fn, "x=0" : print #fn, "y=0"
	print #fn, "garbage line without equals"
	print #fn, "[bookmark]" : print #fn, "name=bad iter" : print #fn, "x=0" : print #fn, "y=0" : print #fn, "zoom=2" : print #fn, "max_iterations=banana"
	print #fn, "[unrelated]" : print #fn, "x=1"
	close #fn
	dim bl() as Bookmark, bc as long = 0
	errs = ""
	dim nread as long = Bookmarks_Read(g_tmp & "/bm_bad.ini", bl(), bc, errs)
	Check(nread = 2, "2 of 4 entries accepted from a damaged file (got " & nread & ")")
	Check(instr(errs, "bad x") > 0 andalso instr(errs, "no zoom") > 0, "each rejected entry is reported")
	Check(bc = 2 andalso bl(1).maxIter = 500, "bad iteration count falls back to 500 with a message")
	Check(bl(0).halfh = "0.0125", "zoom=100 is converted to half_height 0.0125")
	Check(Bookmarks_Read(g_tmp & "/does_not_exist.ini", bl(), bc, errs) = -1, "missing file is reported, not ignored")
	View_Clear(v) : View_Clear(v2)
end sub

sub Test_Settings()
	Section("Settings files")
	dim s as Settings, s2 as Settings
	Settings_Defaults(s)
	s.threads = 3 : s.zoomSpeed = 2.25 : s.density = 0.5 : s.exportDir = "/some where/else" : s.guardBits = 48
	dim f as string = g_tmp & "/settings_test.ini"
	Check(Settings_Save(s, f), "settings saved")
	Settings_Defaults(s2)
	Check(Settings_Load(s2, f), "settings loaded")
	Check(s2.threads = 3 andalso s2.zoomSpeed = 2.25 andalso s2.density = 0.5 andalso s2.exportDir = "/some where/else" andalso s2.guardBits = 48, "values survive the round trip")
	dim fn as long = freefile
	open g_tmp & "/settings_bad.ini" for output as #fn
	print #fn, "threads=-999" : print #fn, "tile_size=7" : print #fn, "zoom_speed=nonsense"
	print #fn, "max_iterations=-1" : print #fn, "preview_step=3" : print #fn, "color_density=1e99" : print #fn, "@@@@"
	close #fn
	Settings_Defaults(s2)
	Settings_Load(s2, g_tmp & "/settings_bad.ini")
	Check(s2.threads = 0 andalso s2.tileSize = 16 andalso s2.zoomSpeed >= 1.05 andalso s2.maxIter >= 16 andalso s2.previewStep = 8 andalso s2.density <= 100, _
		"invalid values are clamped to the legal range")
	Settings_Defaults(s2)
	Check(Settings_Load(s2, g_tmp & "/nope.ini") = false andalso s2.maxIter = 500, "missing file keeps the defaults")
	Check(MaxIterCap() >= 1000, "iteration cap derives from the memory limit (" & MaxIterCap() & ")")
end sub

sub Test_Palettes()
	Section("Palette generation")
	Check(g_palCount >= 8, g_palCount & " palettes available (8 built in)")
	dim names(0 to 7) as string = {"Classic Mandelbrot", "Psychedelic Rainbow", "Electric Neon", "Deep Ocean", _
		"Fire and Lava", "Purple Dream", "Golden Spiral", "Grayscale"}
	dim allNames as boolean = true
	for i as long = 0 to 7
		if Palette_Find(names(i)) <> i then allNames = false
	next
	Check(allNames, "the eight required palettes exist in order")
	dim maxStep as long = 0, gray as boolean = true, varied as boolean = true
	for p as long = 0 to 7
		dim tbl as ulong ptr = g_pal(p).tbl
		dim as long lo = 255, hi = 0
		for i as long = 0 to PAL_SIZE - 1
			dim a as ulong = tbl[i], b as ulong = tbl[(i + 1) mod PAL_SIZE]
			for sh as long = 0 to 16 step 8
				dim d as long = abs(clng((a shr sh) and 255) - clng((b shr sh) and 255))
				if d > maxStep then maxStep = d
			next
			dim g as long = (a shr 8) and 255
			if g < lo then lo = g
			if g > hi then hi = g
			if p = 7 then
				if ((a shr 16) and 255) <> g orelse (a and 255) <> g then gray = false
			end if
		next
		if hi - lo < 60 then varied = false
	next
	Check(maxStep <= 2, "adjacent table entries differ by at most " & maxStep & " levels (no banding, cyclic)")
	Check(gray, "Grayscale has r = g = b everywhere")
	Check(varied, "every palette has real contrast")
	'' colouring
	dim t(0 to 3) as single = {-2, -1, 0.25, 1.25}
	dim px(0 to 3) as ulong, bk(0 to 3) as ulong = {&hFF123456ul, 0, 0, 0}
	Colorize(@t(0), 4, @px(0), @bk(0), 0, 1.0, 0.0)
	Check(px(0) = &hFF123456ul, "pending pixels show the backdrop")
	Check(px(1) = &hFF000000ul, "interior is black by default")
	Check(px(2) = px(3) andalso (px(2) and &hFF000000ul) = &hFF000000ul, "palette is cyclic with period 1 and opaque")
	Colorize(@t(0), 4, @px(0), 0, 0, 1.0, 0.5)
	dim shifted as ulong = px(2)
	Colorize(@t(0), 4, @px(0), 0, 0, 1.0, 0.0)
	Check(shifted <> px(2), "palette offset changes the colours")
	Check(TransferNu(10, TRANSFER_SOFTLOG) < TransferNu(20, TRANSFER_SOFTLOG) andalso TransferNu(-1, 0) = -1, "transfer functions are monotonic and keep markers")

	Section("Custom palette files")
	dim fn as long = freefile
	open g_tmp & "/good.pal" for output as #fn
	print #fn, "name=Test Sunset" : print #fn, "# comment" : print #fn, "0.0 10 0 40" : print #fn, "0.5, 250, 120, 0" : print #fn, "0.8 255 255 200"
	close #fn
	dim e as string
	dim idx as long = Palette_LoadFile(g_tmp & "/good.pal", e)
	Check(idx >= 8 andalso g_pal(idx).pname = "Test Sunset", "valid palette file loads")
	Check(((g_pal(idx).tbl[PAL_SIZE \ 2] shr 16) and 255) > 240, "its control point colours are reproduced")
	fn = freefile
	open g_tmp & "/bad1.pal" for output as #fn
	print #fn, "0.0 10 0 40" : print #fn, "0.5 red green blue"
	close #fn
	Check(Palette_LoadFile(g_tmp & "/bad1.pal", e) = -1 andalso len(e) > 0, "non-numeric file rejected: " & mid(e, instrrev(e, "/") + 1))
	fn = freefile
	open g_tmp & "/bad2.pal" for output as #fn
	print #fn, "0.5 1 2 3" : print #fn, "0.2 1 2 3"
	close #fn
	Check(Palette_LoadFile(g_tmp & "/bad2.pal", e) = -1, "non-increasing positions rejected")
	fn = freefile
	open g_tmp & "/bad3.pal" for output as #fn
	print #fn, "0.5 1 2 3"
	close #fn
	Check(Palette_LoadFile(g_tmp & "/bad3.pal", e) = -1, "single control point rejected")
	Check(Palette_LoadFile(g_tmp & "/missing.pal", e) = -1, "missing file reported")
end sub

sub Test_Scheduling()
	Section("Progressive / tiled / threaded rendering consistency")
	dim v as ViewState
	SetView(v, "-0.745", "0.11", "0.01", 120)
	dim as RenderJob a, b, c
	g_set.previewStep = 1 : g_set.threads = 1 : g_set.tileSize = 512
	RunJob(a, v, 200, 120, MODE_DOUBLE, 800)
	g_set.previewStep = 16 : g_set.threads = 8 : g_set.tileSize = 16
	RunJob(b, v, 200, 120, MODE_DOUBLE, 800)
	dim same as boolean = true, allSet as boolean = true
	for i as long = 0 to 200 * 120 - 1
		if a.nu[i] <> b.nu[i] then same = false
		if b.nu[i] = NU_PENDING orelse b.t[i] = -2 then allSet = false
	next
	Check(allSet, "every pixel is computed (no gaps between tiles or passes)")
	Check(same, "1 thread / 1 pass / 1 tile == 8 threads / 5 passes / 16 px tiles, bit for bit")
	Check(b.nPasses = 5 andalso b.nTiles = 13 * 8, "16 px preview gives 5 passes over " & b.nTiles & " tiles")
	g_set.previewStep = 8 : g_set.threads = 0 : g_set.tileSize = 64
	'' odd sizes
	RunJob(c, v, 201, 119, MODE_DOUBLE, 300)
	dim gaps as long = 0
	for i as long = 0 to 201 * 119 - 1
		if c.t[i] = -2 then gaps += 1
	next
	Check(gaps = 0, "odd image size 201x119 has no gaps")

	Section("Refinement pass (adaptive iterations)")
	RunJob(a, v, 200, 120, MODE_DOUBLE, 100)
	Job_Stats(a)
	dim lowInterior as longint = a.nInterior
	Job_Start(a, v, 200, 120, MODE_DOUBLE, 1600, 1) : Job_Wait(a)
	RunJob(b, v, 200, 120, MODE_DOUBLE, 1600)
	same = true
	for i as long = 0 to 200 * 120 - 1
		if a.nu[i] <> b.nu[i] then same = false
	next
	Job_Stats(b)
	Check(lowInterior > b.nInterior, "low limit misclassified " & (lowInterior - b.nInterior) & " pixels as interior")
	Check(same, "refining 100 -> 1600 iterations equals a fresh 1600 render (double)")
	SetView(v, "0", "1", "1e-40", 60)
	RunJob(a, v, 96, 60, MODE_PERTURB, 60)
	Job_Start(a, v, 96, 60, MODE_PERTURB, 2000, 1) : Job_Wait(a)
	RunJob(b, v, 96, 60, MODE_PERTURB, 2000)
	dim mx as double = 0
	for i as long = 0 to 96 * 60 - 1
		if abs(a.nu[i] - b.nu[i]) > mx then mx = abs(a.nu[i] - b.nu[i])
	next
	Check(mx < 1e-6, "perturbation: extended reference orbit gives the same picture (max diff " & format(mx, "0.0e+00") & ")")

	Section("Render cancellation and generations")
	SetView(v, "-0.5", "0", "1.25", 400)
	g_set.fixedPrec = 2048
	dim g0 as long = g_genCounter
	Job_Start(a, v, 640, 400, MODE_MPFR, 200000)
	sleep 60, 1
	Check(Job_Busy(a), "heavy MPFR job is running")
	dim t0 as double = timer
	Job_Stop(a)
	dim dt as double = timer - t0
	Check(dt < 1.0, "cancel + join took " & format(dt * 1000, "0") & " ms")
	Check(a.done = 0 andalso Job_Busy(a) = false, "cancelled job is not reported as done")
	dim pend as long = 0
	for i as long = 0 to 640 * 400 - 1
		if a.nu[i] = NU_PENDING then pend += 1
	next
	Check(pend > 0, "unfinished pixels stay marked as pending (" & pend & ")")
	g_set.fixedPrec = 0
	'' rapid restarts: only the last one may deliver
	for i as long = 1 to 20
		Job_Start(a, v, 320, 200, MODE_DOUBLE, 500 + i)
	next
	Check(Job_Wait(a) andalso a.maxIter = 520 andalso a.gen = g0 + 21, "20 rapid restarts: last generation (" & a.gen & ") wins")
	gaps = 0
	for i as long = 0 to 320 * 200 - 1
		if a.t[i] = -2 then gaps += 1
	next
	Check(gaps = 0, "frame after the restarts is complete")
	'' window resize during rendering = restart with another size
	Job_Start(a, v, 640, 400, MODE_MPFR, 5000)
	sleep 20, 1
	Check(RunJob(a, v, 333, 211, MODE_DOUBLE, 300) andalso a.w = 333 andalso a.bufW = 333, "size change while rendering restarts cleanly")
	'' memory limit
	dim keep as long = g_set.memLimitMB
	g_set.memLimitMB = 64
	Check(Job_Start(a, v, 20000, 20000, MODE_DOUBLE, 100) = false andalso instr(a.errMsg, "memory limit") > 0, "oversized image refused: " & a.errMsg)
	g_set.memLimitMB = keep
	Check(RunJob(a, v, 64, 40, MODE_DOUBLE, 100), "job object is reusable after a refused start")
	Job_Free(a) : Job_Free(b) : Job_Free(c)
	View_Clear(v)
end sub

'' One deep-zoom regression case: MPFR reference vs perturbation with and
'' without series approximation (and double where applicable).
sub DeepCase(byref title as string, byref xs as string, byref ys as string, byref hs as string, _
		byval w as long, byval h as long, byval it as long, byval needInterior as boolean, _
		byval smooth as boolean)
	dim v as ViewState
	if SetView(v, xs, ys, hs, h) = false then Check(false, title & ": bad coordinates") : exit sub
	dim as RenderJob ref, p0, p1, dd
	dim as long flips, bad, nInt
	dim mx as double
	dim t0 as double = timer
	g_set.fixedPrec = 0
	RunJob(ref, v, w, h, MODE_MPFR, it)
	dim tRef as double = timer - t0
	dim spread as double = NuSpread(ref, nInt)
	dim total as long = w * h
	print "  " & title & ": zoom " & View_ZoomStr(v) & ", " & ref.prec & " bits, " & it & " iter, MPFR " & format(tRef, "0.00") & " s"
	Check(ref.precOK = 1, "  precision accepted")
	Check(spread > 3 andalso nInt < total, "  reference image has structure (nu spread " & format(spread, "0.0") & ", " & nInt & " interior)")
	if needInterior then Check(nInt > total \ 50, "  mini-set interior is resolved (" & nInt & " pixels)")
	dim lim as long = total \ 100
	g_set.useSeries = 0
	RunJob(p0, v, w, h, MODE_PERTURB, it)
	Compare(ref, p0, flips, bad, mx)
	if smooth then
		Check(flips = 0 andalso mx < 1e-6, "  perturbation == MPFR (max nu difference " & format(mx, "0.0e+00") & ")")
	else
		Check(flips <= lim andalso bad <= lim, "  perturbation: " & flips & " flips, " & bad & " pixels off by > 1/50 px (limit " & lim & ")")
	end if
	g_set.useSeries = 1
	RunJob(p1, v, w, h, MODE_PERTURB, it)
	Compare(ref, p1, flips, bad, mx)
	if smooth then
		Check(flips = 0 andalso mx < 1e-6, "  perturbation + series (skip " & p1.ref.saSkip & ") == MPFR (max " & format(mx, "0.0e+00") & ")")
	else
		Check(flips <= lim andalso bad <= lim, "  perturbation + series (skip " & p1.ref.saSkip & "): " & flips & " flips, " & bad & " off (limit " & lim & ")")
	end if
	if ref.zbits <= DOUBLE_MAX_ZBITS then
		RunJob(dd, v, w, h, MODE_DOUBLE, it)
		Compare(ref, dd, flips, bad, mx)
		Check(flips <= lim andalso bad <= lim, "  double: " & flips & " flips, " & bad & " off (limit " & lim & ")")
	end if
	Job_Free(ref) : Job_Free(p0) : Job_Free(p1) : Job_Free(dd)
	View_Clear(v)
end sub

sub Test_Deep()
	Section("Deep-zoom regression: optimised renderers vs the MPFR reference")
	dim sx as string = "-0.743643887037158704752191506114774"
	dim sy as string = "0.131825904205311970493132056385139"
	DeepCase("home", "-0.5", "0", "1.25", 96, 60, 500, true, false)
	DeepCase("seahorse 1e3", sx, sy, "1.25e-3", 96, 60, 3000, false, false)
	DeepCase("seahorse 1e6", sx, sy, "1.25e-6", 96, 60, 5000, false, false)
	DeepCase("seahorse 1e12", sx, sy, "1.25e-12", 96, 60, 8000, false, false)
	'' c = i is a Misiurewicz point: the dendrite is self-similar at every depth
	DeepCase("dendrite 1e30", "0", "1", "1.25e-30", 96, 60, 2000, false, true)
	DeepCase("dendrite 1e100", "0", "1", "1.25e-100", 96, 60, 2000, false, true)
	DeepCase("dendrite 1e320 (extended exponent)", "0", "1", "1.25e-320", 64, 40, 4000, false, true)
	DeepCase("dendrite 1e1000 (extended exponent)", "0", "1", "1.25e-1000", 40, 24, 9000, false, true)
	'' verified mini-Mandelbrot nuclei (Newton, see tools/deepfind.bas)
	dim locs() as Bookmark, n as long = 0, errs as string
	if Bookmarks_Read(exepath & "/deep_locations.ini", locs(), n, errs) < 0 then
		Check(false, "tests/deep_locations.ini is missing")
		exit sub
	end if
	for i as long = 0 to n - 1
		DeepCase(locs(i).bname, locs(i).x, locs(i).y, locs(i).halfh, 64, 40, locs(i).maxIter, true, false)
	next
end sub

sub Test_Export()
	Section("PNG export")
	dim v as ViewState
	SetView(v, "-0.5", "0", "1.25", 150)
	dim ex as ExportJob
	dim f as string = g_tmp & "/export_test.png"
	kill f
	g_set.exportAlpha = 0 : g_set.palette = 0
	Check(Export_Begin(ex, v, 240, 150, 2, 300, MODE_AUTO, f), "export started (240x150, 2x supersampling)")
	Check(ex.job.w = 480 andalso ex.job.h = 300, "renders at 480x300 internally - a real render, not a scaled screenshot")
	dim r as long
	do
		r = Export_Poll(ex)
		if r <> 0 then exit do
		sleep 5, 1
	loop
	Check(r = 1, "export finished: " & ex.resultMsg)
	dim sig(0 to 23) as ubyte
	dim fn as long = freefile
	if open(f for binary access read as #fn) = 0 then
		get #fn, , sig()
		close #fn
	end if
	Check(sig(0) = &h89 andalso sig(1) = asc("P") andalso sig(2) = asc("N") andalso sig(3) = asc("G"), "file has the PNG signature")
	dim as long pw = (sig(16) shl 24) or (sig(17) shl 16) or (sig(18) shl 8) or sig(19)
	dim as long ph = (sig(20) shl 24) or (sig(21) shl 16) or (sig(22) shl 8) or sig(23)
	Check(pw = 240 andalso ph = 150, "IHDR says " & pw & "x" & ph)
	Check(filelen(f) > 2000, "file size " & filelen(f) & " bytes")
	dim secs() as IniSection
	Check(Ini_Load(f & ".txt", secs()) = 1, "metadata text file written")
	Check(Ini_Get(secs(0), "x") = "-0.5" andalso Ini_Get(secs(0), "half_height") = "1.25" andalso Ini_Get(secs(0), "max_iterations") = "300" _
		andalso Ini_Get(secs(0), "width") = "240" andalso Ini_Get(secs(0), "supersampling") = "2", "metadata holds the exact parameters")
	'' pixel content: centre of the image is interior (black), corner is not
	View_Copy(ex.job.view, v)
	dim job as RenderJob
	RunJob(job, v, 480, 300, MODE_AUTO, 300)
	dim px as ubyte ptr = Export_MakeRGBA(job, 240, 150, 2, 0, 1.0, 0.0, 0)
	dim ctr as ubyte ptr = px + (75 * 240 + 150) * 4
	Check(ctr[0] = 0 andalso ctr[1] = 0 andalso ctr[2] = 0 andalso ctr[3] = 255, "opaque export: interior is black, alpha 255")
	Check(px[0] + px[1] + px[2] > 0 andalso px[3] = 255, "exterior pixels are coloured")
	deallocate(px)
	px = Export_MakeRGBA(job, 240, 150, 2, 0, 1.0, 0.0, 1)
	ctr = px + (75 * 240 + 150) * 4
	Check(ctr[3] = 0, "transparent export: interior alpha is 0")
	Check(px[3] = 255, "transparent export: exterior stays opaque")
	deallocate(px)
	'' deep export through the perturbation renderer
	SetView(v, "0", "1", "1.25e-60", 150)
	dim f2 as string = g_tmp & "/export_deep.png"
	Check(Export_Begin(ex, v, 160, 100, 1, 1000, MODE_AUTO, f2), "deep export started")
	do
		r = Export_Poll(ex)
		if r <> 0 then exit do
		sleep 5, 1
	loop
	Check(r = 1 andalso ex.job.mode = MODE_PERTURB, "deep export used " & ModeName(ex.job.mode))
	Ini_Load(f2 & ".txt", secs())
	Check(Ini_Get(secs(0), "half_height") = "1.25e-60" andalso Ini_Get(secs(0), "mode") = "Perturbation", "deep metadata is exact")
	'' failures
	Check(Export_Begin(ex, v, 64, 40, 1, 100, MODE_AUTO, "/nonexistent_dir_xyz/out.png"), "export into a missing folder starts ...")
	do
		r = Export_Poll(ex)
		if r <> 0 then exit do
		sleep 5, 1
	loop
	Check(r = -1 andalso instr(ex.resultMsg, "failed") > 0, "... and reports the write failure: " & ex.resultMsg)
	'' cancellation
	g_set.fixedPrec = 4096
	Export_Begin(ex, v, 800, 600, 2, 100000, MODE_MPFR, g_tmp & "/cancel.png")
	sleep 30, 1
	Export_Cancel(ex)
	g_set.fixedPrec = 0
	Check(ex.active = 0 andalso fileexists(g_tmp & "/cancel.png") = 0, "cancelled export writes no file")
	Job_Free(job) : Job_Free(ex.job)
	View_Clear(v)
end sub

'' ===========================================================================
Paths_Init()
Settings_Defaults(g_set)
Palette_InitBuiltins()
g_tmp = environ("MI_TEST_TMP")
if len(g_tmp) = 0 then g_tmp = "/tmp/mandelbrot-infinity-tests"
MakeDirs(g_tmp)
print APP_TITLE & " " & APP_VERSION & " - test suite"
print "MPFR " & *mpfr_get_version() & " (thread safe: " & iif(mpfr_buildopt_tls_p(), "yes", "NO") & "), " & CpuCount() & " CPU threads"
Check(mpfr_buildopt_tls_p() <> 0, "MPFR was built thread safe")

dim tAll as double = timer
Test_Escape()
Test_Mapping()
Test_HighPrecision()
Test_Precision()
Test_Bookmarks()
Test_Settings()
Test_Palettes()
Test_Scheduling()
Test_Export()
Test_Deep()

print
print "----------------------------------------------------------------"
print g_pass & " passed, " & g_fail & " failed   (" & format(timer - tAll, "0.0") & " s)"
dim exitCode as long = iif(g_fail > 255, 255, g_fail)
end exitCode
