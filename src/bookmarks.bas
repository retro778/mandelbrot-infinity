'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - bookmarks and location presets
''
'' Human readable INI-style files.  Coordinates are stored as decimal
'' strings with every digit of the MPFR value - they never pass through a
'' DOUBLE.  Example:
''
''   [bookmark]
''   name=Seahorse spiral
''   x=-0.743643887037158704752191506114774
''   y=0.131825904205311970493132056385139
''   half_height=1.5e-25          (or: zoom=8.3e24, relative to the home view)
''   max_iterations=5000
''   palette=Classic Mandelbrot
''   precision_bits=160
''   guard_bits=32
''   coordinate_bits=256          (optional: exact binary precision of x / y)
'' ---------------------------------------------------------------------------
#include once "common.bi"

dim shared g_bm() as Bookmark
dim shared g_bmCount as long = 0
dim shared g_loc() as Bookmark
dim shared g_locCount as long = 0

function Bookmarks_File() as string
	return g_userDir & "/bookmarks.ini"
end function

'' Build a bookmark from the live state.
function Bookmark_FromView(byref bname as string, byref v as ViewState, byval maxIter as long, _
		byval hpx as long) as Bookmark
	dim b as Bookmark
	b.bname = bname
	b.x = HpToStr(@v.cx)
	b.y = HpToStr(@v.cy)
	b.halfh = HpToStrShortest(@v.halfh)
	b.coordBits = v.prec
	b.maxIter = maxIter
	if g_set.palette >= 0 andalso g_set.palette < g_palCount then b.palette = g_pal(g_set.palette).pname
	b.precBits = PrecisionFor(View_ZoomBits(v, hpx), g_set.guardBits)
	b.guardBits = g_set.guardBits
	return b
end function

'' Apply a bookmark to the view.  The view is untouched on failure.
function Bookmark_Apply(byref b as Bookmark, byref v as ViewState, byref maxIter as long, _
		byref errMsg as string) as boolean
	if View_SetFromStrings(v, b.x, b.y, b.halfh, "", errMsg) = false then return false
	if b.coordBits >= 64 andalso b.coordBits <= v.prec then
		'' the decimal strings carry a few spare digits: rounding to the
		'' recorded precision restores the original value bit for bit
		mpfr_prec_round(@v.cx, b.coordBits, MPFR_RNDN)
		mpfr_prec_round(@v.cy, b.coordBits, MPFR_RNDN)
		v.prec = b.coordBits
	end if
	if b.precBits > v.prec andalso b.precBits <= 4000000 then View_EnsurePrec(v, b.precBits)
	if b.maxIter >= 2 then maxIter = b.maxIter
	if len(b.palette) > 0 then
		dim p as long = Palette_Find(b.palette)
		if p >= 0 then g_set.palette = p
	end if
	return true
end function

'' Read bookmarks from a file and append them to list().  Corrupt entries
'' are skipped and described in errs.  Returns the number of entries added,
'' or -1 when the file cannot be opened.
function Bookmarks_Read(byref fname as string, list() as Bookmark, byref count as long, _
		byref errs as string) as long
	dim secs() as IniSection
	dim n as long = Ini_Load(fname, secs())
	if n < 0 then return -1
	dim added as long = 0
	dim tmp as ViewState
	View_Init(tmp)
	for i as long = 0 to n - 1
		if secs(i).sname <> "bookmark" andalso secs(i).sname <> "location" then continue for
		dim b as Bookmark
		b.bname = Ini_Get(secs(i), "name", "Unnamed")
		b.x = Ini_Get(secs(i), "x")
		b.y = Ini_Get(secs(i), "y")
		b.halfh = Ini_Get(secs(i), "half_height")
		dim zs as string = Ini_Get(secs(i), "zoom")
		dim e as string
		if View_SetFromStrings(tmp, b.x, b.y, b.halfh, zs, e) = false then
			errs &= "entry '" & b.bname & "' skipped: " & e & chr(10)
			continue for
		end if
		if len(b.halfh) = 0 then b.halfh = HpToStrShortest(@tmp.halfh)
		dim mi as string = Ini_Get(secs(i), "max_iterations", "500")
		b.maxIter = valint(mi)
		if b.maxIter < 2 orelse b.maxIter > 100000000 then
			errs &= "entry '" & b.bname & "': bad max_iterations, using 500" & chr(10)
			b.maxIter = 500
		end if
		b.palette = Ini_Get(secs(i), "palette")
		b.precBits = valint(Ini_Get(secs(i), "precision_bits", "0"))
		b.guardBits = valint(Ini_Get(secs(i), "guard_bits", "0"))
		b.coordBits = valint(Ini_Get(secs(i), "coordinate_bits", "0"))
		redim preserve list(0 to count)
		list(count) = b
		count += 1
		added += 1
	next
	View_Clear(tmp)
	return added
end function

'' Write the list (through a temporary file, so a crash cannot leave a
'' half-written bookmark file behind).
function Bookmarks_Write(byref fname as string, list() as Bookmark, byval count as long, _
		byref secName as string = "bookmark") as boolean
	dim tmpName as string = fname & ".tmp"
	dim f as long = freefile
	if open(tmpName for output as #f) <> 0 then
		g_lastError = "cannot write " & tmpName
		return false
	end if
	print #f, "# Mandelbrot Infinity bookmarks - coordinates are exact decimal strings"
	for i as long = 0 to count - 1
		print #f, ""
		print #f, "[" & secName & "]"
		print #f, "name=" & list(i).bname
		print #f, "x=" & list(i).x
		print #f, "y=" & list(i).y
		print #f, "half_height=" & list(i).halfh
		print #f, "max_iterations=" & list(i).maxIter
		print #f, "palette=" & list(i).palette
		print #f, "precision_bits=" & list(i).precBits
		print #f, "guard_bits=" & list(i).guardBits
		if list(i).coordBits > 0 then print #f, "coordinate_bits=" & list(i).coordBits
	next
	close #f
	kill fname
	if name(tmpName, fname) <> 0 then
		g_lastError = "cannot replace " & fname
		return false
	end if
	return true
end function

sub Bookmark_Delete(list() as Bookmark, byref count as long, byval idx as long)
	if idx < 0 orelse idx >= count then exit sub
	for i as long = idx to count - 2
		list(i) = list(i + 1)
	next
	count -= 1
end sub

'' Names may not contain line breaks or be empty.
function CleanName(byref s as string) as string
	dim r as string
	for i as long = 0 to len(s) - 1
		if s[i] >= 32 then r &= chr(s[i])
	next
	r = trim(r)
	if len(r) = 0 then r = "Unnamed"
	if len(r) > 80 then r = left(r, 80)
	return r
end function
