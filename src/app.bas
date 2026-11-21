'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - interactive application (window, input, main loop)
'' ---------------------------------------------------------------------------
#include once "common.bi"
#include once "string.bi"
#include once "datetime.bi"
#include once "vbcompat.bi"

const MK_CONTEXT = 1
const MK_LOCATIONS = 2
const MK_BOOKMARKS = 3
const MK_SETTINGS = 4
const MK_EXPORT = 5

const PP_BM_NAME = 1
const PP_BM_RENAME = 2
const PP_BM_EXPORT = 3
const PP_BM_IMPORT = 4
const PP_GOTO_X = 5
const PP_GOTO_Y = 6
const PP_GOTO_ZOOM = 7
const PP_EXPORT_SIZE = 8
const PP_ITER = 9

dim shared g_tex as SDL_Texture ptr
dim shared g_view as ViewState            '' what the user is looking at
dim shared g_shown as ViewState           '' view the pixels in g_img belong to
dim shared g_shownW as long, g_shownH as long
dim shared g_imgW as long, g_imgH as long, g_barH as long
dim shared g_img as ulong ptr, g_back as ulong ptr
dim shared g_job as RenderJob
dim shared g_export as ExportJob
dim shared g_iter as long = 500
dim shared g_viewDirty as boolean = true
dim shared g_lastChange as double = 0
dim shared g_recolor as boolean = true
dim shared g_wasBusy as boolean = false
dim shared g_adaptCount as long = 0
dim shared g_renderTime as double = 0
dim shared g_showHelp as boolean = false
dim shared g_quit as boolean = false
dim shared g_dragging as boolean = false
dim shared g_dragMoved as boolean = false
dim shared g_menuPX as long, g_menuPY as long      '' image pixel of the right click
dim shared g_strX as string, g_strY as string, g_strZoom as string
dim shared g_strDirty as boolean = true
dim shared g_gotoX as string, g_gotoY as string
dim shared g_bmEdit as long = -1
dim shared g_lastColorize as double = 0
dim shared g_lastAnim as double = 0
dim shared g_cancelled as boolean = false

'' ---- background helpers: verification and nucleus search --------------------------
type VerifyState
	thread as any ptr
	running as long
	cancel as long
	finished as long
	n as long
	bad as long
	maxDiff as double
end type
dim shared g_verify as VerifyState

private sub VerifyMain(byval p as any ptr)
	dim ctx as MpfrCtx
	MpfrCtx_Init(ctx, g_job.prec)
	dim seed as ulongint = &h9E3779B97F4A7C15ull xor culngint(timer * 1000)
	dim t0 as double = timer
	for s as long = 1 to 64
		seed = seed * 6364136223846793005ull + 1442695040888963407ull
		dim px as long = (seed shr 33) mod g_job.w
		seed = seed * 6364136223846793005ull + 1442695040888963407ull
		dim py as long = (seed shr 33) mod g_job.h
		dim a as double = g_job.nu[clngint(py) * g_job.w + px]
		if a = NU_PENDING then continue for
		PixelCoordMpfr(g_job, ctx, px, py)
		dim b as double = IterateMpfr(ctx, g_job.maxIter, @g_verify.cancel)
		if b = NU_PENDING then exit for
		g_verify.n += 1
		if (a < 0) <> (b < 0) then
			g_verify.bad += 1
		elseif a >= 0 then
			dim d as double = abs(a - b)
			if d > g_verify.maxDiff then g_verify.maxDiff = d
			if d > 0.05 then g_verify.bad += 1
		end if
		if timer - t0 > 30 then exit for
	next
	MpfrCtx_Clear(ctx)
	g_verify.finished = 1
end sub

sub Verify_Stop()
	if g_verify.thread then
		g_verify.cancel = 1
		threadwait(g_verify.thread)
		g_verify.thread = 0
	end if
	g_verify.running = 0
	g_verify.finished = 0
end sub

type NucState
	thread as any ptr
	running as long
	cancel as long
	finished as long
	found as long
	period as long
	maxPeriod as long
	cx as mpfr_t
	cy as mpfr_t
	rad as mpfr_t
	ox as mpfr_t
	oy as mpfr_t
	osize as mpfr_t
	inited as long
end type
dim shared g_nuc as NucState

private sub NucMain(byval p as any ptr)
	dim period as long
	g_nuc.found = iif(Nucleus_Find(@g_nuc.cx, @g_nuc.cy, @g_nuc.rad, g_nuc.maxPeriod, @g_nuc.cancel, _
		@g_nuc.ox, @g_nuc.oy, @g_nuc.osize, period), 1, 0)
	g_nuc.period = period
	g_nuc.finished = 1
end sub

sub Nuc_Stop()
	if g_nuc.thread then
		g_nuc.cancel = 1
		threadwait(g_nuc.thread)
		g_nuc.thread = 0
	end if
	g_nuc.running = 0
	g_nuc.finished = 0
end sub

'' ---- layout ------------------------------------------------------------------------
sub App_Layout()
	dim as long ww, wh, ow, oh
	SDL_GetWindowSize(g_win, @ww, @wh)
	if SDL_GetRendererOutputSize(g_ren, @ow, @oh) <> 0 then ow = ww : oh = wh
	if ow < 16 then ow = 16
	if oh < 16 then oh = 16
	dim nd as double = iif(ww > 0, ow / ww, 1.0)
	if nd < 1 then nd = 1
	if g_font = 0 orelse abs(nd - g_dpi) > 0.01 then
		g_dpi = nd
		if Font_Load(clng(14 * g_dpi)) = false then
			LogMsg("no usable TrueType font found (looked for DejaVuSansMono.ttf)")
		end if
	end if
	g_W = ow : g_H = oh
	g_barH = g_lineH * 3 + 10
	g_imgW = g_W
	g_imgH = g_H - g_barH
	if g_imgH < 16 then g_imgH = 16
end sub

sub App_MarkView()
	g_viewDirty = true
	g_lastChange = timer
	g_strDirty = true
	g_cancelled = false
end sub

'' Map image "a" (the shown pixels) into the current view: returns false if
'' they are unrelated at any sensible scale.
private function ShownRelation(byref k as double, byref sx as double, byref sy as double) as boolean
	if g_shown.valid = 0 orelse g_shownW < 1 then return false
	return View_Relate(g_shown, g_shownW, g_shownH, g_view, g_imgW, g_imgH, k, sx, sy)
end function

sub App_StartRender(byval refine as boolean = false)
	Verify_Stop()
	dim as long w = g_imgW, h = g_imgH
	if refine = false then
		'' build the backdrop from what is currently on screen
		dim nb as ulong ptr = allocate(clngint(w) * h * sizeof(ulong))
		if nb = 0 then
			Toast("Out of memory for the image buffer", true)
			g_viewDirty = false
			exit sub
		end if
		dim as double k, sx, sy
		dim rel as boolean = (g_img <> 0) andalso ShownRelation(k, sx, sy)
		if rel then
			dim as double ik = 1.0 / k
			dim as double cx0 = (g_shownW - 1) * 0.5, cy0 = (g_shownH - 1) * 0.5
			for y as long = 0 to h - 1
				dim oy as long = clng(floor((y - sy) * ik + cy0 + 0.5))
				dim dst as ulong ptr = nb + clngint(y) * w
				if oy < 0 orelse oy >= g_shownH then
					for x as long = 0 to w - 1
						dst[x] = &hFF101018ul
					next
				else
					dim src as ulong ptr = g_img + clngint(oy) * g_shownW
					for x as long = 0 to w - 1
						dim ox as long = clng(floor((x - sx) * ik + cx0 + 0.5))
						if ox < 0 orelse ox >= g_shownW then dst[x] = &hFF101018ul else dst[x] = src[ox]
					next
				end if
			next
		else
			for i as longint = 0 to clngint(w) * h - 1
				nb[i] = &hFF101018ul
			next
		end if
		if g_back then deallocate(g_back)
		g_back = nb
		if g_shownW <> w orelse g_shownH <> h orelse g_img = 0 orelse g_tex = 0 then
			if g_img then deallocate(g_img)
			g_img = allocate(clngint(w) * h * sizeof(ulong))
			if g_tex then SDL_DestroyTexture(g_tex)
			g_tex = SDL_CreateTexture(g_ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h)
			if g_img = 0 orelse g_tex = 0 then
				Toast("Cannot create a " & w & "x" & h & " image: " & *SDL_GetError(), true)
				g_viewDirty = false
				exit sub
			end if
		end if
		View_Copy(g_shown, g_view)
		g_shownW = w : g_shownH = h
		g_adaptCount = 0
		g_renderTime = 0
		if g_set.adaptiveIter then
			'' gentle depth-based floor; the adaptive pass raises it when needed
			dim fl as long = clng(100 * (1 + View_ZoomLog10(g_view)))
			if fl > g_iter then g_iter = iif(fl > MaxIterCap(), MaxIterCap(), fl)
		end if
	end if
	g_viewDirty = false
	g_cancelled = false
	if Job_Start(g_job, g_view, w, h, g_set.mode, g_iter, iif(refine, 1, 0)) = false then
		Toast("Render failed: " & g_job.errMsg, true)
	end if
	g_wasBusy = true
	g_recolor = true
end sub

sub App_Recolor()
	if g_img = 0 orelse g_job.t = 0 orelse g_tex = 0 then exit sub
	if g_job.w <> g_shownW orelse g_job.h <> g_shownH then exit sub
	Colorize(g_job.t, clngint(g_shownW) * g_shownH, g_img, g_back, g_set.palette, g_set.density, g_set.offset)
	SDL_UpdateTexture(g_tex, 0, g_img, g_shownW * 4)
	g_recolor = false
	g_lastColorize = timer
end sub

'' ---- actions -------------------------------------------------------------------------
sub Act_Reset()
	View_Reset(g_view)
	g_iter = g_set.maxIter
	App_MarkView()
end sub

sub Act_Zoom(byval px as double, byval py as double, byval factor as double)
	if View_ZoomAt(g_view, g_imgW, g_imgH, px, py, factor) = false then
		Toast("Zoom limit reached")
	end if
	App_MarkView()
end sub

sub Act_SetIter(byval n as long)
	g_iter = ClampL(n, 16, MaxIterCap())
	g_set.maxIter = g_iter
	Toast("Maximum iterations: " & g_iter)
	App_MarkView()
end sub

sub Act_NextPalette(byval d as long)
	g_set.palette = (g_set.palette + d + g_palCount) mod g_palCount
	Toast("Palette: " & g_pal(g_set.palette).pname)
	g_recolor = true
end sub

sub Act_CycleMode()
	g_set.mode = (g_set.mode + 1) mod 4
	Toast("Rendering mode: " & ModeName(g_set.mode))
	App_MarkView()
end sub

sub Act_Fullscreen()
	g_set.fullscreen = 1 - g_set.fullscreen
	SDL_SetWindowFullscreen(g_win, iif(g_set.fullscreen, SDL_WINDOW_FULLSCREEN_DESKTOP, 0))
end sub

sub Act_GotoLocation(byref b as Bookmark)
	dim e as string
	dim it as long = g_iter
	if Bookmark_Apply(b, g_view, it, e) then
		g_iter = ClampL(it, 16, MaxIterCap())
		View_AutoPrec(g_view, g_imgH)
		Toast(b.bname)
		g_recolor = true
		App_MarkView()
	else
		Toast("Cannot open '" & b.bname & "': " & e, true)
	end if
end sub

sub Act_SaveBookmarks()
	if Bookmarks_Write(Bookmarks_File(), g_bm(), g_bmCount) = false then Toast(g_lastError, true)
end sub

sub Act_Verify()
	if g_job.done = 0 orelse g_job.nu = 0 then
		Toast("Verification needs a finished render")
		exit sub
	end if
	if Job_Busy(g_job) then
		Toast("Verification needs a finished render")
		exit sub
	end if
	Verify_Stop()
	g_verify.cancel = 0 : g_verify.n = 0 : g_verify.bad = 0 : g_verify.maxDiff = 0
	g_verify.running = 1
	g_verify.thread = threadcreate(@VerifyMain, 0)
	if g_verify.thread = 0 then g_verify.running = 0 : Toast("Cannot start verification thread", true) : exit sub
	Toast("Verifying 64 random pixels against the MPFR reference ...", false, 60)
end sub

sub Act_FindNucleus()
	if g_nuc.running then Toast("Minibrot search already running") : exit sub
	Nuc_Stop()
	if g_nuc.inited = 0 then
		mpfr_init2(@g_nuc.cx, 64) : mpfr_init2(@g_nuc.cy, 64) : mpfr_init2(@g_nuc.rad, 64)
		mpfr_init2(@g_nuc.ox, 64) : mpfr_init2(@g_nuc.oy, 64) : mpfr_init2(@g_nuc.osize, 64)
		g_nuc.inited = 1
	end if
	mpfr_set_prec(@g_nuc.cx, g_view.prec) : mpfr_set_prec(@g_nuc.cy, g_view.prec)
	mpfr_set(@g_nuc.cx, @g_view.cx, MPFR_RNDN)
	mpfr_set(@g_nuc.cy, @g_view.cy, MPFR_RNDN)
	mpfr_set(@g_nuc.rad, @g_view.halfh, MPFR_RNDN)
	g_nuc.maxPeriod = ClampL(g_iter * 4, 20000, 2000000)
	g_nuc.cancel = 0
	g_nuc.running = 1
	g_nuc.thread = threadcreate(@NucMain, 0)
	if g_nuc.thread = 0 then g_nuc.running = 0 : Toast("Cannot start search thread", true) : exit sub
	Toast("Searching for a mini-Mandelbrot in this view ... (Esc cancels)", false, 600)
end sub

function Export_NewPath() as string
	MakeDirs(g_set.exportDir)
	dim base_ as string = g_set.exportDir & "/mandelbrot_" & format(now, "yyyymmdd_hhmmss")
	dim p as string = base_ & ".png"
	dim n as long = 1
	while fileexists(p)
		n += 1
		p = base_ & "_" & n & ".png"
	wend
	return p
end function

sub Act_StartExport()
	if g_export.active then exit sub
	Menu_Close()
	if DirExists(g_set.exportDir) = false then MakeDirs(g_set.exportDir)
	if DirExists(g_set.exportDir) = false then
		Toast("Cannot create export folder " & g_set.exportDir, true)
		exit sub
	end if
	'' reuse the colour origin of the picture on screen so the file matches it
	dim cb as double = iif(g_job.done <> 0 andalso g_viewDirty = false, g_job.nuBase, -1.0)
	if Export_Begin(g_export, g_view, g_set.exportW, g_set.exportH, g_set.exportSS, g_iter, _
			g_set.mode, Export_NewPath(), cb) = false then
		Toast(g_export.resultMsg, true)
	end if
end sub

'' ---- menus ---------------------------------------------------------------------------
function OnOff(byval v as long) as string
	return iif(v, "on", "off")
end function

sub Build_Context()
	Menu_Begin(MK_CONTEXT, "Navigation")
	Menu_Add("Zoom in here", 1)
	Menu_Add("Zoom out here", 2)
	Menu_Add("Centre here", 3)
	Menu_Add("Reset view", 4, "R")
	Menu_Add("Find mini-Mandelbrot in view", 5, "N")
	Menu_Add("Go to coordinates ...", 6, "G")
	Menu_Add("Interesting locations ...", 7, "L")
	Menu_Add("Bookmarks ...", 8, "O")
	Menu_Add("Add bookmark ...", 9, "B")
	Menu_Add("Rendering mode", 10, ModeName(g_set.mode))
	Menu_Add("Palette", 11, g_pal(g_set.palette).pname)
	Menu_Add("Save image ...", 12, "S")
	Menu_Add("Settings ...", 13, "Tab")
	Menu_Add("Verify against MPFR", 14, "V")
	Menu_Add("Help", 15, "H")
end sub

sub Build_Locations()
	Menu_Begin(MK_LOCATIONS, "Interesting locations", "Enter = go")
	Menu_Add("Home view (full Mandelbrot set)", -1)
	for i as long = 0 to g_locCount - 1
		Menu_Add(g_loc(i).bname, i)
	next
end sub

sub Build_Bookmarks()
	Menu_Begin(MK_BOOKMARKS, "Bookmarks", "Enter=go  F2=rename  Del=delete  E=export  I=import")
	Menu_Add("+ Add bookmark for the current view", -1)
	for i as long = 0 to g_bmCount - 1
		if i >= MENU_MAX - 2 then exit for
		Menu_Add(g_bm(i).bname, i)
	next
end sub

function TransferName(byval t as long) as string
	select case t
	case TRANSFER_LINEAR : return "linear"
	case TRANSFER_SQRT : return "square root"
	end select
	return "soft log"
end function

sub Build_Settings()
	Menu_Begin(MK_SETTINGS, "Settings", "Left/Right = change   Esc = close")
	Menu_Add("Rendering", 0, "", 1)
	Menu_Add("  Mode", 1, ModeName(g_set.mode))
	Menu_Add("  Maximum iterations", 2, str(g_iter))
	Menu_Add("  Adaptive iteration limit", 3, OnOff(g_set.adaptiveIter))
	Menu_Add("  Periodicity check (double)", 4, OnOff(g_set.periodicity))
	Menu_Add("  Perturbation in Auto mode", 5, OnOff(g_set.usePerturb))
	Menu_Add("  Series approximation", 6, OnOff(g_set.useSeries))
	Menu_Add("Precision policy", 0, "", 1)
	Menu_Add("  Guard bits", 7, str(g_set.guardBits))
	Menu_Add("  Fixed precision (bits)", 8, iif(g_set.fixedPrec = 0, "automatic", str(g_set.fixedPrec)))
	Menu_Add("Performance", 0, "", 1)
	Menu_Add("  Render threads", 9, iif(g_set.threads = 0, "auto (" & CpuCount() & ")", str(g_set.threads)))
	Menu_Add("  Tile size", 10, str(g_set.tileSize))
	Menu_Add("  Preview block size", 11, str(g_set.previewStep))
	Menu_Add("  Memory limit (MB)", 12, str(g_set.memLimitMB))
	Menu_Add("Navigation", 0, "", 1)
	Menu_Add("  Zoom speed (per wheel step)", 13, format(g_set.zoomSpeed, "0.00") & "x")
	Menu_Add("Colour", 0, "", 1)
	Menu_Add("  Palette", 14, g_pal(g_set.palette).pname)
	Menu_Add("  Colour intensity", 15, format(g_set.density, "0.00"))
	Menu_Add("  Palette offset", 16, format(g_set.offset, "0.00"))
	Menu_Add("  Colour mapping", 17, TransferName(g_set.transfer))
	Menu_Add("  Animate palette", 18, OnOff(g_set.animate))
	Menu_Add("  Animation speed", 19, format(g_set.animSpeed, "0.00"))
end sub

dim shared g_presetW(0 to 3) as long = {1280, 1920, 2560, 3840}
dim shared g_presetH(0 to 3) as long = {800, 1080, 1440, 2160}

sub Build_Export()
	Menu_Begin(MK_EXPORT, "Save image (PNG)", "Left/Right = change   Enter = select")
	Menu_Add("Resolution preset", 1, g_set.exportW & " x " & g_set.exportH)
	Menu_Add("Custom resolution ...", 2)
	Menu_Add("Supersampling", 3, g_set.exportSS & "x" & g_set.exportSS)
	Menu_Add("Transparent interior", 4, OnOff(g_set.exportAlpha))
	Menu_Add("Folder", 0, g_set.exportDir, 1)
	Menu_Add("Start export", 5)
end sub

sub Settings_Adjust(byval id as long, byval d as long)
	dim rerender as boolean = false
	select case id
	case 1 : g_set.mode = (g_set.mode + d + 4) mod 4 : rerender = true
	case 2
		if d > 0 then g_iter = ClampL(g_iter * 2, 16, MaxIterCap()) else g_iter = ClampL(g_iter \ 2, 16, MaxIterCap())
		g_set.maxIter = g_iter
		rerender = true
	case 3 : g_set.adaptiveIter = 1 - g_set.adaptiveIter
	case 4 : g_set.periodicity = 1 - g_set.periodicity
	case 5 : g_set.usePerturb = 1 - g_set.usePerturb : rerender = true
	case 6 : g_set.useSeries = 1 - g_set.useSeries : rerender = true
	case 7 : g_set.guardBits = ClampL(g_set.guardBits + d * 8, 8, 512) : rerender = true
	case 8
		if d > 0 then
			g_set.fixedPrec = iif(g_set.fixedPrec = 0, 64, g_set.fixedPrec * 2)
		else
			g_set.fixedPrec = iif(g_set.fixedPrec <= 64, 0, g_set.fixedPrec \ 2)
		end if
		rerender = true
	case 9 : g_set.threads = ClampL(g_set.threads + d, 0, 64)
	case 10 : g_set.tileSize = ClampL(iif(d > 0, g_set.tileSize * 2, g_set.tileSize \ 2), 16, 512)
	case 11 : g_set.previewStep = ClampL(iif(d > 0, g_set.previewStep * 2, g_set.previewStep \ 2), 1, 16)
	case 12 : g_set.memLimitMB = ClampL(iif(d > 0, g_set.memLimitMB * 2, g_set.memLimitMB \ 2), 64, 65536)
	case 13 : g_set.zoomSpeed = ClampD(g_set.zoomSpeed + d * 0.05, 1.05, 8.0)
	case 14 : g_set.palette = (g_set.palette + d + g_palCount) mod g_palCount : g_recolor = true
	case 15 : g_set.density = ClampD(g_set.density * iif(d > 0, 1.1, 1 / 1.1), 0.01, 100) : g_recolor = true
	case 16 : g_set.offset = frac(g_set.offset + d * 0.02 + 1) : g_recolor = true
	case 17 : g_set.transfer = (g_set.transfer + d + 3) mod 3 : rerender = true
	case 18 : g_set.animate = 1 - g_set.animate
	case 19 : g_set.animSpeed = ClampD(g_set.animSpeed * iif(d > 0, 1.25, 0.8), 0.005, 5)
	end select
	Settings_Sanitize(g_set)
	if rerender then App_MarkView()
	Build_Settings()
end sub

sub Export_Adjust(byval id as long, byval d as long)
	select case id
	case 1
		dim cur as long = -1
		for i as long = 0 to 3
			if g_presetW(i) = g_set.exportW andalso g_presetH(i) = g_set.exportH then cur = i
		next
		if cur < 0 then cur = iif(d > 0, 0, 3) else cur = (cur + d + 4) mod 4
		g_set.exportW = g_presetW(cur) : g_set.exportH = g_presetH(cur)
	case 3 : g_set.exportSS = ClampL(g_set.exportSS + d, 1, 4)
	case 4 : g_set.exportAlpha = 1 - g_set.exportAlpha
	end select
	Build_Export()
end sub

sub Menu_Activate()
	if g_menu.n = 0 then exit sub
	dim id as long = g_menu.it(g_menu.sel).id
	select case g_menu.kind
	case MK_CONTEXT
		Menu_Close()
		select case id
		case 1 : Act_Zoom(g_menuPX, g_menuPY, 2.0)
		case 2 : Act_Zoom(g_menuPX, g_menuPY, 0.5)
		case 3 : View_CenterOn(g_view, g_imgW, g_imgH, g_menuPX, g_menuPY) : App_MarkView()
		case 4 : Act_Reset()
		case 5 : Act_FindNucleus()
		case 6 : Prompt_Open(PP_GOTO_X, "Go to: real part (X)", HpToStr(@g_view.cx), "decimal number, any number of digits")
		case 7 : Build_Locations()
		case 8 : Build_Bookmarks()
		case 9 : Prompt_Open(PP_BM_NAME, "Bookmark name", "Bookmark " & (g_bmCount + 1))
		case 10 : Act_CycleMode()
		case 11 : Act_NextPalette(1)
		case 12 : Build_Export()
		case 13 : Build_Settings()
		case 14 : Act_Verify()
		case 15 : g_showHelp = true
		end select
	case MK_LOCATIONS
		Menu_Close()
		if id < 0 then Act_Reset() else Act_GotoLocation(g_loc(id))
	case MK_BOOKMARKS
		if id < 0 then
			Menu_Close()
			Prompt_Open(PP_BM_NAME, "Bookmark name", "Bookmark " & (g_bmCount + 1))
		else
			Menu_Close()
			Act_GotoLocation(g_bm(id))
		end if
	case MK_SETTINGS
		Settings_Adjust(id, 1)
	case MK_EXPORT
		select case id
		case 2 : Prompt_Open(PP_EXPORT_SIZE, "Custom resolution", g_set.exportW & "x" & g_set.exportH, "format: WIDTHxHEIGHT, e.g. 5120x2880")
		case 5 : Act_StartExport()
		case else : Export_Adjust(id, 1)
		end select
	end select
end sub

sub Prompt_Accept()
	dim s as string = trim(g_prompt.txt)
	dim purpose as long = g_prompt.purpose
	Prompt_Close()
	select case purpose
	case PP_BM_NAME
		redim preserve g_bm(0 to g_bmCount)
		g_bm(g_bmCount) = Bookmark_FromView(CleanName(s), g_view, g_iter, g_imgH)
		g_bmCount += 1
		Act_SaveBookmarks()
		Toast("Bookmark saved: " & CleanName(s))
	case PP_BM_RENAME
		if g_bmEdit >= 0 andalso g_bmEdit < g_bmCount then
			g_bm(g_bmEdit).bname = CleanName(s)
			Act_SaveBookmarks()
		end if
		Build_Bookmarks()
	case PP_BM_EXPORT
		if len(s) = 0 then
			Toast("No file name given", true)
		elseif Bookmarks_Write(s, g_bm(), g_bmCount) then
			Toast("Exported " & g_bmCount & " bookmarks to " & s)
		else
			Toast("Export failed: " & g_lastError, true)
		end if
	case PP_BM_IMPORT
		dim errs as string
		dim n as long = Bookmarks_Read(s, g_bm(), g_bmCount, errs)
		if n < 0 then
			Toast("Cannot read " & s, true)
		else
			Act_SaveBookmarks()
			if len(errs) > 0 then
				LogMsg(errs)
				Toast("Imported " & n & " bookmarks; some entries were invalid (see terminal)", true)
			else
				Toast("Imported " & n & " bookmarks")
			end if
		end if
		Build_Bookmarks()
	case PP_GOTO_X
		g_gotoX = s
		Prompt_Open(PP_GOTO_Y, "Go to: imaginary part (Y)", HpToStr(@g_view.cy), "decimal number, any number of digits")
	case PP_GOTO_Y
		g_gotoY = s
		Prompt_Open(PP_GOTO_ZOOM, "Go to: zoom (magnification)", View_ZoomStr(g_view, 6), "e.g. 1e50   (1 = home view)")
	case PP_GOTO_ZOOM
		dim e as string
		if View_SetFromStrings(g_view, g_gotoX, g_gotoY, "", s, e) then
			View_AutoPrec(g_view, g_imgH)
			App_MarkView()
		else
			Toast("Invalid input: " & e, true)
		end if
	case PP_EXPORT_SIZE
		dim p as long = instr(lcase(s), "x")
		dim as long nw = valint(left(s, iif(p > 0, p - 1, 0))), nh = valint(mid(s, p + 1))
		if p = 0 orelse nw < 16 orelse nh < 16 orelse nw > 32768 orelse nh > 32768 then
			Toast("Invalid resolution '" & s & "' (use WIDTHxHEIGHT, 16..32768)", true)
		else
			g_set.exportW = nw : g_set.exportH = nh
		end if
		Build_Export()
	case PP_ITER
		dim n as long = valint(s)
		if n < 16 then Toast("Invalid iteration count '" & s & "'", true) else Act_SetIter(n)
	end select
end sub

'' ---- drawing ---------------------------------------------------------------------------
dim shared g_helpLines(0 to 31) as string
dim shared g_helpCount as long = 0

sub Help_Init()
	#define HL(s) g_helpLines(g_helpCount) = s : g_helpCount += 1
	HL("MOUSE")
	HL("  Wheel            zoom in / out at the cursor")
	HL("  Left drag        pan")
	HL("  Double click     zoom towards the cursor")
	HL("  Right click      navigation menu")
	HL("KEYBOARD")
	HL("  Arrows           pan (Shift = fine)        + / -   zoom in / out")
	HL("  R                reset view                F       fullscreen")
	HL("  C / Shift+C      next / previous palette   A       animate palette")
	HL("  [ ]              palette offset            , .     colour intensity")
	HL("  I / K            more / fewer iterations   T       type iteration count")
	HL("  M                rendering mode            V       verify against MPFR")
	HL("  B                add bookmark              O       bookmark list")
	HL("  L                interesting locations     G       go to coordinates")
	HL("  N                find mini-Mandelbrot      S       save PNG image")
	HL("  Tab              settings                  H / F1  this help")
	HL("  Esc              close panel / cancel render / quit")
end sub

sub Draw_Help()
	dim wch as long = 0
	for i as long = 0 to g_helpCount - 1
		if len(g_helpLines(i)) > wch then wch = len(g_helpLines(i))
	next
	dim pad as long = g_lineH
	dim as long w = wch * g_charW + pad * 2, h = (g_helpCount + 2) * g_lineH + pad * 2
	dim as long x = (g_W - w) \ 2, y = (g_H - h) \ 2
	if y < 4 then y = 4
	Panel(x, y, w, h)
	DrawText(x + pad, y + pad, APP_TITLE & "  " & APP_VERSION, COL_ACCENT)
	for i as long = 0 to g_helpCount - 1
		dim c as ulong = iif(left(g_helpLines(i), 1) = " ", COL_TEXT, COL_DIM)
		DrawText(x + pad, y + pad + (i + 2) * g_lineH, g_helpLines(i), c)
	next
end sub

private function CoordStr(byval x as mpfr_ptr) as string
	dim maxCh as long = (g_W - 16) \ g_charW - 6
	if maxCh < 40 then maxCh = 40
	dim want as long = clng(View_ZoomLog10(g_view)) + 8
	if want < 17 then want = 17
	dim s as string = HpToStr(x, want)
	if len(s) <= maxCh then return s
	'' too long for the bar: show the leading digits and say how many there are
	return left(s, maxCh - 20) & " ... (" & want & " digits)"
end function

sub Draw_StatusBar()
	dim y0 as long = g_H - g_barH
	FillRect(0, y0, g_W, g_barH, COL_BAR)
	FillRect(0, y0, g_W, 1, COL_BORDER)
	if g_strDirty then
		g_strX = CoordStr(@g_view.cx)
		g_strY = CoordStr(@g_view.cy)
		g_strZoom = View_ZoomStr(g_view, 4)
		g_strDirty = false
	end if
	dim x as long = 8
	DrawText(x, y0 + 4, "X", COL_ACCENT)
	DrawText(x + g_charW * 2, y0 + 4, g_strX)
	DrawText(x, y0 + 4 + g_lineH, "Y", COL_ACCENT)
	DrawText(x + g_charW * 2, y0 + 4 + g_lineH, g_strY)

	dim y3 as long = y0 + 4 + g_lineH * 2
	'' narrow windows get a compact third line
	dim compact as boolean = (g_W < 150 * g_charW)
	dim gap as long = g_charW * iif(compact, 2, 3)
	#macro SEG(lbl, txt, col)
		DrawText(x, y3, lbl, COL_DIM)
		x += TextW(lbl) + g_charW
		DrawText(x, y3, txt, col)
		x += TextW(txt) + gap
	#endmacro
	dim zb as long = View_ZoomBits(g_view, g_imgH)
	dim effMode as long = iif(g_job.w > 0, g_job.mode, ResolveMode(g_set.mode, zb))
	dim precBad as boolean = (g_job.precOK = 0 andalso g_job.w > 0)
	dim s as string
	SEG("Zoom", g_strZoom, COL_TEXT)
	dim as long pb = iif(effMode = MODE_DOUBLE, 53, g_job.prec)
	dim as long pd = clng(int(pb * LOG10_2))
	if compact then s = pb & "b/" & pd & "d" else s = pb & " bits (" & pd & " digits)"
	SEG(iif(compact, "Prec", "Precision"), s, iif(precBad, COL_WARN, COL_TEXT))
	SEG("Iter", str(iif(g_job.w > 0, g_job.maxIter, g_iter)), COL_TEXT)
	s = ModeName(effMode)
	if compact andalso effMode = MODE_PERTURB then s = "Perturb"
	if g_set.mode = MODE_AUTO then s = "Auto: " & s
	if effMode = MODE_PERTURB andalso g_job.ref.saSkip > 0 then s &= iif(compact, "+SA", " +SA")
	SEG("Mode", s, COL_TEXT)
	'' progress
	dim st as string
	dim p as double = Job_Progress(g_job, st)
	dim busy as boolean = Job_Busy(g_job)
	dim tm as double = g_renderTime + iif(busy, timer - g_job.tStart, 0)
	if busy then
		dim bw as long = g_charW * iif(compact, 8, 12)
		DrawText(x, y3, "Render", COL_DIM)
		x += g_charW * 7
		FillRect(x, y3 + 3, bw, g_lineH - 8, &hFF2A2E38ul)
		FillRect(x, y3 + 3, clng(bw * p), g_lineH - 8, COL_ACCENT)
		x += bw + g_charW
		s = clng(int(p * 100)) & "%"
		if compact = false orelse g_job.stage < 2 then s &= " " & st
		DrawText(x, y3, s, COL_TEXT)
		x += TextW(s) + gap
	elseif g_cancelled then
		SEG("Render", "cancelled", COL_WARN)
	elseif g_viewDirty then
		SEG("Render", "pending", COL_DIM)
	else
		SEG("Render", "done", COL_OK)
	end if
	SEG("Time", format(tm, "0.00") & " s", COL_TEXT)
	'' right-aligned note: warnings first, palette name otherwise
	dim note as string = g_pal(g_set.palette).pname
	dim noteCol as ulong = COL_DIM
	if precBad then
		note = "PRECISION TOO LOW FOR THIS ZOOM" : noteCol = COL_WARN
		if x + TextW(note) + 8 >= g_W then note = "PRECISION TOO LOW"
		if x + TextW(note) + 8 >= g_W then note = "LOW!"
	elseif g_job.nBad > 0 then
		note = g_job.nBad & " unstable pixels" : noteCol = COL_WARN
	end if
	if x + TextW(note) + 8 < g_W then DrawText(g_W - 8 - TextW(note), y3, note, noteCol)
end sub

sub Draw_Fractal()
	FillRect(0, 0, g_W, g_imgH, &hFF101018ul)
	if g_tex = 0 then exit sub
	dim as double k, sx, sy
	if ShownRelation(k, sx, sy) = false then exit sub
	if k < 1.0 / 256 then exit sub
	'' visible part of the shown image
	dim as double cx0 = (g_shownW - 1) * 0.5, cy0 = (g_shownH - 1) * 0.5
	dim as long ox0 = clng(floor((0 - sx) / k + cx0)) - 1, ox1 = clng(ceil((g_imgW - 1 - sx) / k + cx0)) + 1
	dim as long oy0 = clng(floor((0 - sy) / k + cy0)) - 1, oy1 = clng(ceil((g_imgH - 1 - sy) / k + cy0)) + 1
	if ox0 < 0 then ox0 = 0
	if oy0 < 0 then oy0 = 0
	if ox1 > g_shownW - 1 then ox1 = g_shownW - 1
	if oy1 > g_shownH - 1 then oy1 = g_shownH - 1
	if ox1 < ox0 orelse oy1 < oy0 then exit sub
	dim as SDL_Rect src, dst, clip
	src.x = ox0 : src.y = oy0 : src.w = ox1 - ox0 + 1 : src.h = oy1 - oy0 + 1
	dim as double lx = sx + (ox0 - cx0) * k - k * 0.5 + 0.5, ty = sy + (oy0 - cy0) * k - k * 0.5 + 0.5
	dst.x = clng(floor(lx + 0.5)) : dst.y = clng(floor(ty + 0.5))
	dst.w = clng(floor(lx + src.w * k + 0.5)) - dst.x
	dst.h = clng(floor(ty + src.h * k + 0.5)) - dst.y
	if dst.w < 1 orelse dst.h < 1 then exit sub
	clip.x = 0 : clip.y = 0 : clip.w = g_imgW : clip.h = g_imgH
	SDL_RenderSetClipRect(g_ren, @clip)
	SDL_RenderCopy(g_ren, g_tex, @src, @dst)
	SDL_RenderSetClipRect(g_ren, 0)
end sub

sub Draw_ExportOverlay()
	dim st as string
	dim p as double = Job_Progress(g_export.job, st)
	dim as long w = 52 * g_charW, h = g_lineH * 5 + 12
	dim as long x = (g_W - w) \ 2, y = (g_H - h) \ 2
	Panel(x, y, w, h)
	DrawText(x + g_lineH, y + g_lineH \ 2, "Exporting " & g_export.outW & " x " & g_export.outH & _
		iif(g_export.ss > 1, "  (" & g_export.ss & "x supersampling)", ""), COL_ACCENT)
	FillRect(x + g_lineH, y + g_lineH * 2, w - g_lineH * 2, g_lineH, &hFF2A2E38ul)
	FillRect(x + g_lineH, y + g_lineH * 2, clng((w - g_lineH * 2) * p), g_lineH, COL_ACCENT)
	DrawText(x + g_lineH, y + g_lineH * 3 + 4, clng(int(p * 100)) & "%  " & st & "   " & _
		format(timer - g_export.job.tStart, "0.0") & " s", COL_TEXT)
	DrawText(x + g_lineH, y + g_lineH * 4 + 4, "Esc = cancel export", COL_DIM)
end sub

sub App_Draw()
	Draw_Fractal()
	Draw_StatusBar()
	if g_showHelp then Draw_Help()
	Menu_Draw()
	Prompt_Draw()
	if g_export.active then Draw_ExportOverlay()
	if timer < g_toastUntil andalso len(g_toast) > 0 then
		dim s as string = g_toast
		dim maxCh as long = (g_W - 40) \ g_charW
		if len(s) > maxCh then s = left(s, maxCh - 3) & "..."
		dim w as long = TextW(s) + g_lineH
		dim as long x = (g_W - w) \ 2, y = g_H - g_barH - g_lineH * 2 - 4
		Panel(x, y, w, g_lineH + 10)
		DrawText(x + g_lineH \ 2, y + 5, s, g_toastCol)
	end if
	SDL_RenderPresent(g_ren)
end sub

'' ---- input -------------------------------------------------------------------------------
sub Key_Menu(byval sym as long)
	select case sym
	case SDLK_ESCAPE : Menu_Close() : Settings_Save(g_set, Settings_File())
	case SDLK_UP : Menu_Move(-1)
	case SDLK_DOWN : Menu_Move(1)
	case SDLK_PAGEUP : g_menu.sel = iif(g_menu.sel - 10 < 0, 0, g_menu.sel - 10) : Menu_FixSel(1)
	case SDLK_PAGEDOWN : g_menu.sel = iif(g_menu.sel + 10 >= g_menu.n, g_menu.n - 1, g_menu.sel + 10) : Menu_FixSel(-1)
	case SDLK_HOME : g_menu.sel = 0 : Menu_FixSel(1)
	case SDLK_END : g_menu.sel = g_menu.n - 1 : Menu_FixSel(-1)
	case SDLK_RETURN, SDLK_KP_ENTER, SDLK_SPACE : Menu_Activate()
	case SDLK_LEFT, SDLK_RIGHT
		dim d as long = iif(sym = SDLK_LEFT, -1, 1)
		if g_menu.kind = MK_SETTINGS then Settings_Adjust(g_menu.it(g_menu.sel).id, d)
		if g_menu.kind = MK_EXPORT then Export_Adjust(g_menu.it(g_menu.sel).id, d)
	case SDLK_TAB
		if g_menu.kind = MK_SETTINGS then Menu_Close() : Settings_Save(g_set, Settings_File())
	case else
		if g_menu.kind = MK_BOOKMARKS then
			dim id as long = g_menu.it(g_menu.sel).id
			select case sym
			case SDLK_DELETE
				if id >= 0 then
					Bookmark_Delete(g_bm(), g_bmCount, id)
					Act_SaveBookmarks()
					Build_Bookmarks()
				end if
			case SDLK_F2
				if id >= 0 then
					g_bmEdit = id
					Menu_Close()
					Prompt_Open(PP_BM_RENAME, "Rename bookmark", g_bm(id).bname)
				end if
			case SDLK_e
				Menu_Close()
				Prompt_Open(PP_BM_EXPORT, "Export bookmarks to file", environ("HOME") & "/mandelbrot-bookmarks.ini")
			case SDLK_i
				Menu_Close()
				Prompt_Open(PP_BM_IMPORT, "Import bookmarks from file", environ("HOME") & "/mandelbrot-bookmarks.ini")
			end select
		end if
	end select
end sub

sub Key_Prompt(byval sym as long, byval md as long)
	select case sym
	case SDLK_ESCAPE : Prompt_Close()
	case SDLK_RETURN, SDLK_KP_ENTER : Prompt_Accept()
	case SDLK_BACKSPACE : Prompt_Backspace()
	case SDLK_v
		if md and KMOD_CTRL then
			dim p as zstring ptr = SDL_GetClipboardText()
			if p then
				dim s as string = *p
				SDL_free(p)
				for i as long = 0 to len(s) - 1
					if s[i] < 32 then s[i] = 32
				next
				if len(g_prompt.txt) + len(s) < 100000 then g_prompt.txt &= trim(s)
			end if
		end if
	case SDLK_u
		if md and KMOD_CTRL then g_prompt.txt = ""
	end select
end sub

sub Key_Main(byval sym as long, byval md as long)
	dim shift as boolean = (md and KMOD_SHIFT) <> 0
	dim stp as double = iif(shift, 0.01, 0.1)
	select case sym
	case SDLK_ESCAPE
		if g_showHelp then
			g_showHelp = false
		elseif g_nuc.running then
			Nuc_Stop()
			Toast("Search cancelled")
		elseif Job_Busy(g_job) then
			Job_Stop(g_job)
			g_cancelled = true
			g_wasBusy = false
			g_recolor = true
			Toast("Render cancelled (Esc again to quit)")
		else
			g_quit = true
		end if
	case SDLK_LEFT : View_Pan(g_view, g_imgH, g_imgW * stp, 0) : App_MarkView()
	case SDLK_RIGHT : View_Pan(g_view, g_imgH, -g_imgW * stp, 0) : App_MarkView()
	case SDLK_UP : View_Pan(g_view, g_imgH, 0, g_imgH * stp) : App_MarkView()
	case SDLK_DOWN : View_Pan(g_view, g_imgH, 0, -g_imgH * stp) : App_MarkView()
	case SDLK_PLUS, SDLK_EQUALS, SDLK_KP_PLUS, SDLK_PAGEUP
		Act_Zoom((g_imgW - 1) * 0.5, (g_imgH - 1) * 0.5, g_set.zoomSpeed)
	case SDLK_MINUS, SDLK_KP_MINUS, SDLK_PAGEDOWN
		Act_Zoom((g_imgW - 1) * 0.5, (g_imgH - 1) * 0.5, 1.0 / g_set.zoomSpeed)
	case SDLK_r, SDLK_HOME : Act_Reset()
	case SDLK_f, SDLK_F11 : Act_Fullscreen()
	case SDLK_c : Act_NextPalette(iif(shift, -1, 1))
	case SDLK_i : Act_SetIter(iif(g_iter > MaxIterCap() \ 2, MaxIterCap(), g_iter * 2))
	case SDLK_k : Act_SetIter(g_iter \ 2)
	case SDLK_t : Prompt_Open(PP_ITER, "Maximum iterations", str(g_iter))
	case SDLK_b : Prompt_Open(PP_BM_NAME, "Bookmark name", "Bookmark " & (g_bmCount + 1))
	case SDLK_o : Build_Bookmarks()
	case SDLK_l : Build_Locations()
	case SDLK_h, SDLK_F1 : g_showHelp = not g_showHelp
	case SDLK_s : Build_Export()
	case SDLK_m : Act_CycleMode()
	case SDLK_TAB : Build_Settings()
	case SDLK_g : Prompt_Open(PP_GOTO_X, "Go to: real part (X)", HpToStr(@g_view.cx), "decimal number, any number of digits")
	case SDLK_a
		g_set.animate = 1 - g_set.animate
		Toast("Palette animation " & OnOff(g_set.animate))
	case SDLK_LEFTBRACKET : g_set.offset = frac(g_set.offset - 0.02 + 1) : g_recolor = true
	case SDLK_RIGHTBRACKET : g_set.offset = frac(g_set.offset + 0.02) : g_recolor = true
	case SDLK_COMMA : g_set.density = ClampD(g_set.density / 1.1, 0.01, 100) : g_recolor = true
	case SDLK_PERIOD : g_set.density = ClampD(g_set.density * 1.1, 0.01, 100) : g_recolor = true
	case SDLK_v : Act_Verify()
	case SDLK_n : Act_FindNucleus()
	case SDLK_1 to SDLK_9
		if sym - SDLK_1 < g_palCount then g_set.palette = sym - SDLK_1 : Act_NextPalette(0)
	end select
end sub

sub App_HandleEvent(byref ev as SDL_Event)
	select case ev.type
	case SDL_QUIT_
		g_quit = true
	case SDL_WINDOWEVENT
		if ev.window.event = SDL_WINDOWEVENT_SIZE_CHANGED then
			dim as long ow = g_imgW, oh = g_imgH
			App_Layout()
			if ow <> g_imgW orelse oh <> g_imgH then App_MarkView()
		end if
	case SDL_TEXTINPUT
		if g_prompt.active andalso (SDL_GetModState() and KMOD_CTRL) = 0 then
			if len(g_prompt.txt) < 100000 then g_prompt.txt &= ev.text.text
		end if
	case SDL_KEYDOWN
		dim sym as long = ev.key.keysym.sym
		dim md as long = ev.key.keysym.mod_
		if g_export.active then
			if sym = SDLK_ESCAPE then Export_Cancel(g_export) : Toast("Export cancelled")
		elseif g_prompt.active then
			Key_Prompt(sym, md)
		elseif g_menu.active then
			Key_Menu(sym)
		else
			Key_Main(sym, md)
		end if
	case SDL_MOUSEWHEEL
		if g_export.active orelse g_prompt.active then exit select
		if g_menu.active then
			Menu_Move(iif(ev.wheel.y > 0, -1, 1))
		elseif ev.wheel.y <> 0 then
			dim as long mx, my
			SDL_GetMouseState(@mx, @my)
			if my * g_dpi < g_imgH then
				g_showHelp = false
				Act_Zoom(mx * g_dpi, my * g_dpi, g_set.zoomSpeed ^ ClampL(ev.wheel.y, -4, 4))
			end if
		end if
	case SDL_MOUSEBUTTONDOWN
		if g_export.active orelse g_prompt.active then exit select
		dim as long mx = ev.button.x * g_dpi, my = ev.button.y * g_dpi
		if g_menu.active then
			dim hit as long = Menu_Hit(mx, my)
			if hit = -2 then
				Menu_Close()
				Settings_Save(g_set, Settings_File())
			elseif hit >= 0 andalso ev.button.button = SDL_BUTTON_LEFT then
				g_menu.sel = hit
				Menu_Activate()
			end if
			exit select
		end if
		g_showHelp = false
		if my >= g_imgH then exit select
		if ev.button.button = SDL_BUTTON_LEFT then
			if ev.button.clicks >= 2 then
				Act_Zoom(mx, my, iif(g_set.zoomSpeed * g_set.zoomSpeed > 2, g_set.zoomSpeed * g_set.zoomSpeed, 2.0))
				g_dragging = false
			else
				g_dragging = true
				g_dragMoved = false
			end if
		elseif ev.button.button = SDL_BUTTON_RIGHT then
			g_menuPX = mx : g_menuPY = my
			Build_Context()
			g_menu.atX = mx : g_menu.atY = my
		elseif ev.button.button = SDL_BUTTON_MIDDLE then
			View_CenterOn(g_view, g_imgW, g_imgH, mx, my)
			App_MarkView()
		end if
	case SDL_MOUSEBUTTONUP
		if ev.button.button = SDL_BUTTON_LEFT then g_dragging = false
	case SDL_MOUSEMOTION
		if g_menu.active then
			dim hit as long = Menu_Hit(ev.motion.x * g_dpi, ev.motion.y * g_dpi)
			if hit >= 0 then g_menu.sel = hit
		elseif g_dragging andalso (ev.motion.state and SDL_BUTTON_LMASK) <> 0 then
			if ev.motion.xrel <> 0 orelse ev.motion.yrel <> 0 then
				View_Pan(g_view, g_imgH, ev.motion.xrel * g_dpi, ev.motion.yrel * g_dpi)
				g_dragMoved = true
				App_MarkView()
			end if
		end if
	end select
end sub

'' ---- adaptive iteration limit ---------------------------------------------------------------
'' Called once when a render completes.  Returns true when a refinement
'' pass with a higher limit was started.
function App_Adapt() as boolean
	Job_Stats(g_job)
	if g_set.adaptiveIter = 0 then return false
	if g_job.nInterior = 0 then return false
	if g_job.maxIter >= MaxIterCap() then return false
	dim total as longint = clngint(g_job.w) * g_job.h
	dim grow as boolean = false
	'' many pixels escaped only shortly before the limit: detail is being cut
	if g_job.nNearLimit * 1000 > total andalso g_adaptCount < 8 then grow = true
	'' nothing escaped at all: probably far too few iterations for this depth
	if g_job.nEscaped = 0 andalso g_job.nInterior = total andalso g_adaptCount < 3 then grow = true
	if grow = false then return false
	g_adaptCount += 1
	g_renderTime += g_job.tElapsed
	g_iter = ClampL(g_job.maxIter * 2, 16, MaxIterCap())
	App_StartRender(true)
	return true
end function

'' ---- start-up / shutdown ---------------------------------------------------------------------
function App_Init() as boolean
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0")
	if SDL_Init(SDL_INIT_VIDEO) <> 0 then
		LogMsg("SDL_Init failed: " & *SDL_GetError())
		return false
	end if
	if TTF_Init() <> 0 then
		LogMsg("TTF_Init failed: " & *SDL_GetError())
		return false
	end if
	dim flags as ulong = SDL_WINDOW_RESIZABLE or SDL_WINDOW_ALLOW_HIGHDPI
	if g_set.fullscreen then flags or= SDL_WINDOW_FULLSCREEN_DESKTOP
	g_win = SDL_CreateWindow(APP_TITLE, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, _
		g_set.winW, g_set.winH, flags)
	if g_win = 0 then
		LogMsg("Cannot create a window: " & *SDL_GetError())
		return false
	end if
	SDL_SetWindowMinimumSize(g_win, 800, 600)
	g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_ACCELERATED or SDL_RENDERER_PRESENTVSYNC)
	if g_ren = 0 then g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_SOFTWARE)
	if g_ren = 0 then
		LogMsg("Cannot create a renderer (unsupported graphics mode?): " & *SDL_GetError())
		return false
	end if
	SDL_SetRenderDrawBlendMode(g_ren, SDL_BLENDMODE_BLEND)
	App_Layout()
	if g_font = 0 then
		LogMsg("Font missing: install fonts-dejavu-core or restore assets/fonts/DejaVuSansMono.ttf")
		return false
	end if
	Help_Init()
	View_Init(g_view)
	g_iter = g_set.maxIter
	return true
end function

sub App_Shutdown()
	Verify_Stop()
	Nuc_Stop()
	if g_export.active then Export_Cancel(g_export)
	Job_Free(g_job)
	if (SDL_GetWindowFlags(g_win) and SDL_WINDOW_FULLSCREEN_DESKTOP) = 0 then
		dim as long ww, wh
		SDL_GetWindowSize(g_win, @ww, @wh)
		g_set.winW = ww : g_set.winH = wh
	end if
	if Settings_Save(g_set, Settings_File()) = false then LogMsg(g_lastError)
	Text_FlushCache()
	if g_tex then SDL_DestroyTexture(g_tex)
	if g_font then TTF_CloseFont(g_font)
	if g_ren then SDL_DestroyRenderer(g_ren)
	if g_win then SDL_DestroyWindow(g_win)
	TTF_Quit()
	SDL_Quit()
end sub

sub App_Run()
	dim ev as SDL_Event
	dim lastDraw as double = 0
	g_lastAnim = timer
	do until g_quit
		dim active as boolean = false
		while SDL_PollEvent(@ev)
			App_HandleEvent(ev)
			active = true
		wend

		'' start (or restart) the accurate render once the view has settled
		if g_viewDirty andalso g_export.active = 0 then
			dim zb as long = View_ZoomBits(g_view, g_imgH)
			dim wait_ as double = iif(ResolveMode(g_set.mode, zb) = MODE_DOUBLE, 0.02, 0.15)
			if g_dragging = false orelse wait_ < 0.1 then
				if timer - g_lastChange >= wait_ orelse g_img = 0 then App_StartRender()
			end if
		end if

		dim busy as boolean = Job_Busy(g_job)
		if busy then
			if timer - g_lastColorize > 0.04 then g_recolor = true
			active = true
		elseif g_wasBusy then
			g_wasBusy = false
			g_recolor = true
			active = true
			if g_job.failed then
				if len(g_job.errMsg) > 0 then Toast("Render failed: " & g_job.errMsg, true)
			elseif g_job.done then
				if App_Adapt() = false then
					g_renderTime += g_job.tElapsed
					if g_job.nBad > 0 then Toast(g_job.nBad & " numerically unstable pixels in this frame", true)
				end if
			end if
		end if

		if g_set.animate then
			dim nowT as double = timer
			g_set.offset = frac(g_set.offset + (nowT - g_lastAnim) * g_set.animSpeed)
			g_lastAnim = nowT
			g_recolor = true
			active = true
		else
			g_lastAnim = timer
		end if

		if g_verify.running andalso g_verify.finished then
			dim as long vn = g_verify.n, vb = g_verify.bad
			dim vd as double = g_verify.maxDiff
			Verify_Stop()
			if vn = 0 then
				Toast("Verification produced no samples")
			elseif vb = 0 then
				Toast("Verified " & vn & " pixels against MPFR: all match (max difference " & format(vd, "0.0e+00") & ")")
			else
				Toast("Verification: " & vb & " of " & vn & " pixels differ from the MPFR reference", true)
			end if
			active = true
		end if

		if g_nuc.running andalso g_nuc.finished then
			dim nf as long = g_nuc.found, np as long = g_nuc.period
			threadwait(g_nuc.thread) : g_nuc.thread = 0
			g_nuc.running = 0 : g_nuc.finished = 0
			if nf then
				dim p as long = mpfr_get_prec(@g_nuc.ox)
				mpfr_set_prec(@g_view.cx, p) : mpfr_set_prec(@g_view.cy, p)
				g_view.prec = p
				mpfr_set(@g_view.cx, @g_nuc.ox, MPFR_RNDN)
				mpfr_set(@g_view.cy, @g_nuc.oy, MPFR_RNDN)
				mpfr_mul_d(@g_view.halfh, @g_nuc.osize, 2.5, MPFR_RNDN)
				View_AutoPrec(g_view, g_imgH)
				if g_iter < np * 4 + 500 then g_iter = ClampL(np * 4 + 500, 16, MaxIterCap())
				Toast("Mini-Mandelbrot of period " & np & ", size " & HpShort(@g_nuc.osize, 3))
				App_MarkView()
			else
				Toast("No mini-Mandelbrot found in this view")
			end if
			active = true
		end if

		if g_export.active then
			active = true
			dim r as long = Export_Poll(g_export)
			if r <> 0 then Toast(g_export.resultMsg, r < 0, 8)
		end if

		if g_recolor then App_Recolor()
		if timer < g_toastUntil then active = true
		if active orelse g_viewDirty orelse timer - lastDraw > 0.25 then
			App_Draw()
			lastDraw = timer
		else
			SDL_Delay(8)
		end if
	loop
end sub
