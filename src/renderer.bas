'' ---------------------------------------------------------------------------
'' Mandelbrot Infinity - render jobs: worker threads, tiles, progressive passes
''
'' A RenderJob owns its result buffers and a pool of worker threads.  Work
'' is handed out as (pass, tile) tasks under a mutex.  Passes go from coarse
'' blocks (previewStep) down to single pixels; a pass only starts when every
'' tile of the previous pass is finished, so block fills never overwrite
'' finer results.  Workers poll job.cancel; Job_Stop sets it and joins all
'' threads, and every job start gets a new generation id so a stale worker
'' can never write into a newer frame.  Workers only touch the nu()/t()
'' buffers - all SDL calls stay on the main thread.
'' ---------------------------------------------------------------------------
#include once "common.bi"

dim shared g_genCounter as long = 0

const TASK_EXIT = 0
const TASK_WAIT = 1
const TASK_REF = 2
const TASK_TILE = 3

type WorkerArg
	job as RenderJob ptr
	gen as long
end type

sub Job_Init(byref job as RenderJob)
	if job.mutex = 0 then job.mutex = mutexcreate()
end sub

sub Job_Stop(byref job as RenderJob)
	job.cancel = 1
	for i as long = 0 to job.nStarted - 1
		if job.threads(i) then
			threadwait(job.threads(i))
			job.threads(i) = 0
		end if
	next
	job.nStarted = 0
	if job.running then
		job.running = 0
		job.tElapsed = timer - job.tStart
	end if
end sub

sub Job_Free(byref job as RenderJob)
	Job_Stop(job)
	if job.nu then deallocate(job.nu) : job.nu = 0
	if job.t then deallocate(job.t) : job.t = 0
	if job.tileX then deallocate(job.tileX) : job.tileX = 0
	if job.tileY then deallocate(job.tileY) : job.tileY = 0
	job.bufW = 0 : job.bufH = 0
	Ref_Free(job.ref)
	View_Clear(job.view)
	if job.psInited then mpfr_clear(@job.ps) : job.psInited = 0
	if job.mutex then mutexdestroy(job.mutex) : job.mutex = 0
end sub

'' Resolve MODE_AUTO for a given zoom depth.
function ResolveMode(byval mode as long, byval zbits as long) as long
	if mode <> MODE_AUTO then return mode
	if zbits <= DOUBLE_MAX_ZBITS then return MODE_DOUBLE
	if g_set.usePerturb then return MODE_PERTURB
	return MODE_MPFR
end function

function ModeName(byval mode as long) as string
	select case mode
	case MODE_AUTO : return "Auto"
	case MODE_DOUBLE : return "Double"
	case MODE_MPFR : return "MPFR"
	case MODE_PERTURB : return "Perturbation"
	end select
	return "?"
end function

'' End of the first pass: fix the colour origin (lowest iteration value seen
'' so far) and redo the transfer of everything computed with the provisional
'' origin.  Runs under the job mutex while no tile is being rendered.
private sub Job_FixBase(byval job as RenderJob ptr)
	if job->nu = 0 then exit sub
	dim as long w = job->w, h = job->h, stp = job->firstStep
	if stp < 1 then stp = 1
	dim lo as double = 1e300
	for y as long = 0 to h - 1 step stp
		dim rowp as double ptr = job->nu + clngint(y) * w
		for x as long = 0 to w - 1 step stp
			if rowp[x] >= 0 andalso rowp[x] < lo then lo = rowp[x]
		next
	next
	if lo < 1e299 then job->nuBase = iif(lo > 0.5, lo - 0.5, 0.0)
	for y as long = 0 to h - 1 step stp
		for x as long = 0 to w - 1 step stp
			dim v as double = job->nu[clngint(y) * w + x]
			if v = NU_PENDING then continue for
			dim tv as single = TransferNu(v, job->transfer, job->nuBase)
			dim as long bx1 = iif(x + stp > w, w, x + stp), by1 = iif(y + stp > h, h, y + stp)
			for by as long = y to by1 - 1
				dim tp as single ptr = job->t + clngint(by) * w
				for bx as long = x to bx1 - 1
					tp[bx] = tv
				next
			next
		next
	next
end sub

private function FetchTask(byval job as RenderJob ptr, byval gen as long, byref tile as long, _
		byref stp as long, byref isFirst as long) as long
	dim res as long = TASK_EXIT
	mutexlock(job->mutex)
	do
		if job->cancel orelse job->gen <> gen orelse job->failed then exit do
		if job->stage = 0 then
			job->stage = 1
			res = TASK_REF
			exit do
		end if
		if job->stage = 1 then res = TASK_WAIT : exit do
		if job->pass >= job->nPasses then exit do
		if job->nextTile < job->nTiles then
			tile = job->nextTile
			job->nextTile += 1
			stp = job->firstStep shr job->pass
			if stp < 1 then stp = 1
			isFirst = iif(job->pass = 0, 1, 0)
			res = TASK_TILE
			exit do
		end if
		if job->tilesDone < job->nTiles then res = TASK_WAIT : exit do
		'' the pass is complete
		if job->pass = 0 andalso job->refineOnly = 0 andalso job->baseFixed = 0 then Job_FixBase(job)
		job->pass += 1
		job->nextTile = 0
		job->tilesDone = 0
		if job->pass >= job->nPasses then
			job->done = 1
			job->tElapsed = timer - job->tStart
			exit do
		end if
	loop
	mutexunlock(job->mutex)
	return res
end function

private sub RenderTile(byval job as RenderJob ptr, byref ctx as MpfrCtx, byval tile as long, _
		byval stp as long, byval isFirst as long)
	dim as long w = job->w, h = job->h
	dim as long x0 = job->tileX[tile], y0 = job->tileY[tile]
	dim as long x1 = x0 + job->tileSize, y1 = y0 + job->tileSize
	if x1 > w then x1 = w
	if y1 > h then y1 = h
	dim as long stp2 = stp * 2, mode = job->mode
	dim as longint cnt = 0, bad = 0
	dim v as double
	dim tv as single
	for y as long = y0 to y1 - 1 step stp
		if job->cancel then exit for
		for x as long = x0 to x1 - 1 step stp
			if isFirst = 0 then
				if (x mod stp2) = 0 andalso (y mod stp2) = 0 then continue for
			end if
			dim idx as longint = clngint(y) * w + x
			cnt += 1
			if job->refineOnly then
				if job->nu[idx] <> NU_INTERIOR then continue for
			end if
			select case mode
			case MODE_DOUBLE
				v = PixelDouble(*job, x, y)
			case MODE_PERTURB
				v = PixelPerturb(*job, x, y)
			case else
				v = PixelMpfr(*job, ctx, x, y)
				if v = NU_PENDING then exit for, for
			end select
			if v <> v then
				'' NaN: numerically unstable pixel, report it instead of hiding it
				v = NU_INTERIOR
				bad += 1
			end if
			if job->nu then job->nu[idx] = v
			tv = TransferNu(v, job->transfer, job->nuBase)
			if stp = 1 orelse job->refineOnly then
				job->t[idx] = tv
			else
				dim as long bx1 = x + stp, by1 = y + stp
				if bx1 > x1 then bx1 = x1
				if by1 > y1 then by1 = y1
				for by as long = y to by1 - 1
					dim rowp as single ptr = job->t + clngint(by) * w
					for bx as long = x to bx1 - 1
						rowp[bx] = tv
					next
				next
			end if
		next
	next
	mutexlock(job->mutex)
	job->tilesDone += 1
	job->pixDone += cnt
	job->nBad += bad
	mutexunlock(job->mutex)
end sub

private sub WorkerMain(byval p as any ptr)
	dim arg as WorkerArg ptr = p
	dim job as RenderJob ptr = arg->job
	dim gen as long = arg->gen
	deallocate(arg)
	dim ctx as MpfrCtx
	if job->mode = MODE_MPFR then MpfrCtx_Init(ctx, job->prec)
	dim as long tile, stp, isFirst
	do
		select case FetchTask(job, gen, tile, stp, isFirst)
		case TASK_EXIT
			exit do
		case TASK_WAIT
			sleep 1, 1
		case TASK_REF
			dim e as string
			dim ok as boolean = Ref_Compute(job->ref, @job->view.cx, @job->view.cy, job->prec, _
				job->maxIter, @job->cancel, @job->refProgress, e)
			if ok then
				if job->useSeries then
					Ref_SeriesSetup(job->ref, hypot(cdbl(job->w), cdbl(job->h)) * 0.5 * job->psMant, job->psExp)
				else
					job->ref.saSkip = 0
				end if
			end if
			mutexlock(job->mutex)
			if ok then
				job->stage = 2
			else
				if len(e) > 0 then job->errMsg = e
				job->failed = 1
			end if
			mutexunlock(job->mutex)
		case TASK_TILE
			RenderTile(job, ctx, tile, stp, isFirst)
		end select
	loop
	MpfrCtx_Clear(ctx)
end sub

'' Start rendering "v" into the job.  modeReq may be MODE_AUTO.
'' refineOnly keeps the existing buffers and recomputes only the pixels that
'' reached the previous iteration limit (same view and size required).
'' Returns false with job.errMsg set when the job cannot start.
function Job_Start(byref job as RenderJob, byref v as ViewState, byval w as long, byval h as long, _
		byval modeReq as long, byval maxIter as long, byval refineOnly as long = 0, _
		byval wantNu as long = 1, byval fixedBase as double = -1) as boolean
	Job_Init(job)
	Job_Stop(job)
	job.errMsg = ""
	job.failed = 0
	job.done = 0
	if w < 1 orelse h < 1 then job.errMsg = "invalid image size" : return false

	'' ---- buffers ----
	dim npx as longint = clngint(w) * h
	if job.bufW <> w orelse job.bufH <> h orelse job.t = 0 orelse (wantNu <> 0 andalso job.nu = 0) then
		refineOnly = 0
		dim need as longint = npx * iif(wantNu, 12, 4)
		if need > clngint(g_set.memLimitMB) * 1024 * 1024 then
			job.errMsg = "image of " & w & "x" & h & " needs " & (need \ 1048576) & _
				" MB, above the memory limit (" & g_set.memLimitMB & " MB)"
			return false
		end if
		if job.nu then deallocate(job.nu) : job.nu = 0
		if job.t then deallocate(job.t) : job.t = 0
		job.bufW = 0 : job.bufH = 0
		job.t = allocate(npx * sizeof(single))
		if wantNu then job.nu = allocate(npx * sizeof(double))
		if job.t = 0 orelse (wantNu <> 0 andalso job.nu = 0) then
			if job.nu then deallocate(job.nu) : job.nu = 0
			if job.t then deallocate(job.t) : job.t = 0
			job.errMsg = "out of memory allocating a " & w & "x" & h & " image"
			return false
		end if
		job.bufW = w : job.bufH = h
	end if
	if refineOnly = 0 then
		for i as longint = 0 to npx - 1
			job.t[i] = -2
		next
		if job.nu then
			for i as longint = 0 to npx - 1
				job.nu[i] = NU_PENDING
			next
		end if
	end if
	job.w = w : job.h = h

	'' ---- numerical setup ----
	View_Copy(job.view, v)
	job.zbits = View_ZoomBits(v, h)
	job.mode = ResolveMode(modeReq, job.zbits)
	job.maxIter = ClampL(maxIter, 2, 100000000)
	if job.mode = MODE_PERTURB andalso job.maxIter > MaxIterCap() then job.maxIter = MaxIterCap()
	if g_set.fixedPrec > 0 then
		job.prec = g_set.fixedPrec
	else
		job.prec = PrecisionFor(job.zbits, g_set.guardBits)
	end if
	if job.mode = MODE_DOUBLE then
		job.precOK = iif(job.zbits <= DOUBLE_LIMIT_ZBITS, 1, 0)
	else
		job.precOK = iif(job.prec >= PrecisionMinimum(job.zbits), 1, 0)
	end if
	if job.psInited = 0 then mpfr_init2(@job.ps, 64) : job.psInited = 1
	View_PixelSize(v, h, @job.ps)
	job.psd = mpfr_get_d(@job.ps, MPFR_RNDN)
	dim pe as clong
	job.psMant = mpfr_get_d_2exp(@pe, @job.ps, MPFR_RNDN)
	job.psExp = pe
	job.cxd = mpfr_get_d(@v.cx, MPFR_RNDN)
	job.cyd = mpfr_get_d(@v.cy, MPFR_RNDN)
	'' the job's own centre copy is rounded to the working precision so the
	'' MPFR and perturbation renderers see exactly the same reference point
	if job.mode <> MODE_DOUBLE andalso job.view.prec > job.prec then
		mpfr_prec_round(@job.view.cx, job.prec, MPFR_RNDN)
		mpfr_prec_round(@job.view.cy, job.prec, MPFR_RNDN)
		job.view.prec = job.prec
	end if

	job.nThreads = ClampL(EffectiveThreads(), 1, 64)
	job.tileSize = g_set.tileSize
	job.periodicity = g_set.periodicity
	job.useSeries = g_set.useSeries
	job.transfer = g_set.transfer
	job.refineOnly = refineOnly
	if fixedBase >= 0 then
		job.nuBase = fixedBase
		job.baseFixed = 1
	else
		job.baseFixed = 0       '' nuBase keeps its previous value as a provisional origin
	end if
	job.firstStep = iif(refineOnly, 1, g_set.previewStep)
	job.nPasses = 0
	dim s as long = job.firstStep
	while s >= 1
		job.nPasses += 1
		s shr= 1
	wend

	'' ---- tiles, ordered from the centre outwards ----
	dim ts as long = job.tileSize
	dim as long tcx = (w + ts - 1) \ ts, tcy = (h + ts - 1) \ ts
	job.nTiles = tcx * tcy
	job.tileX = reallocate(job.tileX, job.nTiles * sizeof(long))
	job.tileY = reallocate(job.tileY, job.nTiles * sizeof(long))
	if job.tileX = 0 orelse job.tileY = 0 then job.errMsg = "out of memory" : return false
	dim k as long = 0
	for ty as long = 0 to tcy - 1
		for tx as long = 0 to tcx - 1
			job.tileX[k] = tx * ts
			job.tileY[k] = ty * ts
			k += 1
		next
	next
	'' insertion sort by distance to the image centre (tile counts are small)
	for i as long = 1 to job.nTiles - 1
		dim as long ax = job.tileX[i], ay = job.tileY[i]
		dim da as double = (ax + ts * 0.5 - w * 0.5) ^ 2 + (ay + ts * 0.5 - h * 0.5) ^ 2
		dim j as long = i - 1
		while j >= 0
			dim db as double = (job.tileX[j] + ts * 0.5 - w * 0.5) ^ 2 + (job.tileY[j] + ts * 0.5 - h * 0.5) ^ 2
			if db <= da then exit while
			job.tileX[j + 1] = job.tileX[j]
			job.tileY[j + 1] = job.tileY[j]
			j -= 1
		wend
		job.tileX[j + 1] = ax
		job.tileY[j + 1] = ay
	next

	'' ---- go ----
	g_genCounter += 1
	job.gen = g_genCounter
	job.cancel = 0
	job.stage = iif(job.mode = MODE_PERTURB, 0, 2)
	job.pass = 0
	job.nextTile = 0
	job.tilesDone = 0
	job.pixDone = 0
	job.pixTotal = npx
	job.nBad = 0
	job.refProgress = 0
	job.tStart = timer
	job.tElapsed = 0
	job.running = 1
	job.nStarted = 0
	for i as long = 0 to job.nThreads - 1
		dim arg as WorkerArg ptr = allocate(sizeof(WorkerArg))
		if arg = 0 then exit for
		arg->job = @job
		arg->gen = job.gen
		job.threads(job.nStarted) = threadcreate(@WorkerMain, arg)
		if job.threads(job.nStarted) = 0 then
			deallocate(arg)
			exit for
		end if
		job.nStarted += 1
	next
	if job.nStarted = 0 then
		job.running = 0
		job.errMsg = "could not start any render thread"
		return false
	end if
	return true
end function

'' True while workers are still producing pixels.
function Job_Busy(byref job as RenderJob) as boolean
	if job.running = 0 then return false
	dim b as boolean
	mutexlock(job.mutex)
	b = (job.done = 0 andalso job.failed = 0 andalso job.cancel = 0)
	mutexunlock(job.mutex)
	return b
end function

'' Progress 0..1 and a short description of the current stage.
function Job_Progress(byref job as RenderJob, byref stageTxt as string) as double
	if job.mutex = 0 then return 0
	dim p as double
	mutexlock(job.mutex)
	if job.stage < 2 then
		stageTxt = "reference orbit " & job.refProgress & "/" & job.maxIter
		p = 0
	else
		stageTxt = "pass " & iif(job.pass + 1 > job.nPasses, job.nPasses, job.pass + 1) & "/" & job.nPasses
		if job.pixTotal > 0 then p = job.pixDone / job.pixTotal
	end if
	if job.done then p = 1
	mutexunlock(job.mutex)
	if p > 1 then p = 1
	return p
end function

'' Block until the job finishes (tests, command line rendering).
function Job_Wait(byref job as RenderJob) as boolean
	while Job_Busy(job)
		sleep 2, 1
	wend
	dim ok as boolean = (job.done <> 0 andalso job.failed = 0)
	Job_Stop(job)
	return ok
end function

'' Gather statistics from a finished job (requires the nu() buffer).
sub Job_Stats(byref job as RenderJob)
	job.nInterior = 0 : job.nEscaped = 0 : job.nNearLimit = 0
	job.nuMin = 1e300 : job.nuMax = 0
	if job.nu = 0 then exit sub
	dim lim as double = job.maxIter * 0.5
	for i as longint = 0 to clngint(job.w) * job.h - 1
		dim v as double = job.nu[i]
		if v >= 0 then
			job.nEscaped += 1
			if v > lim then job.nNearLimit += 1
			if v < job.nuMin then job.nuMin = v
			if v > job.nuMax then job.nuMax = v
		elseif v = NU_INTERIOR then
			job.nInterior += 1
		end if
	next
end sub
