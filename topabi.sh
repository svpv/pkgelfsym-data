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
    find "$1" -mindepth $depth -maxdepth $depth -name '*.rpm' |
    while read -r f; do
	rpmelfsym.pl "$f" </dev/null |cut -f2 |
	sort -u |sed '\|^/usr/share/doc/|d;s/^/./' |
	rpmpeek "$f" xargs -r --delimiter='\n' objdump -p |
	awk -v rpm="${f##*/}" '
	    /^Version [Dd]ef/,/^$/ { if (NF==4 && +$1>1) print rpm "\tA\t" $NF }
	    /^Version [Rr]ef/,/^$/ { if (NF==4 && / 0x/) print rpm "\tU\t" $NF }'
    done |
	sort -u |
	join -t$'\t' -o '1.2 1.1 2.2 2.3' "$rpm2srpm" -
}

ProcDump()
{
    sort -t$'\t' -u -k4 -k1,3 --compress-program=lz4 |
    awk -F'\t' '
	function flushSym()
	{
	    N += (n ** 0.63) * (allU ? 1.28 : 1)
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
    out=abi.${d//\//_}
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
sort -g --compress-program=lz4 |tail -1024 >abi.1k
cut -f2 abi.1k |tail -256 |sort -u >topabi.list
