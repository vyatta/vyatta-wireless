#! /usr/bin/perl

# **** License ****
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# This code was originally developed by Vyatta, Inc.
# Portions created by Vyatta are Copyright (C) 2009 Vyatta, Inc.
# All Rights Reserved.
#
# Author: Stephen Hemminger
# Date: August 2009
# Description: Script to display wireless information
#
# **** End License ****

use lib "/opt/vyatta/share/perl5/";
use Getopt::Long;
use Vyatta::Config;
use Vyatta::Interface;

use strict;
use warnings;

my %iw2type = (
    'IBSS'	=> 'adhoc',
    'managed'	=> 'station',
    'AP'	=> 'access-point',
#    'AP/VLAN'	=> 'vlan-access-point',
#    'WDS'	=> 'wds',
    'monitor'	=> 'monitor',
    'mesh point' => 'mesh',
);

# Only modes valid on command line are listed
my %type2iw = (
    'access-point'	=> '__ap',
    'adhoc'		=> 'IBSS',
    'station'		=> 'managed',
#    'wds'		=> 'wds',
    'monitor'		=> 'monitor',
    'mesh' 		=> 'mesh point',
);

# Convert from device (wlan0) to underlying phy (phy0)
# This is gross, no other API for getting the info
sub get_phy {
    my $intf = shift;
    my $phylink = "/sys/class/net/$intf/phy80211";

    # if interface does not exist yet, that is okay
    return unless -l $phylink;

    my $link = readlink $phylink;
    return unless $link;

    #  expect value like ../../ieee80211/phy0
    return $1 if ( $link =~ m/\/(phy\d+)$/ );
}

# get list of channels available by device
sub get_chan {
    my $intf = shift;
    my $phy = get_phy($intf);
    exit 0 unless $phy;

    my @args = ('iw', 'phy', $phy, 'info');
    open my $iwcmd, '-|'
	or exec @args
	or die "iw command failed: $!";

    my @chans;
    while (<$iwcmd>) {
	chomp;
	next unless /Frequencies:/;

	while (<$iwcmd>) {
	    chomp;
	    next if /\(disabled\)/;
	    last unless /\* \d+ MHz \[(\d+)\]/;
	    push @chans, $1;
	}
	last;
    }
    close $iwcmd;
    return @chans;
}

# get list of supported types: AP, ...
sub get_type {
    my $intf = shift;
    my $phy = get_phy($intf);
    exit 0 unless $phy;

    my @args = ('iw', 'phy', $phy, 'info');

    open my $iwcmd, '-|'
	or exec @args
	or die "iw command failed: $!";

    my @types;
    while (<$iwcmd>) {
	next unless /Supported interface modes:/;
	while (<$iwcmd>) {
	    last unless m/\* (.+)$/;
	    my $t = $iw2type{$1};

	    # skip unknown/unused types
	    push @types, $t if $t;
	}
	last;
    }
    close $iwcmd;

    return @types;
}


sub usage {
    print <<EOF;
Usage: $0 --dev=<interface> show-type
       $0 --dev=<interface> show-chan
EOF
    exit 1;
}

sub list_chan {
    print join(' ', get_chan(@_)), "\n";
}

sub check_chan {
    my ($dev, $ch) = @_;
    my $match = grep { $ch eq $_ } get_chan($dev);
    die "Channel $ch is not availabe for $dev\n" unless ($match > 0);
}

sub list_type {
    print join(' ', get_type(@_)), "\n";
}

sub check_type {
    my ($dev, $type) = @_;
    my $match = grep { $type eq $_ } get_type($dev);
    die "Type $type is not a available for $dev\n" unless ($match > 0);
}

sub create_dev {
    my $wlan = shift;
    my $cfg = new Vyatta::Config;

    $cfg->setLevel("interfaces wireless");
    die "No configuration for $wlan\n" unless $cfg->exists($wlan);

    $cfg->setLevel("interfaces wireless $wlan");
    my $phy = $cfg->returnValue('physical-device');
    die "wireless $wlan: you must specify physical-device\n" unless $phy;

    my $type = $cfg->returnValue('type');
    die "wireless $wlan: you must specify type\n" unless $type;

    my $iwtype = $type2iw{$type};
    die "wireless $wlan: unknown type $type\n" unless $iwtype;

    system("iw phy $phy interface add $wlan type $iwtype") == 0
	or die "wireless $wlan: device create failed\n";
}

sub delete_dev {
    my $name = shift;

    exec 'iw', 'dev', $name, 'del';
    die "Could not exec iw: $!";
}

my $dev;
my ( $list_type, $check_type, $list_chan, $check_chan );
my ( $create_dev, $delete_dev );

GetOptions(
    'dev=s'		  => \$dev,
    'list-type'   	  => \$list_type,
    'check-type=s'	  => \$check_type,

    'list-chan'		  => \$list_chan,
    'check-chan=s'	  => \$check_chan,

    'create'		  => \$create_dev,
    'delete'		  => \$delete_dev,
) or usage();

die "Missing device argument\n" unless $dev;

list_chan($dev) 		if $list_chan;
check_chan($dev, $check_chan)	if $check_chan;

list_type($dev)			if $list_type;
check_type($dev, $check_type)	if $check_type;

create_dev($dev)		if $create_dev;
delete_dev($dev)		if $delete_dev;
