'' Developer tool: builds a chain of ever deeper mini-Mandelbrot nuclei.
'' build: fbc -gen gcc -O 3 -mt -i include -i src tools/deepfind.bas -x tools/deepfind
'' usage: deepfind x y radius levels offsetFactor angleDeg
#include once "engine.bas"
Paths_Init() : Settings_Defaults(g_set)
dim as mpfr_t cx, cy, rad, ox, oy, sz, t
mpfr_init2(@cx, 256) : mpfr_init2(@cy, 256) : mpfr_init2(@rad, 64)
mpfr_init2(@ox, 64) : mpfr_init2(@oy, 64) : mpfr_init2(@sz, 64) : mpfr_init2(@t, 64)
HpFromStr(@cx, command(1), 256) : HpFromStr(@cy, command(2), 256) : HpFromStr(@rad, command(3), 64)
dim levels as long = valint(command(4))
dim offF as double = val(command(5)), ang as double = val(command(6)) * 3.14159265358979 / 180
dim radF as double = val(command(7)) : if radF <= 0 then radF = 0.3
for lv as long = 1 to levels
	dim period as long
	dim t0 as double = timer
	if Nucleus_Find(@cx, @cy, @rad, 2000000, 0, @ox, @oy, @sz, period) = false then print "level "; lv; ": no nucleus found" : exit for
	print "level "; lv; " period="; period; " size="; HpShort(@sz, 4); " prec="; mpfr_get_prec(@ox); " t="; timer - t0
	print "x="; HpToStr(@ox)
	print "y="; HpToStr(@oy)
	'' next search disc: offset from the nucleus by offF * size
	dim p as long = mpfr_get_prec(@ox)
	mpfr_set_prec(@cx, p) : mpfr_set_prec(@cy, p)
	mpfr_mul_d(@t, @sz, offF * cos(ang), MPFR_RNDN) : mpfr_add(@cx, @ox, @t, MPFR_RNDN)
	mpfr_mul_d(@t, @sz, offF * sin(ang), MPFR_RNDN) : mpfr_add(@cy, @oy, @t, MPFR_RNDN)
	mpfr_mul_d(@rad, @sz, offF * radF, MPFR_RNDN)
next
