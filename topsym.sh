#!/bin/sh -efu

DumpDir()
{
    rpmelfsym.pl "$1"
    find "$1" -mindepth 1 -maxdepth 1 -name '*.rpm' -execdir \
	rpmquery --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm\t%{SOURCERPM}\n' -p '{}' '+' |
	sort -u >rpm2srpm
    rpmelfsym.pl "$1" |
	join -t$'\t' -o '1.2 2.2 2.3 2.4' rpm2srpm -
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
	    print $1 "\t" $4
	}
    ' |
    sort -u |cut -f2- |
    sort |uniq -c |awk '$1>2'
}

for d; do
    out=out.${d//\//_}
    DumpDir "$d" |ProcDump >$out
    set -- "$@" "$out"
done
shift $(($#/2))

sort -m -k2 "$@" |
awk '
    {   n = $1
	sub(/^ *[1-9][0-9]* /, "")
	if ($0 == SYM)
	    N += n
	else {
	    if (N)
		print N "\t" SYM
	    SYM = $0
	    N = n
	}
    }
    END {
	if (N)
	    print N "\t" SYM
    }' |
sort -n
