'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - colour palettes
''
'' A palette is a cyclic list of control points (position 0..1, r, g, b)
'' expanded into a PAL_SIZE entry lookup table with a cubic Hermite spline,
'' so neighbouring table entries differ by less than one 8-bit step.
'' Eight palettes are built in; more are loaded from *.pal text files.
'' ---------------------------------------------------------------------------
#include once "common.bi"

type Palette
	pname as string
	tbl as ulong ptr          '' PAL_SIZE entries, &h00RRGGBB
end type

dim shared g_pal() as Palette
dim shared g_palCount as long = 0

const MAX_CTRL = 64

private function Hermite(byval p0 as double, byval p1 as double, byval m0 as double, _
		byval m1 as double, byval u as double) as double
	dim u2 as double = u * u, u3 as double = u2 * u
	return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 _
	     + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1
end function

'' Build the lookup table from n control points (positions strictly rising
'' in [0,1)).  The gradient wraps around from the last point to the first.
function Palette_Build(byref pname as string, byval n as long, ps() as double, _
		rgb_() as double) as long
	if n < 2 orelse n > MAX_CTRL then return -1
	redim preserve g_pal(0 to g_palCount)
	dim byref p as Palette = g_pal(g_palCount)
	p.pname = pname
	p.tbl = allocate(PAL_SIZE * sizeof(ulong))
	if p.tbl = 0 then return -1
	for i as long = 0 to PAL_SIZE - 1
		dim x as double = i / PAL_SIZE
		'' find segment k: pos(k) <= x < pos(k+1), cyclic
		dim k as long = n - 1
		for j as long = 0 to n - 1
			if ps(j) <= x then k = j
		next
		if x < ps(0) then k = n - 1
		dim k0 as long = (k - 1 + n) mod n, k1 as long = (k + 1) mod n, k2 as long = (k + 2) mod n
		dim x0 as double = ps(k), x1 as double = ps(k1)
		if k1 <= k then x1 += 1
		dim xm as double = ps(k0)
		if k0 >= k then xm -= 1
		dim xp as double = ps(k2)
		if k2 <= k then xp += 1
		if xp <= x1 then xp += 1
		dim xx as double = x
		if xx < x0 then xx += 1
		dim seg as double = x1 - x0
		dim u as double = (xx - x0) / seg
		dim c(0 to 2) as long
		for ch as long = 0 to 2
			dim a as double = rgb_(k0 * 3 + ch), b as double = rgb_(k * 3 + ch)
			dim c1 as double = rgb_(k1 * 3 + ch), d as double = rgb_(k2 * 3 + ch)
			'' finite difference tangents (non-uniform Catmull-Rom)
			dim m0 as double = (c1 - a) / (x1 - xm) * seg
			dim m1 as double = (d - b) / (xp - x0) * seg
			dim v as double = Hermite(b, c1, m0, m1, u)
			if v < 0 then v = 0
			if v > 255 then v = 255
			c(ch) = clng(v)
		next
		p.tbl[i] = (culng(c(0)) shl 16) or (culng(c(1)) shl 8) or culng(c(2))
	next
	g_palCount += 1
	return g_palCount - 1
end function

private sub AddBuiltin(byref pname as string, byref spec as string)
	'' spec: "pos r g b; pos r g b; ..."
	dim ps(0 to MAX_CTRL - 1) as double, c(0 to MAX_CTRL * 3 - 1) as double
	dim n as long = 0, i as long = 1
	do
		dim j as long = instr(i, spec, ";")
		dim item as string
		if j = 0 then item = mid(spec, i) else item = mid(spec, i, j - i)
		item = trim(item)
		if len(item) > 0 then
			dim v(0 to 3) as double, q as long = 1
			for f as long = 0 to 3
				dim sp as long = instr(q, item, " ")
				if sp = 0 then sp = len(item) + 1
				v(f) = val(mid(item, q, sp - q))
				q = sp + 1
			next
			ps(n) = v(0)
			c(n * 3) = v(1) : c(n * 3 + 1) = v(2) : c(n * 3 + 2) = v(3)
			n += 1
		end if
		if j = 0 then exit do
		i = j + 1
	loop
	Palette_Build(pname, n, ps(), c())
end sub

'' Load one custom palette file.  Format:
''   name=My palette
''   # position  red green blue
''   0.00   0   7 100
''   0.16  32 107 203
'' Returns the palette index or -1 (errMsg set).
function Palette_LoadFile(byref fname as string, byref errMsg as string) as long
	dim f as long = freefile
	if open(fname for input as #f) <> 0 then
		errMsg = "cannot open " & fname
		return -1
	end if
	dim ps(0 to MAX_CTRL - 1) as double, c(0 to MAX_CTRL * 3 - 1) as double
	dim n as long = 0, ln as string, pname as string, lineNo as long = 0
	dim bad as boolean = false
	while not eof(f)
		line input #f, ln
		lineNo += 1
		ln = trim(ln, any " " & chr(9) & chr(13))
		if len(ln) = 0 orelse ln[0] = asc("#") orelse ln[0] = asc(";") then continue while
		if lcase(left(ln, 5)) = "name=" then
			pname = trim(mid(ln, 6))
			continue while
		end if
		'' four whitespace separated numbers
		dim v(0 to 3) as double, cnt as long = 0, q as long = 0
		while q < len(ln) andalso cnt < 4
			while q < len(ln) andalso (ln[q] = 32 orelse ln[q] = 9 orelse ln[q] = asc(","))
				q += 1
			wend
			if q >= len(ln) then exit while
			dim st as long = q
			while q < len(ln) andalso ln[q] <> 32 andalso ln[q] <> 9 andalso ln[q] <> asc(",")
				q += 1
			wend
			dim tok as string = mid(ln, st + 1, q - st)
			dim okNum as boolean = true
			for z as long = 0 to len(tok) - 1
				select case tok[z]
				case asc("0") to asc("9"), asc("."), asc("-"), asc("+"), asc("e"), asc("E")
				case else : okNum = false
				end select
			next
			if okNum = false then cnt = -99 : exit while
			v(cnt) = val(tok)
			cnt += 1
		wend
		if cnt <> 4 orelse n >= MAX_CTRL then
			errMsg = fname & ": bad control point on line " & lineNo
			bad = true
			exit while
		end if
		if v(0) < 0 orelse v(0) >= 1 orelse (n > 0 andalso v(0) <= ps(n - 1)) then
			errMsg = fname & ": positions must rise within [0,1) (line " & lineNo & ")"
			bad = true
			exit while
		end if
		ps(n) = v(0)
		for z as long = 0 to 2
			c(n * 3 + z) = ClampD(v(z + 1), 0, 255)
		next
		n += 1
	wend
	close #f
	if bad then return -1
	if n < 2 then
		errMsg = fname & ": needs at least two control points"
		return -1
	end if
	if len(pname) = 0 then
		pname = fname
		dim sl as long = instrrev(pname, "/")
		if sl > 0 then pname = mid(pname, sl + 1)
	end if
	return Palette_Build(pname, n, ps(), c())
end function

'' Load every *.pal file of a directory.  Returns the number of failures;
'' messages are appended to errs.
function Palette_LoadDir(byref d as string, byref errs as string) as long
	dim fails as long = 0
	dim names() as string, cnt as long = 0
	dim fn as string = dir(d & "/*.pal")
	while len(fn) > 0
		redim preserve names(0 to cnt)
		names(cnt) = fn
		cnt += 1
		fn = dir()
	wend
	'' simple sort so the order is stable
	for i as long = 0 to cnt - 2
		for j as long = i + 1 to cnt - 1
			if names(j) < names(i) then swap names(i), names(j)
		next
	next
	for i as long = 0 to cnt - 1
		dim e as string
		if Palette_LoadFile(d & "/" & names(i), e) < 0 then
			fails += 1
			errs &= e & chr(10)
		end if
	next
	return fails
end function

sub Palette_InitBuiltins()
	if g_palCount > 0 then exit sub
	AddBuiltin("Classic Mandelbrot", _
		"0 0 7 100; 0.16 32 107 203; 0.42 237 255 255; 0.6425 255 170 0; 0.8575 0 2 0")
	AddBuiltin("Psychedelic Rainbow", _
		"0 255 0 0; 0.1667 255 230 0; 0.3333 0 235 40; 0.5 0 220 255; 0.6667 30 40 255; 0.8333 240 0 230")
	AddBuiltin("Electric Neon", _
		"0 5 0 20; 0.14 0 255 200; 0.28 20 0 70; 0.44 255 0 220; 0.58 10 10 50; 0.74 90 255 0; 0.88 0 40 60")
	AddBuiltin("Deep Ocean", _
		"0 0 5 30; 0.25 0 60 125; 0.5 0 165 195; 0.68 190 245 250; 0.85 0 95 155")
	AddBuiltin("Fire and Lava", _
		"0 10 0 0; 0.2 125 0 0; 0.4 235 60 0; 0.58 255 175 0; 0.72 255 250 185; 0.86 205 60 0")
	AddBuiltin("Purple Dream", _
		"0 15 0 40; 0.25 90 20 165; 0.5 200 110 255; 0.68 255 225 255; 0.85 120 40 145")
	AddBuiltin("Golden Spiral", _
		"0 20 10 0; 0.25 125 72 10; 0.5 225 172 40; 0.68 255 242 175; 0.85 142 92 20")
	AddBuiltin("Grayscale", "0 0 0 0; 0.5 255 255 255")
end sub

function Palette_Find(byref pname as string) as long
	for i as long = 0 to g_palCount - 1
		if lcase(g_pal(i).pname) = lcase(pname) then return i
	next
	return -1
end function

'' ---- transfer function and colouring -----------------------------------------

'' Map the smooth iteration value to palette "time".  "nuBase" is the lowest
'' iteration value of the frame: colours follow the distance from it, so a
'' deep-zoom picture (where every pixel needs e.g. 100000+ iterations) keeps
'' the same contrast as a shallow one.
function TransferNu(byval nu as double, byval mode as long, byval nuBase as double = 0) as single
	if nu < 0 then return csng(nu)
	nu -= nuBase
	if nu < 0 then nu = 0
	select case mode
	case TRANSFER_LINEAR
		return csng(nu / 64.0)
	case TRANSFER_SQRT
		return csng(sqr(nu) / 8.0)
	end select
	return csng(1.5 * log(1.0 + nu / 24.0))
end function

'' Colour lookup: &hAARRGGBB with full alpha.
#define PAL_COLOR(tblp, tv, dens, offs) _
	((tblp)[clng(frac(cdbl(tv) * (dens) + (offs)) * PAL_SIZE) and (PAL_SIZE - 1)] or &hFF000000ul)

'' Convert a t() buffer to ARGB pixels.  Pending pixels take the colour of
'' back() when given, otherwise a dark placeholder.
sub Colorize(byval t as single ptr, byval n as longint, byval dst as ulong ptr, _
		byval back as ulong ptr, byval pal as long, byval dens as double, byval offs as double, _
		byval interiorColor as ulong = &hFF000000ul)
	if pal < 0 orelse pal >= g_palCount then pal = 0
	dim tbl as ulong ptr = g_pal(pal).tbl
	for i as longint = 0 to n - 1
		dim tv as single = t[i]
		if tv >= 0 then
			dst[i] = PAL_COLOR(tbl, tv, dens, offs)
		elseif tv = -2 then
			if back then dst[i] = back[i] else dst[i] = &hFF101018ul
		else
			dst[i] = interiorColor
		end if
	next
end sub
