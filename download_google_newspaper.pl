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
use JSON;
use Getopt::Long qw( :config posix_default bundling no_ignore_case );
use IO::Handle;

my $page_arg;
GetOptions("page|p=i" => \$page_arg)
	or die "Usage: $0 [--page page] url";

my $user_agent = "Mozilla/5.0 (X11; Linux x86_64; rv:18.0) Gecko/20100101 Firefox/18.0";
my $ua = new LWP::UserAgent(
	agent=>$user_agent,
	);

if(@ARGV != 1)
{
	die "Usage: $0 [--page page] url";
}

my ($url) = @ARGV;
my $response = $ua->get($url);
die "Unable to fetch page: ".$response->as_string if ($response->is_error);
my $content = $response->content;
my ($title) = $content =~ /title="Go to front page"><nobr>([^<]*)/;
die "Unable to parse title from page" unless($title);
decode_entities($title);
$title =~ s/\xa0/ /g;
say $title;

my $page;
my ($height, $width);
my $zoom = 6;

if (defined($page_arg))
{
	$content =~ /_OC_Run\((.*)\);<\/script\>/;
	my $data = from_json("[$1]");
	my @pages = @{$data->[0]->{page}};
	if ($page_arg < 1 || $page_arg > scalar(@pages))
	{
		die "Error: Invalid page";
	}
	my $page_data = $pages[$page_arg - 1];
	$page = $page_arg;
	my $prefix = $data->[0]->{prefix};
	$url = "$prefix&pg=$page_data->{pid}";
	say $url;

	my $page_info_response = $ua->get("$url&jscmd=click3");
	die "Unable to fetch info page: ".$page_info_response->as_string if ($page_info_response->is_error);
	my $page_info = from_json($page_info_response->content);
	my $tile_res_arr = $page_info->{page}->[0]->{additional_info}->{'[NewspaperJSONPageInfo]'}->{tileres};
	my ($tile_res) = grep { $_->{z} == $zoom } @$tile_res_arr;
	($width, $height) = ($tile_res->{w}, $tile_res->{h});
}
else
{
	($page) = $content =~ /<input name=jtp id=jtp value="(\d+)"/;
	($height, $width) = $content =~ /{"h":(\d+),"w":(\d+),"z":$zoom}/;
}
say "Page $page";

my $s = 256;
my $num_tiles_x = ceil($width / $s);
my $num_tiles_y = ceil($height / $s);
my $num_tiles = $num_tiles_x*$num_tiles_y;

my $tempdir;
#if (scalar(@ARGV) >= 2)
#{
#	$tempdir = $ARGV[1];
#}
#else
{
	$tempdir = tempdir( 'tmp.XXXXXXXX', DIR=>'.');
	for my $tid (0 .. $num_tiles - 1)
	{
		printf "\r%d / %d", $tid+1, $num_tiles;
		STDOUT->flush();
		my $tile = sprintf "%04d", $tid;
		my $request = HTTP::Request->new(GET => $url . "&img=1&zoom=$zoom&tid=$tid");
		my $response = $ua->request($request, "$tempdir/tile$tile.jpg");
	}
	print "\n";
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
for my $tid (0 .. $num_tiles - 1)
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

say "'$out'";

