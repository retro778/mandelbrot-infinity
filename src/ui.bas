'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - SDL2 user interface building blocks
'' Text (SDL2_ttf with a small texture cache), panels, list menus, a text
'' prompt and toast messages.  Everything here runs on the main thread.
'' ---------------------------------------------------------------------------
#include once "common.bi"
#include once "SDL2/SDL.bi"
#include once "SDL2/SDL_ttf.bi"

dim shared g_win as SDL_Window ptr
dim shared g_ren as SDL_Renderer ptr
dim shared g_font as TTF_Font ptr
dim shared g_W as long, g_H as long          '' renderer output size in pixels
dim shared g_dpi as double = 1.0             '' output pixels per window unit
dim shared g_lineH as long = 18
dim shared g_charW as long = 8

const COL_TEXT = &hFFE6E8EEul
const COL_DIM = &hFF9AA0AEul
const COL_ACCENT = &hFF5CC8FFul
const COL_WARN = &hFFFF6B5Eul
const COL_OK = &hFF7BE08Aul
const COL_PANEL = &hEE14161Cul
const COL_BAR = &hFF14161Cul
const COL_SEL = &hFF2A4C6Eul
const COL_BORDER = &hFF3A3F4Cul

'' ---- primitives -----------------------------------------------------------------
sub SetColor(byval c as ulong)
	SDL_SetRenderDrawColor(g_ren, (c shr 16) and 255, (c shr 8) and 255, c and 255, (c shr 24) and 255)
end sub

sub GfxFill(byval x as long, byval y as long, byval w as long, byval h as long, byval c as ulong)
	dim r as SDL_Rect
	r.x = x : r.y = y : r.w = w : r.h = h
	SetColor(c)
	SDL_RenderFillRect(g_ren, @r)
end sub

sub GfxFrame(byval x as long, byval y as long, byval w as long, byval h as long, byval c as ulong)
	dim r as SDL_Rect
	r.x = x : r.y = y : r.w = w : r.h = h
	SetColor(c)
	SDL_RenderDrawRect(g_ren, @r)
end sub

'' ---- text ------------------------------------------------------------------------
const TEXT_CACHE = 160
type TextEntry
	txt as string
	col as ulong
	tex as SDL_Texture ptr
	w as long
	h as long
	stamp as longint
end type
dim shared g_tc(0 to TEXT_CACHE - 1) as TextEntry
dim shared g_tcStamp as longint = 0

sub Text_FlushCache()
	for i as long = 0 to TEXT_CACHE - 1
		if g_tc(i).tex then SDL_DestroyTexture(g_tc(i).tex)
		g_tc(i).tex = 0
		g_tc(i).txt = ""
	next
end sub

function Font_Load(byval px as long) as boolean
	dim cand(0 to 5) as string
	cand(4) = EnvDir("WINDIR") & "/Fonts/consola.ttf"
	cand(5) = EnvDir("WINDIR") & "/Fonts/cour.ttf"
	cand(0) = g_baseDir & "/assets/fonts/DejaVuSansMono.ttf"
	cand(1) = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
	cand(2) = "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"
	cand(3) = "/usr/share/fonts/TTF/DejaVuSansMono.ttf"
	if g_font then TTF_CloseFont(g_font) : g_font = 0
	Text_FlushCache()
	for i as long = 0 to 5
		g_font = TTF_OpenFont(strptr(cand(i)), px)
		if g_font then exit for
	next
	if g_font = 0 then return false
	g_lineH = TTF_FontLineSkip(g_font)
	dim as long tw, th
	TTF_SizeUTF8(g_font, "M", @tw, @th)
	g_charW = iif(tw > 0, tw, 8)
	return true
end function

function TextW(byref s as string) as long
	'' monospace font: count UTF-8 code points
	dim n as long = 0
	for i as long = 0 to len(s) - 1
		if (s[i] and &hC0) <> &h80 then n += 1
	next
	return n * g_charW
end function

sub GfxText(byval x as long, byval y as long, byref s as string, byval col as ulong = COL_TEXT)
	if len(s) = 0 orelse g_font = 0 then exit sub
	g_tcStamp += 1
	dim slot as long = -1, oldest as long = 0
	for i as long = 0 to TEXT_CACHE - 1
		if g_tc(i).tex <> 0 andalso g_tc(i).col = col andalso g_tc(i).txt = s then
			slot = i
			exit for
		end if
		if g_tc(i).stamp < g_tc(oldest).stamp then oldest = i
	next
	if slot < 0 then
		slot = oldest
		if g_tc(slot).tex then SDL_DestroyTexture(g_tc(slot).tex) : g_tc(slot).tex = 0
		dim c as SDL_Color
		c.r = (col shr 16) and 255 : c.g = (col shr 8) and 255 : c.b = col and 255 : c.a = 255
		dim surf as SDL_Surface ptr = TTF_RenderUTF8_Blended(g_font, strptr(s), c)
		if surf = 0 then exit sub
		g_tc(slot).tex = SDL_CreateTextureFromSurface(g_ren, surf)
		g_tc(slot).w = surf->w
		g_tc(slot).h = surf->h
		SDL_FreeSurface(surf)
		if g_tc(slot).tex = 0 then exit sub
		g_tc(slot).txt = s
		g_tc(slot).col = col
	end if
	g_tc(slot).stamp = g_tcStamp
	dim r as SDL_Rect
	r.x = x : r.y = y : r.w = g_tc(slot).w : r.h = g_tc(slot).h
	SDL_RenderCopy(g_ren, g_tc(slot).tex, 0, @r)
end sub

sub Panel(byval x as long, byval y as long, byval w as long, byval h as long)
	GfxFill(x, y, w, h, COL_PANEL)
	GfxFrame(x, y, w, h, COL_BORDER)
end sub

'' ---- toast ------------------------------------------------------------------------
dim shared g_toast as string
dim shared g_toastUntil as double = 0
dim shared g_toastCol as ulong = COL_TEXT

sub Toast(byref s as string, byval isError as boolean = false, byval secs as double = 4.0)
	g_toast = s
	g_toastCol = iif(isError, COL_WARN, COL_TEXT)
	g_toastUntil = timer + iif(isError, secs + 3, secs)
	if isError then LogMsg(s)
end sub

'' ---- list menu ----------------------------------------------------------------------
const MENU_MAX = 96
type MenuItem
	label as string
	value as string
	id as long
	sep as long                '' non-selectable heading / separator
end type

type Menu
	active as long
	kind as long
	title as string
	hint as string
	n as long
	it(0 to MENU_MAX - 1) as MenuItem
	sel as long
	scroll as long
	atX as long                '' -1 = centred
	atY as long
	'' layout (computed while drawing, used for mouse hit tests)
	x as long
	y as long
	w as long
	h as long
	rowY as long
	rows as long
end type

dim shared g_menu as Menu

sub Menu_Begin(byval kind as long, byref title as string, byref hint as string = "")
	dim keepSel as long = iif(g_menu.active <> 0 andalso g_menu.kind = kind, g_menu.sel, 0)
	dim keepScroll as long = iif(g_menu.active <> 0 andalso g_menu.kind = kind, g_menu.scroll, 0)
	if g_menu.active = 0 orelse g_menu.kind <> kind then g_menu.atX = -1
	g_menu.active = 1
	g_menu.kind = kind
	g_menu.title = title
	g_menu.hint = hint
	g_menu.n = 0
	g_menu.sel = keepSel
	g_menu.scroll = keepScroll
end sub

sub Menu_Add(byref label as string, byval id as long, byref value as string = "", byval sep as long = 0)
	if g_menu.n >= MENU_MAX then exit sub
	with g_menu.it(g_menu.n)
		.label = label
		.value = value
		.id = id
		.sep = sep
	end with
	g_menu.n += 1
end sub

sub Menu_FixSel(byval dirn as long = 1)
	if g_menu.n = 0 then g_menu.sel = 0 : exit sub
	if g_menu.sel < 0 then g_menu.sel = 0
	if g_menu.sel >= g_menu.n then g_menu.sel = g_menu.n - 1
	dim guard as long = 0
	while g_menu.it(g_menu.sel).sep <> 0 andalso guard < g_menu.n
		g_menu.sel = (g_menu.sel + dirn + g_menu.n) mod g_menu.n
		guard += 1
	wend
end sub

sub Menu_Move(byval d as long)
	if g_menu.n = 0 then exit sub
	g_menu.sel = (g_menu.sel + d + g_menu.n) mod g_menu.n
	Menu_FixSel(iif(d < 0, -1, 1))
end sub

sub Menu_Close()
	g_menu.active = 0
end sub

sub Menu_Draw()
	if g_menu.active = 0 then exit sub
	Menu_FixSel()
	dim as long pad = g_lineH \ 2, rowH = g_lineH + 4
	dim wch as long = len(g_menu.title) + 2
	for i as long = 0 to g_menu.n - 1
		dim l as long = TextW(g_menu.it(i).label) \ g_charW + TextW(g_menu.it(i).value) \ g_charW + 6
		if l > wch then wch = l
	next
	if len(g_menu.hint) + 2 > wch then wch = len(g_menu.hint) + 2
	dim w as long = wch * g_charW + pad * 2
	if w > g_W - 20 then w = g_W - 20
	dim maxRows as long = (g_H - 6 * g_lineH) \ rowH
	if maxRows < 3 then maxRows = 3
	dim rows as long = iif(g_menu.n < maxRows, g_menu.n, maxRows)
	if g_menu.sel < g_menu.scroll then g_menu.scroll = g_menu.sel
	if g_menu.sel >= g_menu.scroll + rows then g_menu.scroll = g_menu.sel - rows + 1
	if g_menu.scroll > g_menu.n - rows then g_menu.scroll = g_menu.n - rows
	if g_menu.scroll < 0 then g_menu.scroll = 0
	dim h as long = pad * 2 + g_lineH + 6 + rows * rowH + iif(len(g_menu.hint) > 0, g_lineH + 6, 0)
	dim as long x, y
	if g_menu.atX >= 0 then
		x = g_menu.atX : y = g_menu.atY
		if x + w > g_W - 4 then x = g_W - 4 - w
		if y + h > g_H - 4 then y = g_H - 4 - h
		if x < 4 then x = 4
		if y < 4 then y = 4
	else
		x = (g_W - w) \ 2
		y = (g_H - h) \ 2
	end if
	Panel(x, y, w, h)
	GfxText(x + pad, y + pad, g_menu.title, COL_ACCENT)
	GfxFill(x + 1, y + pad + g_lineH + 2, w - 2, 1, COL_BORDER)
	dim ry as long = y + pad + g_lineH + 6
	g_menu.x = x : g_menu.y = y : g_menu.w = w : g_menu.h = h
	g_menu.rowY = ry : g_menu.rows = rows
	for r as long = 0 to rows - 1
		dim i as long = g_menu.scroll + r
		dim yy as long = ry + r * rowH
		if g_menu.it(i).sep then
			GfxText(x + pad, yy + 2, g_menu.it(i).label, COL_DIM)
			continue for
		end if
		if i = g_menu.sel then GfxFill(x + 2, yy, w - 4, rowH, COL_SEL)
		GfxText(x + pad, yy + 2, g_menu.it(i).label, COL_TEXT)
		if len(g_menu.it(i).value) > 0 then
			GfxText(x + w - pad - TextW(g_menu.it(i).value), yy + 2, g_menu.it(i).value, COL_ACCENT)
		end if
	next
	if g_menu.n > rows then
		'' scroll indicator
		dim as long th = rows * rowH
		dim as long kh = th * rows \ g_menu.n
		dim as long ky = th * g_menu.scroll \ g_menu.n
		GfxFill(x + w - 4, ry + ky, 3, iif(kh < 8, 8, kh), COL_BORDER)
	end if
	if len(g_menu.hint) > 0 then
		GfxText(x + pad, ry + rows * rowH + 4, g_menu.hint, COL_DIM)
	end if
end sub

'' Item index under a point, -1 for none, -2 when outside the menu.
function Menu_Hit(byval mx as long, byval my as long) as long
	if mx < g_menu.x orelse mx >= g_menu.x + g_menu.w orelse my < g_menu.y orelse my >= g_menu.y + g_menu.h then return -2
	dim rowH as long = g_lineH + 4
	if my < g_menu.rowY then return -1
	dim r as long = (my - g_menu.rowY) \ rowH
	if r >= g_menu.rows then return -1
	dim i as long = g_menu.scroll + r
	if i >= g_menu.n orelse g_menu.it(i).sep then return -1
	return i
end function

'' ---- text prompt ---------------------------------------------------------------------
type Prompt
	active as long
	purpose as long
	title as string
	info as string
	txt as string
end type
dim shared g_prompt as Prompt

sub Prompt_Open(byval purpose as long, byref title as string, byref initial as string = "", _
		byref info as string = "")
	g_prompt.active = 1
	g_prompt.purpose = purpose
	g_prompt.title = title
	g_prompt.info = info
	g_prompt.txt = initial
	SDL_StartTextInput()
end sub

sub Prompt_Close()
	g_prompt.active = 0
	SDL_StopTextInput()
end sub

sub Prompt_Backspace()
	dim l as long = len(g_prompt.txt)
	if l = 0 then exit sub
	l -= 1
	'' do not cut a UTF-8 sequence in half
	while l > 0 andalso (g_prompt.txt[l] and &hC0) = &h80
		l -= 1
	wend
	g_prompt.txt = left(g_prompt.txt, l)
end sub

sub Prompt_Draw()
	if g_prompt.active = 0 then exit sub
	dim pad as long = g_lineH \ 2
	dim w as long = g_W * 3 \ 4
	if w < 60 * g_charW then w = 60 * g_charW
	if w > g_W - 20 then w = g_W - 20
	dim h as long = pad * 2 + g_lineH * 3 + 16 + iif(len(g_prompt.info) > 0, g_lineH, 0)
	dim as long x = (g_W - w) \ 2, y = (g_H - h) \ 2
	Panel(x, y, w, h)
	GfxText(x + pad, y + pad, g_prompt.title, COL_ACCENT)
	dim yy as long = y + pad + g_lineH + 4
	if len(g_prompt.info) > 0 then
		GfxText(x + pad, yy, g_prompt.info, COL_DIM)
		yy += g_lineH
	end if
	GfxFill(x + pad, yy, w - pad * 2, g_lineH + 8, &hFF0B0C10ul)
	GfxFrame(x + pad, yy, w - pad * 2, g_lineH + 8, COL_BORDER)
	'' show the tail when the text is wider than the box
	dim maxCh as long = (w - pad * 2 - 12) \ g_charW - 1
	dim s as string = g_prompt.txt
	dim cut as long = 0
	while TextW(s) \ g_charW > maxCh
		cut += 1
		s = mid(g_prompt.txt, cut + 1)
		while len(s) > 0 andalso (s[0] and &hC0) = &h80
			cut += 1
			s = mid(g_prompt.txt, cut + 1)
		wend
	wend
	if cut > 0 then s = "<" & mid(s, 2)
	GfxText(x + pad + 6, yy + 4, s & "_", COL_TEXT)
	GfxText(x + pad, yy + g_lineH + 12, "Enter = OK    Esc = cancel    Ctrl+V = paste", COL_DIM)
end sub
