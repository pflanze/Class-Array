package Class::Array::WithDBI;

# Fri Mar  8 20:53:40 2002  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id$

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
	croak "Class method create_set_from_sth called with a reference" if ref $class;
	my $methodname=shift or croak "Missing methodname argument for create_set_from_sth";
	my $sth=shift; ref $sth or croak "Missing dbi statement handle object as 2nd parameter";
	# the remaining arguments is a list with values to return instead of putting into the object
	my @returnvalues=@_;
	my %returnvalues= map {$_=>undef} @returnvalues;
	
	*{"${class}::$methodname"}= sub {
		my $self=shift;
		my $class= ref($self) or croak("$methodname: Object method called without object");
		my $fields= $sth->{NAME} or Carp::croak("could not get NAME hash from statement handle - did you execute it? Stopped");
		my $lookuphash= *{"${class}::CLASS_ARRAY_NAMEHASH"}{HASH} || {
			map { $_=> undef } 	@{"${class}::_CLASS_ARRAY_PUBLIC_FIELDS"},
								@{"${class}::_CLASS_ARRAY_PROTECTED_FIELDS"},
								@{"${class}::_CLASS_ARRAY_PRIVATE_FIELDS"}
		};

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
				croak("$methodname: field '$_' from statement handle is not an object field and has not been defined as return field");
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
