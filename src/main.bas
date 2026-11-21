'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - Deep Zoom Explorer
'' Copyright (c) 2026 retro778 - MIT License (see LICENSE)
''
'' Entry point: command line handling, start-up checks, headless rendering.
'' ---------------------------------------------------------------------------
#include once "engine.bas"
#include once "ui.bas"
#include once "app.bas"

sub PrintUsage()
	print APP_TITLE & " " & APP_VERSION
	print
	print "Usage: mandelbrot-infinity [options]"
	print
	print "  (no options)            start the interactive explorer"
	print "  --x NUM --y NUM         centre coordinates (decimal, any number of digits)"
	print "  --zoom NUM              magnification relative to the home view (e.g. 1e50)"
	print "  --half-height NUM       alternative to --zoom: half height of the view"
	print "  --location NAME         start at a preset from data/locations/locations.ini"
	print "  --iter N                maximum iterations"
	print "  --mode M                auto | double | mpfr | perturb"
	print "  --palette NAME|INDEX    colour palette"
	print "  --threads N             number of render threads (0 = all cores)"
	print
	print "Headless rendering (no window is opened):"
	print "  --render FILE.png       render the view to a PNG file and exit"
	print "  --size WxH              output size (default 1280x800)"
	print "  --ss N                  supersampling factor 1..4"
	print "  --transparent           transparent interior"
	print "  --no-series             disable series approximation"
	print
	print "  --list-locations        print the preset names"
	print "  --version, --help"
end sub

function ParseMode(byref s as string) as long
	select case lcase(s)
	case "double" : return MODE_DOUBLE
	case "mpfr" : return MODE_MPFR
	case "perturb", "perturbation" : return MODE_PERTURB
	case "auto" : return MODE_AUTO
	end select
	return -1
end function

function Main() as long
	Paths_Init()
	Settings_Defaults(g_set)
	if fileexists(Settings_File()) then
		if Settings_Load(g_set, Settings_File()) = false then
			LogMsg("settings file is empty or unreadable, using defaults: " & Settings_File())
		end if
	end if
	g_set.mode = MODE_AUTO          '' always start in automatic mode
	Palette_InitBuiltins()
	dim errs as string
	if Palette_LoadDir(g_baseDir & "/assets/palettes", errs) > 0 then LogMsg(errs)
	errs = ""
	if Palette_LoadDir(g_userDir & "/palettes", errs) > 0 then LogMsg(errs)
	if g_set.palette >= g_palCount then g_set.palette = 0

	errs = ""
	dim locFile as string = g_baseDir & "/data/locations/locations.ini"
	if Bookmarks_Read(locFile, g_loc(), g_locCount, errs) < 0 then
		LogMsg("location presets not found: " & locFile)
	elseif len(errs) > 0 then
		LogMsg("location presets: " & errs)
	end if
	errs = ""
	if fileexists(Bookmarks_File()) then
		if Bookmarks_Read(Bookmarks_File(), g_bm(), g_bmCount, errs) < 0 then
			LogMsg("cannot read " & Bookmarks_File())
		elseif len(errs) > 0 then
			LogMsg("bookmarks: " & errs)
		end if
	end if

	'' ---- command line ----
	dim as string ax, ay, azoom, ahalf, aloc, arender
	dim as long aw = 1280, ah = 800, aiter = 0, i = 1
	dim haveView as boolean = false
	while len(command(i)) > 0
		dim a as string = command(i)
		dim v as string = command(i + 1)
		select case a
		case "--help", "-h" : PrintUsage() : return 0
		case "--version" : print APP_TITLE & " " & APP_VERSION : return 0
		case "--list-locations"
			for k as long = 0 to g_locCount - 1
				print g_loc(k).bname
			next
			return 0
		case "--x" : ax = v : i += 1
		case "--y" : ay = v : i += 1
		case "--zoom" : azoom = v : i += 1
		case "--half-height" : ahalf = v : i += 1
		case "--location" : aloc = v : i += 1
		case "--iter" : aiter = valint(v) : i += 1
		case "--render" : arender = v : i += 1
		case "--ss" : g_set.exportSS = valint(v) : i += 1
		case "--threads" : g_set.threads = valint(v) : i += 1
		case "--transparent" : g_set.exportAlpha = 1
		case "--no-series" : g_set.useSeries = 0
		case "--mode"
			if ParseMode(v) < 0 then print "unknown mode '" & v & "'" : return 2
			g_set.mode = ParseMode(v) : i += 1
		case "--palette"
			dim p as long = Palette_Find(v)
			if p < 0 andalso len(v) > 0 andalso v[0] >= asc("0") andalso v[0] <= asc("9") then p = valint(v)
			if p < 0 orelse p >= g_palCount then print "unknown palette '" & v & "'" : return 2
			g_set.palette = p : i += 1
		case "--size"
			dim q as long = instr(lcase(v), "x")
			aw = valint(left(v, iif(q > 0, q - 1, 0))) : ah = valint(mid(v, q + 1))
			if q = 0 orelse aw < 16 orelse ah < 16 orelse aw > 32768 orelse ah > 32768 then
				print "invalid --size '" & v & "' (use WIDTHxHEIGHT)" : return 2
			end if
			i += 1
		case else
			print "unknown option '" & a & "' (try --help)" : return 2
		end select
		i += 1
	wend
	Settings_Sanitize(g_set)

	dim startView as ViewState
	View_Init(startView)
	dim startIter as long = g_set.maxIter
	if len(aloc) > 0 then
		dim found as boolean = false
		for k as long = 0 to g_locCount - 1
			if lcase(g_loc(k).bname) = lcase(aloc) then
				dim e as string
				if Bookmark_Apply(g_loc(k), startView, startIter, e) = false then print "location error: " & e : return 2
				found = true
			end if
		next
		if found = false then print "unknown location '" & aloc & "' (try --list-locations)" : return 2
		haveView = true
	end if
	if len(ax) > 0 orelse len(ay) > 0 orelse len(azoom) > 0 orelse len(ahalf) > 0 then
		if len(ax) = 0 then ax = "-0.5"
		if len(ay) = 0 then ay = "0"
		if len(azoom) = 0 andalso len(ahalf) = 0 then azoom = "1"
		dim e as string
		if View_SetFromStrings(startView, ax, ay, ahalf, azoom, e) = false then
			print "invalid view: " & e : return 2
		end if
		haveView = true
	end if
	if aiter > 0 then startIter = ClampL(aiter, 16, 100000000)

	'' ---- headless render ----
	if len(arender) > 0 then
		dim ex as ExportJob
		View_AutoPrec(startView, ah * g_set.exportSS)
		if Export_Begin(ex, startView, aw, ah, g_set.exportSS, startIter, g_set.mode, arender) = false then
			print ex.resultMsg : return 1
		end if
		dim r as long, lastP as long = -1
		do
			r = Export_Poll(ex)
			if r <> 0 then exit do
			dim st as string
			dim pc as long = int(Job_Progress(ex.job, st) * 100)
			if pc <> lastP then
				print chr(13) & "rendering " & pc & "%  " & st & "      ";
				lastP = pc
			end if
			sleep 50, 1
		loop
		print chr(13) & ex.resultMsg & "  [" & ModeName(ex.job.mode) & ", " & ex.job.maxIter & " iterations, " & _
			iif(ex.job.mode = MODE_DOUBLE, 53, ex.job.prec) & " bits, " & _
			iif(ex.job.mode = MODE_PERTURB, "series skip " & ex.job.ref.saSkip & ", ", "") & _
			format(ex.job.tElapsed, "0.00") & " s]"
		Job_Free(ex.job)
		return iif(r = 1, 0, 1)
	end if

	'' ---- interactive ----
	if App_Init() = false then
		print "Mandelbrot Infinity could not start - see the message above."
		#ifdef __FB_WIN32__
		'' a Windows GUI program has no console: show the reason in a dialog
		SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, APP_NAME, _
			"Mandelbrot Infinity could not start:" & chr(10) & chr(10) & g_fatalMsg, 0)
		#else
		print "Required runtime libraries: libsdl2-2.0-0 libsdl2-ttf-2.0-0 libmpfr6 libgmp10 libpng16-16"
		#endif
		return 1
	end if
	if haveView then
		View_Copy(g_view, startView)
		View_AutoPrec(g_view, g_imgH)
		g_iter = startIter
	end if
	View_Clear(startView)
	App_MarkView()
	App_Run()
	App_Shutdown()
	return 0
end function

end Main()
