'' Mandelbrot Infinity - benchmark (prints a Markdown table)
'' build: fbc -gen gcc -O 3 -mt -i include -i src tests/bench.bas -x tests/bench
#include once "engine.bas"
#include once "string.bi"
Paths_Init() : Settings_Defaults(g_set) : Palette_InitBuiltins()

sub Bench(byref title as string, byref xs as string, byref ys as string, byref hs as string, _
		byval it as long, byval mode as long, byval sa as long, byval w as long, byval h as long)
	dim v as ViewState, e as string
	View_Init(v)
	if View_SetFromStrings(v, xs, ys, hs, "", e) = false then print "bad view" : exit sub
	View_AutoPrec(v, h)
	dim job as RenderJob
	g_set.useSeries = sa
	Job_Start(job, v, w, h, mode, it)
	Job_Wait(job)
	dim mn as string = ModeName(job.mode)
	if job.mode = MODE_PERTURB then mn &= iif(sa, " + series", "")
	print "| " & title & " | " & View_ZoomStr(v, 3) & " | " & it & " | " & mn & " | " & _
		iif(job.mode = MODE_DOUBLE, 53, job.prec) & " | " & w & "x" & h & " | " & format(job.tElapsed, "0.00") & " |"
	Job_Free(job)
	View_Clear(v)
end sub

dim locs() as Bookmark, n as long = 0, errs as string
Bookmarks_Read(g_baseDir & "/data/locations/locations.ini", locs(), n, errs)
function FindLoc(locs() as Bookmark, byval n as long, byref key as string) as long
	for i as long = 0 to n - 1
		if instr(locs(i).bname, key) > 0 then return i
	next
	return 0
end function

print "| View | Zoom | Max iter | Renderer | Bits | Size | Seconds |"
print "|---|---|---|---|---|---|---|"
dim as long W = 1280, H = 740, WS = 320, HS = 185
Bench("Home", "-0.5", "0", "1.25", 500, MODE_DOUBLE, 1, W, H)
Bench("Home", "-0.5", "0", "1.25", 500, MODE_PERTURB, 1, W, H)
Bench("Home", "-0.5", "0", "1.25", 500, MODE_MPFR, 1, W, H)
dim i as long = FindLoc(locs(), n, "Seahorse Valley")
Bench("Seahorse Valley", locs(i).x, locs(i).y, locs(i).halfh, 1500, MODE_DOUBLE, 1, W, H)
i = FindLoc(locs(), n, "Spiral")
Bench("Seahorse spiral", locs(i).x, locs(i).y, locs(i).halfh, 6000, MODE_PERTURB, 1, W, H)
Bench("Seahorse spiral", locs(i).x, locs(i).y, locs(i).halfh, 6000, MODE_PERTURB, 0, W, H)
Bench("Seahorse spiral", locs(i).x, locs(i).y, locs(i).halfh, 6000, MODE_MPFR, 0, WS, HS)
i = FindLoc(locs(), n, "period 64")
Bench("Mini, period 64", locs(i).x, locs(i).y, locs(i).halfh, 8000, MODE_PERTURB, 1, W, H)
i = FindLoc(locs(), n, "Embedded Julia")
Bench("Embedded Julia rings", locs(i).x, locs(i).y, locs(i).halfh, 3000, MODE_PERTURB, 1, W, H)
Bench("Embedded Julia rings", locs(i).x, locs(i).y, locs(i).halfh, 3000, MODE_MPFR, 0, WS, HS)
i = FindLoc(locs(), n, "Deep rings")
Bench("Rings around a mini", locs(i).x, locs(i).y, locs(i).halfh, 20000, MODE_PERTURB, 1, W, H)
i = FindLoc(locs(), n, "period 1339")
Bench("Mini, period 1339", locs(i).x, locs(i).y, locs(i).halfh, 40000, MODE_PERTURB, 1, W, H)
Bench("Dendrite tip", "0", "1", "1.25e-100", 2000, MODE_PERTURB, 1, W, H)
Bench("Dendrite tip", "0", "1", "1.25e-100", 2000, MODE_PERTURB, 0, W, H)
Bench("Dendrite tip", "0", "1", "1.25e-100", 2000, MODE_MPFR, 0, WS, HS)
Bench("Dendrite tip", "0", "1", "1.25e-1000", 8000, MODE_PERTURB, 1, W, H)
Bench("Dendrite tip", "0", "1", "1.25e-1000", 8000, MODE_PERTURB, 0, W, H)
Bench("Dendrite tip", "0", "1", "1.25e-10000", 60000, MODE_PERTURB, 1, W, H)
