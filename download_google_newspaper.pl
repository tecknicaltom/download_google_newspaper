#!/usr/bin/perl

# Copyright 2014 Tom Samstag
# https://github.com/tecknicaltom/download_google_newspaper
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use diagnostics;
use feature 'say';
use LWP::UserAgent;
use HTML::Entities;
use File::Temp qw(tempdir);
use POSIX;

if (scalar(@ARGV) != 1)
{
	say "Usage: $0 url";
	exit;
}

my $url = $ARGV[0];

my $user_agent = "Mozilla/5.0 (X11; Linux x86_64; rv:18.0) Gecko/20100101 Firefox/18.0";
my $ua = new LWP::UserAgent(
	agent=>$user_agent,
	);

my $response = $ua->get($url);
die "Unable to fetch page: ".$response->as_string if ($response->is_error);
my $content = $response->content;
my ($title) = $content =~ /title="Go to front page"><nobr>([^<]*)/;
die "Unable to parse title from page" unless($title);
decode_entities($title);
$title =~ s/\xa0/ /g;
say $title;
my ($page) = $content =~ /<input name=jtp id=jtp value="(\d+)"/;
say "Page $page";

my $zoom = 6;
my ($height, $width) = $content =~ /{"h":(\d+),"w":(\d+),"z":$zoom}/;

my $s = 256;
my $num_tiles_x = ceil($width / $s);
my $num_tiles_y = ceil($height / $s);
my $num_tiles = $num_tiles_x*$num_tiles_y;

my $tempdir;
if (scalar(@ARGV) >= 2)
{
	$tempdir = $ARGV[1];
}
else
{
	$tempdir = tempdir( 'tmp.XXXXXXXX', DIR=>'.');
	for my $tid (0..$num_tiles)
	{
		my $tile = sprintf "%04d", $tid;
		my $request = HTTP::Request->new(GET => $url . "&img=1&zoom=$zoom&tid=$tid");
		my $response = $ua->request($request, "$tempdir/tile$tile.jpg");
	}
}

my $out = "$title - Page $page.png";

if (-e $out)
{
	say "out file already exists!";
	say $out;
	exit;
}

my ($x, $y) = (0,0);
my ($megatile_x, $megatile_y) = (0,0);
my %filenames;
for my $tid (0..$num_tiles)
{
	my ($x_pos, $y_pos) = ($x*3+$megatile_x, $y*3+$megatile_y);

	my $tile = sprintf "%04d", $tid;
	$filenames{$x_pos}->{$y_pos} = "$tempdir/tile$tile.jpg";

	$megatile_x++;
	($megatile_x, $megatile_y) = (0, $megatile_y+1) if($megatile_x == 3 or $x*3+$megatile_x >= $num_tiles_x);
	($megatile_x, $megatile_y, $x, $y) = (0, 0, $x+1, $y) if($megatile_y == 3 or $y*3+$megatile_y >= $num_tiles_y);
	($x, $y) = (0, $y+1) if($x*3+$megatile_x >= $num_tiles_x);
}

my @ordered_filenames;
for my $y (0 .. $num_tiles_y - 1)
{
	push @ordered_filenames, "(";
	for my $x (0 .. $num_tiles_x - 1)
	{
		push @ordered_filenames, $filenames{$x}->{$y};
	}
	push @ordered_filenames, ")";
}
system "montage", "-mode", "Concatenate", "-tile", "${num_tiles_x}x${num_tiles_y}", @ordered_filenames, $out;

say $out;

