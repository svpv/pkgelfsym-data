#!/bin/sh -efu

DumpDir()
{
    rpm2srpm=rpm2srpm.${1//\//_}
    if [ ! -s "$rpm2srpm" ] || [ "$rpm2srpm" -nt "$1" ] || [ "$rpm2srpm" -ot "$1" ]; then
	find "$1" -mindepth 1 -maxdepth 1 -name '*.rpm' -execdir \
	rpmquery --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\t%{SOURCERPM}\n' -p '{}' '+' |
	sort -u >"$rpm2srpm"
	touch -r "$1" "$rpm2srpm"
    fi
    rpmelfsym.pl "$1" |
	join -t$'\t' -o '1.2 1.1 2.3 2.4' "$rpm2srpm" -
}

ProcDump()
{
    awk -F'\t' '
	$3 != "v"                 &&
	$3 != "w"                 &&
	$4 != "__bss_start"       &&
	$4 != "__libc_start_main" &&
	$4 != "_edata"            &&
	$4 != "_end"              &&
	$4 != "_fini"             &&
	$4 != "_init" {
	    print $1 "\t" $2 "\t" $4
	}
    ' |
    sort -t$'\t' -u -k3 -k1,2 |
    awk -F'\t' '
	function flushSym()
	{
	    N += sqrt(n)
	    if (N > 1.7) # at least two srpms, or at least three subpackages
		print N "\t" sym
	}
	{   if (sym == $3) {
		if ($1 == srpm)
		    n++; # the same srpm, count subpackages with this symbol
		else {
		    # combine subpackage count, start another srpm
		    N += sqrt(n)
		    srpm = $1
		    n = 1
		}
	    }
	    else {
		# another symbol, another dollar
		if (n)
		    flushSym()
		sym = $3
		srpm = $1
		N = 0; n = 1
	    }
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
sort -n
