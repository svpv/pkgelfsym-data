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
    depth=$((1+${subdirs:-0}))
    if [ ! -s "$rpm2srpm" ]; then
	find "$1" -mindepth $depth -maxdepth $depth -name '*.rpm' -execdir \
	rpmquery --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\t%{SOURCERPM}\n' -p '{}' '+' |
	sort -u >"$rpm2srpm"
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
	BEGIN {
	    Junk["__bss_end__"]
	    Junk["__bss_start"]
	    Junk["__bss_start__"]
	    Junk["__data_start"]
	    Junk["__end__"]
	    Junk["__gmon_start__"]
	    Junk["__libc_csu_fini"]
	    Junk["__libc_csu_init"]
	    Junk["_bss_end__"]
	    Junk["_edata"]
	    Junk["_end"]
	    Junk["_fini"]
	    Junk["_init"]
	    Junk["_start"]
	    Junk["data_start"]
	    Junk["main"]
	}
	index("UTWVDBRuiGS", $4) &&
	!($5 in Junk) &&
	index($3, "/usr/share/doc/") != 1 {
	    print $1 "\t" $2 "\t" $4 "\t" $5
	}
    ' |
    sort -t$'\t' -u -k4 -k1,3 --compress-program=lz4 |
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

w=1.0 wsum=0
wcmd='sort -m -k2 --compress-program=lz4'

for d; do
    if [[ $d = [0-9].[0-9]* ]]; then
	w=$d
	continue
    fi
    d=${d%/}
    out=out.${d//\//_}
    [ -s "$out" ] ||
    DumpDir "$d" |ProcDump >$out
    if [ $w = 1.0 ]; then
	wcmd="$wcmd $out"
    else
	wcmd="$wcmd <(awk -F'\t' '{print\$1*$w\"\t\"\$2}' $out)"
    fi
    wsum=$(perl -e "print $wsum+$w")
done

set +o posix
eval "$wcmd" |
awk -F'\t' -v NFiles=$wsum '
    BEGIN {
	ShortLen = 16
	RNorm = 1 / (log(ShortLen) * NFiles)
    }
    function printSym()
    {
	N *= log(ShortLen + length(sym))
	if (match(sym, /^caml.*_([0-9]+)$/, A))
	    N *= 99 / (99 + log(99 + A[1]))
	if (sym ~ /^_Z[1-9]/)
	    N *= 0.97
	N *= RNorm
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
sort -g --compress-program=lz4 |tail -$((1<<20)) >out.1M
awk -F'\t' <out.1M '$2~/^_Z/{print$2}' |
    tail -$((64<<10)) >topsym.list
awk -F'\t' <out.1M '$2~/^caml.*_[0-9]+$/{print$2}' |
    tail -$((4<<10)) >>topsym.list
awk -F'\t' <out.1M '$2!~/^_Z|^caml.*_[0-9]+$/{print$2}' |
    tail -$((60<<10)) >>topsym.list
sort -u -o topsym.list{,}
