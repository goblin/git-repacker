#! /usr/bin/perl

use strict;
use warnings;

use Compress::Zlib;
use Data::Dumper;

my @thresholds;
my $threshnum = 0;
for(my $i = 1; $i < 8; $i++) {
	$threshnum += 2**(7*$i);
	push @thresholds, $threshnum;
}

binmode STDIN;
binmode STDOUT;

my ($sig, $num_all) = (0, 0);
read STDIN, $sig, 4;
unless($sig eq 'UNPK') {
	die "not a UNPK file";
}

read STDIN, $num_all, 4;
$num_all = unpack('N', $num_all);

print 'PACK', pack('N', 2), pack('N', $num_all);

my %objs;

for(my $i = 0; $i < $num_all; $i++) {
	my $cur_ofs = tell STDOUT;
	$objs{$i} = $cur_ofs;

	my ($type, $size, $tsstr) = read_typesize();
	print $tsstr;
	if($type == 6) { # OBJ_OFS_DELTA
		my $refobj;
		read STDIN, $refobj, 4;
		$refobj = unpack('L', $refobj);
		my $ofs_num = $cur_ofs - $objs{$refobj};
		print encode_ofs_delta($ofs_num);
	} elsif($type == 7) { # OBJ_REF_DELTA
		my $base;
		read STDIN, $base, 20;
		print $base;
	}

	my ($d, $status) = deflateInit();
	my ($in, $out);
	# FIXME: potentially much RAM and hacky but will do for now
	read STDIN, $in, $size;
#	print STDERR "read sz=$size: $in\n";
	($out, $status) = $d->deflate($in);
	$out .= $d->flush();
#	printf STDERR "status = %d (size=%d)\n", $status, length($out);
	print $out;
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

sub encode_ofs_delta {
	my $ofs = shift;

	my $n = 1;
	for(my $i = 0; $i < 7; $i++) {
		$n++ if($ofs >= $thresholds[$i]);
	}

	for(my $i = 1; $i < $n; $i++) {
		$ofs -= 2**(7*$i);
	}

	my @bytes;

	for(my $i = 0; $i < $n; $i++) {
		push @bytes, ($ofs & 0b0111_1111);
		$ofs = $ofs >> 7;
	}

	my $out = '';
	for(my $i = $n-1; $i > 0; $i--) {
		$out .= pack('C', 0b1000_0000 | ($bytes[$i]));
	}
	$out .= pack('C', $bytes[0]);

	return $out;
}
