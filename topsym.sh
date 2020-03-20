#!/bin/sh -efu

DumpDir()
{
    if (cd "$1" && set +f && set -- *.rpm && [ -f "$1" ]); then
	subdirs=
    elif (cd "$1" && set +f && set -- */*.rpm && [ -f "$1" ]); then
	subdirs=1
    else
	echo >&2 "$1: no rpms"
	return 1
    fi
    rpm2srpm=rpm2srpm.${1//\//_}
    if [ ! -s "$rpm2srpm" ] || [ "$rpm2srpm" -nt "$1" ] || [ "$rpm2srpm" -ot "$1" ]; then
	depth=$((1+${subdirs:-0}))
	find "$1" -mindepth $depth -maxdepth $depth -name '*.rpm' -execdir \
	rpmquery --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\t%{SOURCERPM}\n' -p '{}' '+' |
	sort -u >"$rpm2srpm"
	touch -r "$1" "$rpm2srpm"
    fi
    if [ "${subdirs:-0}" -eq 0 ]; then
	rpmelfsym.pl "$1"
    else
	cd "$1"; set +f # subshell
	ls */*.rpm |sort -t/ -k2 |xargs --delimiter='\n' \
	rpmelfsym.pl
    fi |
	join -t$'\t' -o '1.2 1.1 2.2 2.3 2.4' "$rpm2srpm" -
}

ProcDump()
{
    awk -F'\t' '
	index("UTWVDBARuiGS", $4) &&
	$5 != "__bss_start"       &&
	$5 != "__libc_start_main" &&
	$5 != "_edata"            &&
	$5 != "_end"              &&
	$5 != "_fini"             &&
	$5 != "_init"		  &&
	index($3, "/usr/share/doc/") != 1 {
	    print $1 "\t" $2 "\t" $4 "\t" $5
	}
    ' |
    sort -t$'\t' -u -k4 -k1,3 |
    awk -F'\t' '
	function flushSym()
	{
	    N += (n ** 0.63) * (allU ? 1.28 : 1)
	    if (N > 1.99) # at least two srpms, or at least three subpackages
		print N "\t" sym
	}
	{   if (sym == $4) {
		if ($1 == srpm && $2 == rpm) {
		    # dups within a subpackage do not count
		    allU = (allU && $3 == "U")
		}
		else if ($1 == srpm) {
		    n++; # the same srpm, count subpackages with this symbol
		    allU = (allU && $3 == "U")
		}
		else {
		    # combine subpackage count, start another srpm
		    N += (n ** 0.63) * (allU ? 1.28 : 1)
		    allU = ($3 == "U")
		    n = 1
		}
	    }
	    else {
		# another symbol, another dollar
		if (n)
		    flushSym()
		allU = ($3 == "U")
		N = 0; n = 1
	    }
	    srpm = $1; rpm = $2
	    sym = $4
	}
	END {
	    if (n)
		flushSym()
	}
    '
}

for d; do
    d=${d%/}
    out=out.${d//\//_}
    DumpDir "$d" |ProcDump >$out
    set -- "$@" "$out"
done
shift $(($#/2))

sort -m -k2 "$@" |
awk -F'\t' '
    function printSym()
    {
	ShortLen = 16
	N *= log(ShortLen + length(sym))
	print N "\t" sym
    }
    {   if ($2 == sym)
	    N += $1
	else {
	    if (N)
		printSym()
	    sym = $2
	    N = $1
	}
    }
    END {
	if (N)
	    printSym()
    }' |
sort -n |tail -$((1<<20)) >out.1M
tail -$((1<<16)) <out.1M >out.64k
cut -f2 <out.64k |sort -u >topsym.list
