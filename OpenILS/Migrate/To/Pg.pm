# -*- cperl -*-

package OpenILS::Migrate::To::Pg;

use Carp;
use strict;
use DBI;
use DateTime::Format::Pg;
use Exporter;

our %pgconnectinfo;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = qw(&pgconnect &pgstore &pgdeltable &pgcreatetable &pgnuketable &pgmaketable &pgtablename);
@EXPORT_OK   = qw(%pgconnectinfo);
%EXPORT_TAGS = ( DEFAULT => [qw(&pgconnect &pgstore &pgdeltable &pgcreatetable &pgnuketable)],
                 Both    => [qw(%pgconnectinfo)]);

sub pgtablename {
  my ($name) = @_;
  $name =~ s/.*[.]//g;
  $name = lc $name;
  return $name;
}

sub pgconnect {
  # Returns a connection to the Postgres database.
  # Used by the other functions in this file.
  our %arg = @_;

  $pgconnectinfo{dbname} = $arg{dbname} || $pgconnectinfo{dbname} || askuser("the name of the Postgres database (default: MigrationTest)") || "MigrationTest";
  $pgconnectinfo{host}   = $arg{host}   || $pgconnectinfo{host}   || askuser("the host Postgres runs on (default: localhost)") || "localhost";
  $pgconnectinfo{user}   = $arg{user}   || $pgconnectinfo{user}   || askuser("the Postgres account username (default: pguser)") || "pguser";
  $pgconnectinfo{pass}   = $arg{pass}   || $pgconnectinfo{pass}   || askuser("the Postgres account password (default: pgpass)") || "pgpass";

  my $db = DBI->connect("dbi:Pg:dbname=$pgconnectinfo{dbname};"
                        . "host=$pgconnectinfo{host}",
                        $pgconnectinfo{user}, $pgconnectinfo{pass},
                        {'RaiseError' => 1, AutoCommit => 1})
    or die ("Cannot Connect: $DBI::errstr\n");
  return $db;
}

sub pgnuketable {
  my ($table) = @_;
  my $tname = (ref $table) ? pgtablename($$table{name}) : $table;
  my $qstring = qq[DROP TABLE IF EXISTS "$tname"];
  my $db = pgconnect();
  eval {
    my $q = $db->prepare($qstring);
    $q->execute();
  };
  if ($@) {
    carp "pgnuketable(): failed query string was $qstring\n";
  }
}

sub pgmaketable {
  my ($table) = @_;
  my $db = pgconnect();
  my $tname = pgtablename($$table{name});
  my $qstring = "CREATE TABLE $tname (" . (join ", ", map {
    my $f = $_;
    my $name = $$f{pgname} || $$f{name};
    qq[$name $$f{type}]
  } @{$$table{fields}} ) . ")";
  my $q;
  eval {
    $q = $db->prepare($qstring);
    $q->execute();
  };
  if ($@) {
    die "pgmaketable(): failed query string was $qstring\n";
  }
}

sub pgstore {
  my ($table, $r) = @_;
  croak "Incorrect argument: record must be a hashref" if not ('HASH' eq ref $r);
  my %r = %{$r};
  croak "Record must contain at least one field" if not keys %r;
  my $db = pgconnect();
  my @field = sort keys %r;
  my @ques  = map { "?" } @field;
  my @values  = map { $r{$_} } @field;
  my ($result, $q);
  #warn "Attempting to add record: " . Dumper($r) . "\n\n";
  eval {
    $q = $db->prepare("INSERT INTO $table (". (join ", ", @field)
                      . ") VALUES (" . (join ", ", @ques) . ")");
    $result = $q->execute(@values);
  };
  if ($@) {
    use Data::Dumper;
    confess "Unable to add record: $@\n" . Dumper(@_);
  }
  #if ($result) {
  #  my $idq = $db->prepare("SELECT currval(pg_get_serial_sequence('$table','id'))");
  #  $idq->execute();
  #  my $res2 = $idq->fetchrow_arrayref();
  #  $db::added_record_id=$$res2[0]; # Calling code can read this magic variable if desired.
  #} else {
  #  warn "addrecord failed: " . $q->errstr;
  #}
  return $result;
}

sub askuser {
  my ($thing) = @_;
  $|=1;
  print "Enter $thing: ";
  my $answer = <STDIN>;
  chomp $answer;
  return $answer;
}

sub DateTime::Format::ForDB {
  my ($dt) = @_;
  if (ref $dt) {
    my $fmt = "" . DateTime::Format::Pg->format_datetime($dt);
    return $fmt;
  }
  carp "Not a valid datetime object: $dt, $@$!";
}

