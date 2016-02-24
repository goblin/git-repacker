#! /usr/bin/perl

use strict;
use warnings;

use Compress::Zlib;
use IO::Unread qw/unread/;
use Data::Dumper;

binmode STDIN;
binmode STDOUT;

my ($sig, $ver, $num_all) = (0, 0, 0);
read STDIN, $sig, 4;
unless($sig eq 'PACK') {
	die "not a PACK file";
}

read STDIN, $ver, 4;
$ver = unpack('N', $ver);

unless($ver == 2) {
	die "unknown version $ver";
}

read STDIN, $num_all, 4;
$num_all = unpack('N', $num_all);

print 'UNPK', pack('N', $num_all);

my %objs;

for(my $i = 0; $i < $num_all; $i++) {
	my $cur_ofs = tell STDIN;
	$objs{$cur_ofs} = $i;
	my ($type, $size, $tsstr) = read_typesize();
	print $tsstr;
	if($type == 6) { # OBJ_OFS_DELTA
		my $offset = '';
		my $last = 0b1000_0000;
		while($last & 0b1000_0000) {
			my $cur;
			read STDIN, $cur, 1;
			$offset .= $cur;
			$last = unpack('C', $cur);
		}
		my $refpos = $cur_ofs - decode_ofs_delta($offset);
		die unless exists($objs{$refpos});
		my $refobj = $objs{$refpos};
		print pack('L', $refobj);
	} elsif($type == 7) { # OBJ_REF_DELTA
		my $base;
		read STDIN, $base, 20;
		print $base;
	}

	my ($i, $status) = inflateInit();
	my ($in, $out);
	# FIXME: potentially much RAM and hacky but will do for now
	read STDIN, $in, $size + 1000;
	($out, $status) = $i->inflate($in);
#	printf "status = %d (ok=%d, end=%d)\n", $status, Z_OK, Z_STREAM_END;
	print $out;
	unread STDIN, $in;
}

sub read_typesize {
	my $first;
	my $orig = '';
	read STDIN, $first, 1;
	$orig .= $first;
	$first = unpack('C', $first);

	my $last = $first;
	my $type = ($first & 0b0111_0000) >> 4;
	my $size = $first & 0b0000_1111;
	my $cnt = 4;

	while(($last & 0b1000_0000) == 0b1000_0000) {
		my $cur;
		read STDIN, $cur, 1;
		$orig .= $cur;
		$cur = unpack('C', $cur);
		my $curdata = $cur & 0b0111_1111;
		$size = $size | ($curdata << $cnt);
		$cnt += 7;

		$last = $cur;
	}

	return ($type, $size, $orig);
}

sub decode_ofs_delta {
	my $str = shift;
	my @bytes = unpack('C*', $str);
	my $n = length($str);

	my $res = 0;
	for(my $i = 0; $i < $n; $i++) {
		$res = $res << 7;
		$res = $res | ($bytes[$i] & 0b0111_1111);
	}
	for(my $i = 1; $i < $n; $i++) {
		$res += 2**(7*$i);
	}
	return $res;

}
