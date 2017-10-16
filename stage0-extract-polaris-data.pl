#!/usr/bin/perl
# -*- cperl -*-

use strict;
use OpenILS::Migrate::From::Polaris::DB;
use OpenILS::Migrate::To::Pg;
use Term::ReadKey;
use Term::ANSIColor;
use DateTime;

do "./credentials.pl" if -e "./credentials.pl"; # see credentials.pl.sample for how this can work.

END { ReadMode 'restore'; } ReadMode 'cbreak'; # Don't auto-echo typed characters.

my %default = ( mode      => "active",
                startdate => DateTime->now()->year(),
              );
my %shortopt = ( a => [ mode => "active" ],
                 c => [ mode => "current", startdate => DateTime->now()->subtract( months => 1)->year() ],
                 f => [ mode => "full" ],
               );
my %option = %default;
while (@ARGV) {
  my $arg = shift @ARGV;
  if ($arg =~ /^--(\w+)=(.*)/) {
    $option{$1} = $2;
  } elsif ($arg =~ /^--(\w+)/) {
    $option{$1} = shift @ARGV;
  } elsif ($arg =~ /^-(\w+)/) {
    for my $so (split //, $1) {
      if ($shortopt{$so}) {
        my @sobit = @{$shortopt{$so}};
        while (@sobit) {
          my $optname = shift @sobit;
          my $value   = shift @sobit;
          $option{$optname} = $value;
        }
      } else {
        warn "Unrecognized short option: $so\n";
      }}
  } else {
    warn "Unrecognized command-line option: $arg\n";
  }}

my $response = "";
my $ready = 0;

while (not $ready) {
  print "\n" . color("white on_black") . "\n";
  my @menu = ("How many data do you want to retrieve from Polaris?",
              ["a", "Active   ", ($option{mode} eq "active")  ? "SELECTED" : ""],
              ["c", "Current  ", ($option{mode} eq "current") ? "SELECTED" : ""],
              ["f", "Full     ", ($option{mode} eq "full")    ? "SELECTED" : ""],
              "",
              "How recent do data have to be, to be considered current?",
              ["s", "Startdate", $option{startdate}],
              "",
              ["g", "Go        ", "Start retrieving data from Polaris."]);
  my $response = menu(@menu);
  if    ("a" eq lc $response) { $option{mode} = "active"; }
  elsif ("c" eq lc $response) { $option{mode} = "current"; }
  elsif ("f" eq lc $response) { $option{mode} = "full"; }
  elsif ("s" eq lc $response) {
    ReadMode 'restore';
    local $|=1;
    print "Enter a year: "; # It is of course possible to be more specific than a year, if you know about
                            # date formats, but I didn't want to explain all those details in the prompt.
    my $date = <STDIN>;
    ReadMode 'cbreak';
    chomp $date;
    $option{startdate} = $date;
  } elsif ("g" eq lc $response) {
    print "Starting data retrieval...\n";
    print "Count: $ready\n" if $ready++ > 0;
  } else {
    print "Unrecognized menu selection: $response\n\n";
  }
}
print "Getting list of tables...\n";

ReadMode 'restore';
my %idlist;

for my $t (@$tables) {
  print "Processing table '$$t{name}':\n";
  pgnuketable($t);
  my @r;
  if (($option{mode} eq "full") or ($$t{migrate} eq "full")) {
    @r = getrecord($$t{name});
  } elsif (($option{mode} eq "current") and ($$t{current})) {
    @r = getsince($$t{name}, $$t{current}, $option{startdate});
  } else { # "active" migration: pull in only the linked records.
    @r = grep { ref $_ } map { getrecord($$t{name}, $_, $$t{idfield}) } uniq(@{$idlist{$$t{name}}});
  }
  print "  * Attempting to migrate " . @r . " records.\n    ";
  pgmaketable($t) if scalar @r;
  my @field = map { $$_{name} } @{$$t{fields}};
  my %fname = map { $$_{name} => ($$_{pgname} || $$_{name}) } @{$$t{fields}};
  my $c = 0; $|=1;
  for my $record (@r) {
    my $pgrec = +{ map { $fname{$_} => $$record{$_} } @field };
    pgstore(pgtablename($$t{name}), $pgrec);
    $c++;
    if (not ($c % 25)) {
      print ".";
      print "  ($c)\n    " if not ($c % 1500);
    }
  }
  print "\n";

  if (($option{mode} eq "active") or ($option{mode} eq "current")) {
    print "  * Taking note of foreign keys.\n";
    for my $fkfield (grep { ref $$_{link} } @{$$t{fields}}) {
      for my $fk (@{$$fkfield{link}}) {
        push @{$idlist{$$fk{t}}}, $_ for uniq(map { $$_{$$fkfield{name}} } @r);
      }}}
}


exit 0; # Subroutines follow

sub uniqrec {
  my $idfield = shift @_;
  my %seen;
  return grep { not $seen{$$_{$idfield}} } @_;
}

sub uniq {
  my %seen;
  return grep { not $seen{$_}++ } @_;
}

sub menu {
  my (@item) = @_;
  for my $i (@item) {
    if (ref $i) {
      my ($acel, $name, $descr) = @$i;
      print color("bold cyan on_black") . $acel;
      print color("reset") . color("white on_black") . ") ";
      print color("bold white on_black") . $name;
      print color("reset") . color("white on_black") . "    ";
      print color("cyan") . $descr;
      print color("reset") . color("white on_black") . "\n";
    } else {
      print color("reset") . color("bold green on_black") . $i . "\n";
    }
  }
  print color("reset") . "\n\n";
  my $response = "";
  while (1) {
    $response = ReadKey 0;
    for my $i (grep { ref $_ } @item) {
      my ($acel, $name, $descr) = @$i;
      if (((lc $response) eq (lc $acel)) or ($response eq $name)) {
        return lc $acel;
      }}}
}

