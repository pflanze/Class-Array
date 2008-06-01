package Class::Array::WithDBI;

# Fri Mar  8 20:53:40 2002  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id: WithDBI.pm,v 1.4 2002/03/16 01:18:51 chris Exp $

=head1 NAME

Class::Array::WithDBI 

=head1 DESCRIPTION


=cut

use Carp;

require Class::Array;
@ISA= 'Class::Array';

use strict;
no strict 'refs';

sub create_sthreader {
	my $class=shift;
	croak "Class method create_sthreader called on a reference" if ref $class;
	my $methodname=shift or croak "Missing methodname argument for create_set_from_sth";
	my $sth=shift; ref $sth or croak "Missing dbi statement handle object as 2nd parameter";
	# the remaining arguments is a list with values to return instead of putting into the object
	my @returnvalues=@_;
	my %returnvalues= map {$_=>undef} @returnvalues;
	
	*{"${class}::$methodname"}= sub {
		my $self=shift;
		my $class= ref($self) or croak("$methodname: Object method called without object");
		my $fields= $sth->{NAME} or Carp::croak("could not get NAME hash from statement handle - did you execute it? Stopped");
		my $lookuphash= $class->class_array_namehash(undef,undef,scalar caller); #do {
#			my $calling_class= caller;
# 			if ($calling_class eq $class) { # creation of sthreader in class itself. So we also want protected fields and our own private fields.
# 				if (*{"${class}::CLASS_ARRAY_NAMEHASH"}{HASH}) {
# 					*{"${class}::CLASS_ARRAY_NAMEHASH"}{HASH}
# 				} else {
# 					$class->create_namehash(1, $calling_class);
# 				}
# 			} else { # we create the sthreader from outside the class.    Should we distinguish whether we have inherited that class, or are completely outside so we don't know protected fields?
# 				if ($calling_class->isa($class)) {
# 					$class->create_namehash(1, $calling_class); # $class ne $calling_class
# 				} else {
# 					$class->create_namehash
# 				}
# 			}
#		};

		my $idx;
		my $retidx=0;
		my @segments;
		for (@$fields) {
			#/^\w+$/ or Carp::croak("field '$_' from statement handle has an invalid format")
			if (exists $returnvalues{$_}) {
				# return this field to output
				##$returnvalues{$_}= $retidx++;
				push @segments, [0, $retidx++];
				delete $returnvalues{$_};
			} elsif (exists $lookuphash->{$_}) {
				# field exists in object;
				##gar nich nötig: defined ($idx= $lookuphash->{$_}) or $idx= eval "${class}::$_"; die "???: $@" if $@;
				push @segments, [1, "${class}::$_"]; #"\$self->[$_]";
			} else {
				croak("$methodname: field '$_' from statement handle is not an object field (at least none that's accessible to you) and has not been defined as return field");
			}
		}
		carp("$methodname: the following return fields have been given but are not in the database output: '".join("', '",keys %returnvalues)."'")
			if keys %returnvalues;

		# create second stage code:
		my (@parts,@subparts);
		my $parttype;
		for (@segments) {
			if (defined $parttype) {
				if ($parttype==1) {
					if ($parttype==$_->[0]) {
					} else { # it was 1; -> terminate object writes
						if (@subparts>1) {
							push @parts, '@{$self}['.join(",",@subparts).']';
						} else {
							push @parts, '$self->['.$subparts[0].']';
						}
						@subparts=();
						$parttype=$_->[0];
					}
					push @subparts,$_->[1];
				} else {
					if ($parttype==$_->[0]) {
					} else { # it was 0; -> terminate return writes
						if (@subparts>1) {
							push @parts, '@retv['.join(",",@subparts).']';
						} else {
							push @parts, '$retv['.$subparts[0].']';
						}
						@subparts=();
						$parttype=$_->[0];
					}
					push @subparts,$_->[1];
				}
			} else {
				$parttype= $_->[0];
				push @subparts,$_->[1];
			}
		}
		if (@subparts) {
			# terminate the rest
			if ($parttype==1) {
						if (@subparts>1) {
							push @parts, '@{$self}['.join(",",@subparts).']';
						} else {
							push @parts, '$self->['.$subparts[0].']';
						}
			} else {
						if (@subparts>1) {
							push @parts, '@retv['.join(",",@subparts).']';
						} else {
							push @parts, '$retv['.$subparts[0].']';
						}
			}
		} else {
			warn "???";
		}
		my $code='
		sub {
			my $self=shift;
			my @retv;
			('.join(",",@parts).')= $sth->fetchrow_array;
			@retv
		}';
		#warn "Generated the following code for '${class}::$methodname': $code\n";
		#undef *{"${class}::$methodname"};
		delete ${"${class}::"}{$methodname};
		$code= *{"${class}::$methodname"} = eval $code;
		die "Error while generating second stage code for '${class}::$methodname': $@" if $@;
		&$code($self);
	};
}




1;

__END__

sub {
	my $self=shift;
	my @retv;
	($self->[],$retv[],) = $sth->fetchrow_array;
	@retv
}


# stage 0: call of create_set_from_sth:
#	create first stage handler

# first stage: (first call to the created method)
#	read colnames from $sth and create another eval from it. Replace itself with that one.
#	


# Ich *benötige* den hash, weil sonst, per eval, isses eben doch evtl gefahrlich weil 
# subs ausgefurht werden konnen die nicht sollten.?

----
Sat,  9 Mar 2002 18:42:38 +0100

Shit massiver Fehler:

$lookuphash ab arrays bilden geht nicht, da die inherited felder dann unbekannt sind.


#Zurückspeichern:

--

Also neues Konzept needed für das hash zeugs.

- in alias_fields drin?










Die neue Idee:
ein EL::DB Teil.

->prepare
dann



Weil mehrere Quellen speichern.
->create_saver( class1,class2, 'Id','Bla','Bleh');
->save_with_values_from($obj1, $obj2, $value0,$value1,$value2);

Aber: bei select krieg ich von der db  nach dem execute aber vor dem fetch  die kolonnen.
Beim saven geht das doch gar nich!!!!!!

D.h. ich muss beim creator die Feldreihenfolge angeben.

->create_saver('save_blabla', [class1, @fields], [class2, @fields2], 'Id','Bla','Bleh');

Aber brauch ich wirklich einen saver creator?
Sonst muss ich halt immer checken ob dieselben fields oder andere das ist müll. Also doch.

dann
$sth->save_blabla
(Aber he: ich kann ja ab dem sth das caching determinieren? hash mit $dbh als key? Aber nein, dann gingen nur eine savemethode pro $sth.(Das
ist zwar auch der normalfall)

Hmm was wenn einfach selber Klassen schreiben für jeden $sth?

package EL::Sth::Hubaru;
my $hubaru= $DB->prepare(..);
sub executewith {
	my $self=shift; (brauchts ja gar nich weil eh klar iss dass hubaru hierhin gehört?
	
}

oder

package EL::Sth::Hubaru;
(nun kommt wieder der scheiss von fahlkonstruktion voin dbi in die quere)
(weil wenn ich beim prepare automatisch blessen wollte dann....) 
(Aber es geht ja so:)
my $hubaru= $DB->prepare(..);
bless $hubaru;
sub executewith {
	my $self=shift; (brauchts ja gar nich weil eh klar iss dass hubaru hierhin gehört?
	
}
