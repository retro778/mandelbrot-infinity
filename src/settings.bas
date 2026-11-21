'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - paths, INI files, settings
'' ---------------------------------------------------------------------------
#include once "common.bi"
#include once "dir.bi"
#include once "file.bi"

dim shared g_set as Settings
dim shared g_baseDir as string      '' where assets/ and data/ live
dim shared g_userDir as string      '' per-user config directory
dim shared g_lastError as string

dim shared g_fatalMsg as string     '' last message, shown in a dialog if start-up fails

'' Messages go to stderr; on Windows (where a GUI program has no console)
'' they are also appended to log.txt in the user directory.
sub LogMsg(byref s as string)
	g_fatalMsg = s
	dim f as long = freefile
	if open err(for output as #f) = 0 then
		print #f, "[mandelbrot-infinity] " & s
		close #f
	end if
	#ifdef __FB_WIN32__
	if len(g_userDir) > 0 then
		f = freefile
		if open(g_userDir & "/log.txt" for append as #f) = 0 then
			print #f, date & " " & time & "  " & s
			close #f
		end if
	end if
	#endif
end sub

'' Environment variable holding a directory, with forward slashes.
function EnvDir(byref v as string) as string
	dim s as string = environ(v)
	for i as long = 0 to len(s) - 1
		if s[i] = asc("\") then s[i] = asc("/")
	next
	while len(s) > 1 andalso right(s, 1) = "/"
		s = left(s, len(s) - 1)
	wend
	return s
end function

'' The user's home folder (HOME on Linux, USERPROFILE on Windows).
function HomeDir() as string
	#ifdef __FB_WIN32__
	dim h as string = EnvDir("USERPROFILE")
	#else
	dim h as string = EnvDir("HOME")
	#endif
	if len(h) = 0 then h = "."
	return h
end function

function DirExists(byref p as string) as boolean
	return len(dir(p, fbDirectory or fbHidden)) > 0
end function

sub MakeDirs(byref p as string)
	'' mkdir -p
	dim i as long = 2
	do
		dim j as long = instr(i, p, "/")
		dim part as string
		if j = 0 then part = p else part = left(p, j - 1)
		if len(part) > 0 andalso right(part, 1) <> ":" then
			if DirExists(part) = false then mkdir part
		end if
		if j = 0 then exit do
		i = j + 1
	loop
end sub

sub Paths_Init()
	dim e as string = exepath
	for i as long = 0 to len(e) - 1
		if e[i] = asc("\") then e[i] = asc("/")
	next
	if DirExists(e & "/assets") orelse DirExists(e & "/data") then
		g_baseDir = e
	elseif DirExists(e & "/../assets") then
		g_baseDir = e & "/.."
	else
		g_baseDir = e
	end if
	#ifdef __FB_WIN32__
	dim cfg as string = EnvDir("APPDATA")
	if len(cfg) = 0 then cfg = HomeDir()
	#else
	dim cfg as string = EnvDir("XDG_CONFIG_HOME")
	if len(cfg) = 0 then cfg = HomeDir() & "/.config"
	#endif
	g_userDir = cfg & "/" & APP_DIRNAME
	MakeDirs(g_userDir)
	MakeDirs(g_userDir & "/palettes")
end sub

function CpuCount() as long
	#ifdef __FB_WIN32__
	dim n as long = valint(environ("NUMBER_OF_PROCESSORS"))
	#else
	dim n as long = sysconf(84)   '' _SC_NPROCESSORS_ONLN on Linux
	#endif
	if n < 1 then n = 1
	if n > 64 then n = 64
	return n
end function

'' ---- INI files --------------------------------------------------------------
'' [section] headers, key=value pairs, '#' or ';' comments.  Lines without '='
'' are kept as raw lines (key = "") - used for palette control points.
type IniSection
	sname as string
	n as long
	k(any) as string
	v(any) as string
end type

sub Ini_Add(byref s as IniSection, byref key as string, byref value as string)
	if s.n > ubound(s.k) then
		redim preserve s.k(0 to s.n * 2 + 15)
		redim preserve s.v(0 to s.n * 2 + 15)
	end if
	s.k(s.n) = key
	s.v(s.n) = value
	s.n += 1
end sub

function Ini_Get(byref s as IniSection, byref key as string, byref def as string = "") as string
	dim lk as string = lcase(key)
	for i as long = 0 to s.n - 1
		if s.k(i) = lk then return s.v(i)
	next
	return def
end function

'' Returns the number of sections, or -1 when the file cannot be read.
function Ini_Load(byref fname as string, secs() as IniSection) as long
	dim f as long = freefile
	dim cnt as long = 0
	erase secs
	if open(fname for input as #f) <> 0 then return -1
	dim ln as string
	while not eof(f)
		line input #f, ln
		ln = trim(ln, any " " & chr(9) & chr(13))
		if len(ln) = 0 then continue while
		if ln[0] = asc("#") orelse ln[0] = asc(";") then continue while
		if ln[0] = asc("[") then
			dim q as long = instr(ln, "]")
			if q = 0 then q = len(ln) + 1
			redim preserve secs(0 to cnt)
			secs(cnt).sname = lcase(trim(mid(ln, 2, q - 2)))
			secs(cnt).n = 0
			cnt += 1
			continue while
		end if
		if cnt = 0 then
			redim preserve secs(0 to 0)
			secs(0).sname = ""
			secs(0).n = 0
			cnt = 1
		end if
		dim p as long = instr(ln, "=")
		if p > 0 then
			Ini_Add(secs(cnt - 1), lcase(trim(left(ln, p - 1))), trim(mid(ln, p + 1)))
		else
			Ini_Add(secs(cnt - 1), "", ln)
		end if
	wend
	close #f
	return cnt
end function

'' ---- settings ----------------------------------------------------------------
function ClampL(byval v as long, byval lo as long, byval hi as long) as long
	if v < lo then return lo
	if v > hi then return hi
	return v
end function

function ClampD(byval v as double, byval lo as double, byval hi as double) as double
	if v < lo orelse v <> v then return lo
	if v > hi then return hi
	return v
end function

sub Settings_Defaults(byref s as Settings)
	s.threads = 0
	s.tileSize = 64
	s.previewStep = 8
	s.guardBits = 32
	s.fixedPrec = 0
	s.zoomSpeed = 1.5
	#ifdef __FB_64BIT__
	s.memLimitMB = 1024
	#else
	s.memLimitMB = 768          '' a 32-bit process has about 2 GB of address space
	#endif
	s.periodicity = 1
	s.usePerturb = 1
	s.useSeries = 1
	s.adaptiveIter = 1
	s.maxIter = 500
	s.mode = MODE_AUTO
	s.palette = 0
	s.density = 1.0
	s.offset = 0.0
	s.animate = 0
	s.animSpeed = 0.1
	s.transfer = TRANSFER_SOFTLOG
	s.winW = 1280
	s.winH = 800
	s.fullscreen = 0
	s.exportW = 1920
	s.exportH = 1080
	s.exportSS = 1
	s.exportAlpha = 0
	s.exportDir = HomeDir() & "/Pictures/" & APP_DIRNAME
end sub

'' Force every value into its legal range (invalid config files cannot
'' put the program into an unusable state).
sub Settings_Sanitize(byref s as Settings)
	s.threads = ClampL(s.threads, 0, 64)
	s.tileSize = ClampL((s.tileSize \ 16) * 16, 16, 512)
	select case s.previewStep
	case 1, 2, 4, 8, 16
	case else : s.previewStep = 8
	end select
	s.guardBits = ClampL(s.guardBits, 8, 512)
	if s.fixedPrec <> 0 then s.fixedPrec = ClampL(s.fixedPrec, 64, 4000000)
	s.zoomSpeed = ClampD(s.zoomSpeed, 1.05, 8.0)
	#ifdef __FB_64BIT__
	s.memLimitMB = ClampL(s.memLimitMB, 64, 65536)
	#else
	s.memLimitMB = ClampL(s.memLimitMB, 64, 1536)
	#endif
	s.maxIter = ClampL(s.maxIter, 16, 100000000)
	s.mode = ClampL(s.mode, MODE_AUTO, MODE_PERTURB)
	if s.palette < 0 then s.palette = 0
	s.density = ClampD(s.density, 0.01, 100.0)
	s.offset = s.offset - floor(s.offset)
	if s.offset <> s.offset then s.offset = 0
	s.animSpeed = ClampD(s.animSpeed, 0.005, 5.0)
	s.transfer = ClampL(s.transfer, 0, 2)
	s.winW = ClampL(s.winW, 800, 16384)
	s.winH = ClampL(s.winH, 600, 16384)
	s.exportW = ClampL(s.exportW, 16, 32768)
	s.exportH = ClampL(s.exportH, 16, 32768)
	s.exportSS = ClampL(s.exportSS, 1, 4)
	if len(s.exportDir) = 0 then s.exportDir = "."
end sub

function Settings_File() as string
	return g_userDir & "/settings.ini"
end function

'' Returns false (and leaves defaults) when the file is missing or unreadable.
function Settings_Load(byref s as Settings, byref fname as string) as boolean
	dim secs() as IniSection
	dim n as long = Ini_Load(fname, secs())
	if n <= 0 then return false
	#define GL(field, key) s.field = valint(Ini_Get(secs(0), key, str(s.field)))
	#define GD(field, key) s.field = val(Ini_Get(secs(0), key, str(s.field)))
	GL(threads, "threads")
	GL(tileSize, "tile_size")
	GL(previewStep, "preview_step")
	GL(guardBits, "guard_bits")
	GL(fixedPrec, "fixed_precision_bits")
	GD(zoomSpeed, "zoom_speed")
	GL(memLimitMB, "memory_limit_mb")
	GL(periodicity, "periodicity_check")
	GL(usePerturb, "use_perturbation")
	GL(useSeries, "use_series_approximation")
	GL(adaptiveIter, "adaptive_iterations")
	GL(maxIter, "max_iterations")
	GL(mode, "mode")
	GL(palette, "palette")
	GD(density, "color_density")
	GD(offset, "color_offset")
	GL(animate, "animate_palette")
	GD(animSpeed, "animation_speed")
	GL(transfer, "color_transfer")
	GL(winW, "window_width")
	GL(winH, "window_height")
	GL(fullscreen, "fullscreen")
	GL(exportW, "export_width")
	GL(exportH, "export_height")
	GL(exportSS, "export_supersampling")
	GL(exportAlpha, "export_transparent")
	s.exportDir = Ini_Get(secs(0), "export_dir", s.exportDir)
	Settings_Sanitize(s)
	return true
end function

function Settings_Save(byref s as Settings, byref fname as string) as boolean
	dim f as long = freefile
	if open(fname for output as #f) <> 0 then
		g_lastError = "Cannot write settings file " & fname
		return false
	end if
	print #f, "# Mandelbrot Infinity settings (edit while the program is closed)"
	print #f, "threads=" & s.threads
	print #f, "tile_size=" & s.tileSize
	print #f, "preview_step=" & s.previewStep
	print #f, "guard_bits=" & s.guardBits
	print #f, "fixed_precision_bits=" & s.fixedPrec
	print #f, "zoom_speed=" & s.zoomSpeed
	print #f, "memory_limit_mb=" & s.memLimitMB
	print #f, "periodicity_check=" & s.periodicity
	print #f, "use_perturbation=" & s.usePerturb
	print #f, "use_series_approximation=" & s.useSeries
	print #f, "adaptive_iterations=" & s.adaptiveIter
	print #f, "max_iterations=" & s.maxIter
	print #f, "mode=" & s.mode
	print #f, "palette=" & s.palette
	print #f, "color_density=" & s.density
	print #f, "color_offset=" & s.offset
	print #f, "animate_palette=" & s.animate
	print #f, "animation_speed=" & s.animSpeed
	print #f, "color_transfer=" & s.transfer
	print #f, "window_width=" & s.winW
	print #f, "window_height=" & s.winH
	print #f, "fullscreen=" & s.fullscreen
	print #f, "export_width=" & s.exportW
	print #f, "export_height=" & s.exportH
	print #f, "export_supersampling=" & s.exportSS
	print #f, "export_transparent=" & s.exportAlpha
	print #f, "export_dir=" & s.exportDir
	close #f
	return true
end function

function EffectiveThreads() as long
	if g_set.threads <= 0 then return CpuCount()
	return g_set.threads
end function

'' Largest iteration limit whose reference orbit fits the memory limit
'' (16 bytes per iteration, at most a quarter of the budget).
function MaxIterCap() as long
	dim m as longint = (clngint(g_set.memLimitMB) * 1024 * 1024 \ 4) \ 16
	if m > 100000000 then m = 100000000
	if m < 1000 then m = 1000
	return m
end function
