#!/usr/local/bin/perl -w
#
# newsuperior.pl
# morgan@morganjones.org

# work around for ldap servers that don't support the newsuperior changetype.
# see README for example usage

use Net::LDAP;
use strict;
use Data::Dumper;
use Getopt::Std;

my %opts;

sub print_usage();
sub get_groups($$);

getopts('b:f:u:D:H:y:n', \%opts);

$opts{b} || print_usage();
$opts{f} || print_usage();
$opts{u} || print_usage();
$opts{y} || print_usage();
$opts{D} || print_usage();
$opts{h} || print_usage();
$opts{n} && print "-n used, no changes will be made\n\n";

open (IN, $opts{y}) || die "can't open $opts{y}";
my $pass = <IN>;
chomp $pass;
close IN;

my $ldap = Net::LDAP->new($opts{h}) || die "$@";
my $bind_r = $ldap->bind($opts{D}, password => $pass);
$bind_r->code && die "unable to bind as ", $opts{D}, ": ", $bind_r->error;

my $r = $ldap->search (base => $opts{b}, filter => $opts{f},
		       attrs => ['*', 'nssizelimit', 'nslookthroughlimit']);
$r->code && die "problem with search $opts{f}: ", $r->error;

my @e = $r->entries;

if ($#e<0) {
    print "no results returned for $opts{f}\n";
    exit;
}

if ($#e>0) {
    print "More than one result for $opts{f}, you must search out a single entry\n";
    exit;
}

my $e = $e[0];
print "original entry";
print $e->ldif();

my $dn = $e->dn();

my @eg = get_groups($ldap, $dn);

my $newdn = (split (/,/, $dn))[0];
$newdn .= ",".$opts{u};

if ($newdn eq $dn) {
    print "entry already has a superior of $opts{u}, no changes made.\n";
    exit;
}

unless (exists $opts{n}) {
    print "deleting entry...\n";
    $e->delete->update($ldap)
}

$e->dn($newdn);

print "\nadding new entry ", $e->dn, "\n";

unless (exists $opts{n}) {
    my $r4 = $ldap->add ($e);
    $r4->code && die "problem adding: ", $r->error;
}

# check to see if groups memberships were cleared.  If not, clear
# them.  If so move on to re-adding with new dn

my @eg2 = get_groups($ldap, $dn);

if (@eg2) {
    print "\n";
    print "these might be deleted by the server automatically when you run without -n\n"
      if (exists $opts{n});

    print "removing $dn from...\n";
    for my $eg2 (@eg2) {
	print "\t", $eg2->dn(), "\n";
	
	unless (exists $opts{n}) {
	    my $delete_dn_r = $eg2->delete(uniquemember => $dn)->update($ldap);
	    $delete_dn_r->code && warn "problem deleting: ", $delete_dn_r->error;
	}
	
    }
}

print "\nadding $newdn to...\n";
for my $eg (@eg) {
    print "\t", $eg->dn(), "\n";

    unless (exists $opts{n}) {
	my $add_dn_r = $eg->add(uniquemember => $newdn)->update($ldap);
	$add_dn_r->code && warn "problem adding: ", $add_dn_r->error;
    }
}

sub print_usage() {
    print "usage: $0  -D <binddn> -y <pass file> -H <host> -b <basedn> -f <filter> -u <newsuperior>\n\n";
    exit;
}


sub get_groups($$) {
    my ($ldap, $dn) = @_;
    
    my $rg = $ldap->search (base => $opts{b}, filter => "uniquemember=".$dn);
    $rg->code && die "problem with search $opts{f}: ", $r->error;
    return $rg->entries;
}
