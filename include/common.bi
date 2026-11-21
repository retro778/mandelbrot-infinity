'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - shared constants, types and declarations (engine)
'' Copyright (c) 2026 retro778 - MIT License
'' ---------------------------------------------------------------------------
#pragma once
#include once "crt/math.bi"
#include once "crt/string.bi"
#include once "crt/stdlib.bi"
#include once "crt/linux/unistd.bi"
#include once "mpfr_bindings.bi"

const APP_NAME = "Mandelbrot Infinity"
const APP_TITLE = "Mandelbrot Infinity - Deep Zoom Explorer"
const APP_VERSION = "1.0.1"
const APP_DIRNAME = "mandelbrot-infinity"

'' ---- numerical rendering modes -------------------------------------------
const MODE_AUTO = 0       '' pick DOUBLE / PERTURB / MPFR from the zoom depth
const MODE_DOUBLE = 1     '' native double precision
const MODE_MPFR = 2       '' full arbitrary precision reference renderer
const MODE_PERTURB = 3    '' MPFR reference orbit + double perturbation

'' ---- per pixel result encoding (smooth iteration value "nu") --------------
const NU_PENDING as double = -2      '' not computed yet
const NU_INTERIOR as double = -1     '' reached the iteration limit
const NU_KNOWN_IN as double = -3     '' proven interior (cardioid / bulb / cycle)

'' The set is defined by |z| <= 2.  Iteration continues to a larger radius
'' because the smooth colouring formula converges much better there; an
'' orbit that leaves radius 2 always reaches the larger radius, so the
'' classification is unchanged.
const BAILOUT_R as double = 256.0
const BAILOUT_R2 as double = 65536.0

'' Home view: centre (-0.5, 0), half height 1.25.  "Zoom" shown to the user
'' is HOME_HALFH / half_height, i.e. magnification relative to the home view.
const HOME_HALFH as double = 1.25

'' AUTO uses double while a pixel is at least 2^-DOUBLE_MAX_ZBITS wide (rounding
'' then stays below about 1/1000 pixel); beyond DOUBLE_LIMIT_ZBITS double
'' cannot separate neighbouring pixels reliably and a warning is shown.
const DOUBLE_MAX_ZBITS = 32
const DOUBLE_LIMIT_ZBITS = 44

const TRANSFER_LINEAR = 0
const TRANSFER_SQRT = 1
const TRANSFER_SOFTLOG = 2

const PAL_SIZE = 8192

'' ---- settings -------------------------------------------------------------
type Settings
	threads as long          '' 0 = one per CPU core
	tileSize as long         '' pixels, multiple of 16
	previewStep as long      '' first progressive block size: 1,2,4,8,16
	guardBits as long        '' extra MPFR bits beyond the pixel spacing
	fixedPrec as long        '' 0 = automatic, else forced MPFR precision
	zoomSpeed as double      '' zoom factor per wheel notch
	memLimitMB as long       '' soft memory limit for buffers / orbits
	periodicity as long      '' periodicity check in double mode
	usePerturb as long       '' AUTO may use perturbation for deep zoom
	useSeries as long        '' series approximation in perturbation mode
	adaptiveIter as long     '' automatically raise the iteration limit
	maxIter as long
	mode as long
	palette as long
	density as double        '' colour intensity (palette cycles multiplier)
	offset as double         '' palette offset 0..1
	animate as long
	animSpeed as double      '' palette cycles per second
	transfer as long
	winW as long
	winH as long
	fullscreen as long
	exportW as long
	exportH as long
	exportSS as long
	exportAlpha as long
	exportDir as string
end type

'' ---- view (always arbitrary precision) -------------------------------------
type ViewState
	cx as mpfr_t             '' centre, real part
	cy as mpfr_t             '' centre, imaginary part
	halfh as mpfr_t          '' half of the view height in the complex plane
	prec as long             '' precision of cx / cy in bits
	valid as long
end type

'' ---- reference orbit for perturbation -------------------------------------
type RefOrbit
	zr as double ptr         '' Z_0 .. Z_n (double copies of the MPFR orbit)
	zi as double ptr
	n as long                '' last valid index
	cap as long
	escaped as long          '' reference left the bailout radius at index n
	'' orbit entries too small for the fast path (|Z| < 1e-60), mantissa*2^exp
	nTiny as long
	tinyIdx as long ptr
	tinyR as double ptr
	tinyI as double ptr
	tinyE as long ptr
	tinyCap as long
	'' MPFR state so the orbit can be extended without restarting
	inited as long
	prec as long
	mcr as mpfr_t
	mci as mpfr_t
	mzr as mpfr_t
	mzi as mpfr_t
	t1 as mpfr_t
	t2 as mpfr_t
	'' series approximation (scaled coefficients, see perturbation.bas)
	saSkip as long
	saR as double            '' image radius = saR * 2^saE
	saE as long
	cfAr as double
	cfAi as double
	cfBr as double
	cfBi as double
	cfCr as double
	cfCi as double
end type

'' ---- render job ------------------------------------------------------------
type RenderJob
	'' parameters (fixed while the job runs)
	w as long
	h as long
	mode as long             '' effective mode (never MODE_AUTO)
	maxIter as long
	prec as long             '' MPFR working precision in bits
	nThreads as long
	tileSize as long
	firstStep as long
	periodicity as long
	useSeries as long
	transfer as long
	refineOnly as long       '' recompute only pixels that hit the old limit
	nuBase as double         '' lowest iteration value of the frame (colour origin)
	baseFixed as long        '' 1 = nuBase was supplied by the caller
	zbits as long            '' ceil(log2(1 / pixel size))
	precOK as long           '' 0 = precision insufficient for this zoom
	'' view copy
	view as ViewState
	ps as mpfr_t             '' pixel size (MPFR)
	psInited as long
	cxd as double
	cyd as double
	psd as double
	psMant as double         '' pixel size = psMant * 2^psExp
	psExp as long
	'' result buffers
	nu as double ptr         '' may be 0 when only t() is wanted
	t as single ptr          '' transfer(nu); < 0 for pending / interior
	bufW as long
	bufH as long
	'' scheduling
	gen as long
	cancel as long
	running as long
	done as long             '' all passes finished (not cancelled)
	failed as long
	errMsg as string
	mutex as any ptr
	threads(0 to 63) as any ptr
	nStarted as long
	stage as long            '' 0 = reference needed, 1 = in progress, 2 = ready
	pass as long
	nPasses as long
	nextTile as long
	tilesDone as long
	nTiles as long
	tileX as long ptr
	tileY as long ptr
	pixDone as longint
	pixTotal as longint
	refProgress as long
	tStart as double
	tElapsed as double
	ref as RefOrbit
	'' statistics (valid after Job_Stats)
	nInterior as longint
	nEscaped as longint
	nNearLimit as longint
	nBad as longint
	nuMin as double
	nuMax as double
end type

type Bookmark
	bname as string
	x as string              '' decimal strings - never routed through DOUBLE
	y as string
	halfh as string
	maxIter as long
	palette as string
	precBits as long         '' render precision that was in use
	guardBits as long
	coordBits as long        '' precision of x / y (0 = derive from the digits)
end type

declare sub LogMsg(byref s as string)
