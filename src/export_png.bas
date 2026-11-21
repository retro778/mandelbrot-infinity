'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - PNG export (libpng simplified API)
''
'' An export is a separate RenderJob at the requested resolution (times the
'' supersampling factor), computed by the same renderers as the screen
'' image - never an enlarged screenshot.  The pixels are box-filtered down,
'' written with libpng, and the exact parameters go to "<file>.txt".
'' ---------------------------------------------------------------------------
#include once "common.bi"
#include once "png16.bi"
#include once "string.bi"

type ExportJob
	job as RenderJob
	active as long
	outW as long
	outH as long
	ss as long
	alpha as long
	path as string
	palette as long
	density as double
	offset as double
	modeReq as long
	resultMsg as string
end type

function SavePng(byref fname as string, byval pix as ubyte ptr, byval w as long, byval h as long, _
		byref errMsg as string) as boolean
	dim img as png_image
	memset(@img, 0, sizeof(img))
	img.version = PNG_IMAGE_VERSION
	img.width = w
	img.height = h
	img.format = PNG_FORMAT_RGBA
	if png_image_write_to_file(@img, strptr(fname), 0, pix, 0, 0) = 0 then
		errMsg = "PNG write failed: " & img.message
		return false
	end if
	return true
end function

'' Colour the t() buffer of a finished job and reduce it by ss x ss.
'' Returns an RGBA byte buffer (caller frees) or 0 when out of memory.
function Export_MakeRGBA(byref job as RenderJob, byval outW as long, byval outH as long, _
		byval ss as long, byval pal as long, byval dens as double, byval offs as double, _
		byval alpha as long) as ubyte ptr
	dim buf as ubyte ptr = allocate(clngint(outW) * outH * 4)
	if buf = 0 then return 0
	if pal < 0 orelse pal >= g_palCount then pal = 0
	dim tbl as ulong ptr = g_pal(pal).tbl
	dim inv as double = 1.0 / (ss * ss)
	for y as long = 0 to outH - 1
		for x as long = 0 to outW - 1
			dim as long sr = 0, sg = 0, sb = 0, sa = 0
			for yy as long = 0 to ss - 1
				dim row as single ptr = job.t + clngint(y * ss + yy) * job.w
				for xx as long = 0 to ss - 1
					dim tv as single = row[x * ss + xx]
					if tv >= 0 then
						dim c as ulong = PAL_COLOR(tbl, tv, dens, offs)
						sr += (c shr 16) and 255
						sg += (c shr 8) and 255
						sb += c and 255
						sa += 255
					elseif alpha = 0 then
						sa += 255         '' opaque black interior
					end if
				next
			next
			dim o as ubyte ptr = buf + (clngint(y) * outW + x) * 4
			if alpha <> 0 andalso sa > 0 andalso sa < 255 * ss * ss then
				'' partially covered pixel: un-premultiply the colour
				dim cov as double = 255.0 / sa
				o[0] = clng(sr * cov) : o[1] = clng(sg * cov) : o[2] = clng(sb * cov)
			else
				o[0] = clng(sr * inv) : o[1] = clng(sg * inv) : o[2] = clng(sb * inv)
			end if
			o[3] = clng(sa * inv)
		next
	next
	return buf
end function

function WriteMetadata(byref fname as string, byref job as RenderJob, byval outW as long, _
		byval outH as long, byval ss as long, byval pal as long, byval dens as double, _
		byval offs as double, byval alpha as long) as boolean
	dim f as long = freefile
	if open(fname for output as #f) <> 0 then return false
	print #f, "# " & APP_TITLE & " " & APP_VERSION & " - image parameters"
	print #f, "date=" & date & " " & time
	print #f, "x=" & HpToStr(@job.view.cx)
	print #f, "y=" & HpToStr(@job.view.cy)
	print #f, "half_height=" & HpToStrShortest(@job.view.halfh)
	print #f, "zoom=" & View_ZoomStr(job.view, 12)
	print #f, "max_iterations=" & job.maxIter
	print #f, "mode=" & ModeName(job.mode)
	print #f, "precision_bits=" & iif(job.mode = MODE_DOUBLE, 53, job.prec)
	print #f, "guard_bits=" & g_set.guardBits
	print #f, "bailout_radius=" & BAILOUT_R
	print #f, "width=" & outW
	print #f, "height=" & outH
	print #f, "supersampling=" & ss
	if pal >= 0 andalso pal < g_palCount then print #f, "palette=" & g_pal(pal).pname
	print #f, "color_density=" & dens
	print #f, "color_offset=" & offs
	print #f, "color_transfer=" & job.transfer
	print #f, "color_base=" & job.nuBase
	print #f, "transparent_interior=" & alpha
	print #f, "render_seconds=" & format(job.tElapsed, "0.000")
	close #f
	return true
end function

'' Start an export.  Returns false (resultMsg set) when it cannot start.
function Export_Begin(byref ex as ExportJob, byref v as ViewState, byval outW as long, _
		byval outH as long, byval ss as long, byval maxIter as long, byval modeReq as long, _
		byref path as string, byval colourBase as double = -1) as boolean
	ex.outW = outW : ex.outH = outH
	ex.ss = ClampL(ss, 1, 8)
	ex.alpha = g_set.exportAlpha
	ex.path = path
	ex.palette = g_set.palette
	ex.density = g_set.density
	ex.offset = g_set.offset
	ex.modeReq = modeReq
	ex.resultMsg = ""
	'' the view keeps its vertical extent; make sure the centre has enough
	'' bits for the (usually larger) export height
	dim v2 as ViewState
	View_Copy(v2, v)
	View_AutoPrec(v2, outH * ex.ss)
	if colourBase < 0 then
		'' no colour origin supplied: measure it on a small preview render
		dim pre as RenderJob
		dim pw as long = 160, ph as long = ClampL(clng(160.0 * outH / outW), 16, 1600)
		if Job_Start(pre, v2, pw, ph, modeReq, maxIter, 0, 1) then
			Job_Wait(pre)
			colourBase = pre.nuBase
		end if
		Job_Free(pre)
		if colourBase < 0 then colourBase = 0
	end if
	dim ok as boolean = Job_Start(ex.job, v2, outW * ex.ss, outH * ex.ss, modeReq, maxIter, 0, 0, colourBase)
	View_Clear(v2)
	if ok = false then
		ex.resultMsg = "Export failed: " & ex.job.errMsg
		ex.active = 0
		return false
	end if
	ex.active = 1
	return true
end function

sub Export_Cancel(byref ex as ExportJob)
	if ex.active = 0 then exit sub
	Job_Stop(ex.job)
	ex.active = 0
	ex.resultMsg = "Export cancelled"
	'' release the (possibly very large) buffers
	if ex.job.t then deallocate(ex.job.t) : ex.job.t = 0
	ex.job.bufW = 0 : ex.job.bufH = 0
end sub

'' Call regularly.  Returns 0 while rendering, 1 when the file was written,
'' -1 on failure; resultMsg describes the outcome.
function Export_Poll(byref ex as ExportJob) as long
	if ex.active = 0 then return -1
	if Job_Busy(ex.job) then return 0
	dim okJob as boolean = (ex.job.done <> 0 andalso ex.job.failed = 0)
	Job_Stop(ex.job)
	ex.active = 0
	dim res as long = -1
	if okJob = false then
		ex.resultMsg = "Export failed: " & iif(len(ex.job.errMsg) > 0, ex.job.errMsg, "render did not finish")
	else
		dim pix as ubyte ptr = Export_MakeRGBA(ex.job, ex.outW, ex.outH, ex.ss, ex.palette, _
			ex.density, ex.offset, ex.alpha)
		if pix = 0 then
			ex.resultMsg = "Export failed: out of memory"
		else
			dim e as string
			if SavePng(ex.path, pix, ex.outW, ex.outH, e) then
				if WriteMetadata(ex.path & ".txt", ex.job, ex.outW, ex.outH, ex.ss, ex.palette, _
						ex.density, ex.offset, ex.alpha) then
					ex.resultMsg = "Saved " & ex.path
				else
					ex.resultMsg = "Saved " & ex.path & " (metadata file could not be written)"
				end if
				res = 1
			else
				ex.resultMsg = "Export failed: " & e
			end if
			deallocate(pix)
		end if
	end if
	if ex.job.t then deallocate(ex.job.t) : ex.job.t = 0
	ex.job.bufW = 0 : ex.job.bufH = 0
	return res
end function
