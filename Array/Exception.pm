package Class::Array::Exception;

# Sat Dec 29 11:50:50 2001  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id: Exception.pm,v 1.2 2002/04/02 03:08:33 chris Exp $

=head1 NAME

Class::Array::Exception - exception base class

=head1 SYNOPSIS

 use My::IOException; # let's assume this inherits from My::Exception, 
        # which in turn inherits from Class::Array::Exception
 
 try {
     open FILE, $file or die "Could not open $file: $!";
     try {
         ..
         throw My::IOException "You don't have permission", EPERM;
         ..
     }
     catch My::Exception {
         print LOG "Some of my exceptions occured: $@";
     }
     catch Some::Other::Exception, Foreign::Exception {
         print LOG "Some other exception that I know of: $@";
     }
     otherwise {
         print LOG "Some unknown exception or error: $@";
     }
 }
 otherwise {
     print LOG $@;
 }
 finally {
     close FILE; # guaranteed to be executed
 }

=head1 DESCRIPTION

Base class for building Class::Array based Exception classes
acting similar to Error.pm.

Whenever a subclass of Class::Array::Exception is use'd,
it invokes a perl source filter (Class::Array::ExceptionFilter) that 
translates try, catch, otherwise and finally keywords to native perl.
For details L<Class::Array::ExceptionFilter>.

Class::Array::Exception defines a few public fields (sorry
about the namespace pollution, should I keep them protected?):

    ExceptionText       Text,
    ExceptionValue      value given as arguments to throw.
    ExceptionPackage    Package,
    ExceptionFile       file and
    ExceptionLine       line from where throw was called.
    ExceptionRethrown   True if rethrown (is an array ref)

The class is overloaded so you can simply access $@ in string
or number context and get a nice error summary or the ExceptionValue.

=head1 CLASS METHODS

=over 4

=item new( text, value )

=item throw( text, value )

These are the same except that throw actually calls die and also
sets the ExceptionPackage,ExceptionFile and ExceptionLine fields.

=back

=head1 OBJECT METHODS

=over 4

=item rethrow

Records package, file and line where rethrow is called from
into ExceptionRethrown and calls die again. 

NOTE: this method is currently used by Class::Array::ExceptionFilter;
maybe I should instead just use 'throw' as an object method as well
to make it easier to use Class::Array::ExceptionFilter with
Error::Simple (as Error.pm replacement).

=back

=head1 AUTHOR

Christian Jaeger, pflanze@gmx.ch

=cut


use strict;
require Class::Array::ExceptionFilter;

use Class::Array -fields=> qw(
-public
	ExceptionText
	ExceptionValue
	ExceptionPackage
	ExceptionFile
	ExceptionLine
	ExceptionRethrown
); # ExceptionDepth   what for?



use overload (
	'""'	   =>	'stringify',
	'.'	       =>	'stringify', # since we don't fallback anymore / make call path a bit shorter :)
	'0+'	   =>	'value',
	'bool'     =>   sub (){1}, # short cut this segfaulting bool 
	'fallback' =>	1  # 1 will give segfaults under 5.6.1 when falling back from boolean test, and since the fallen back boolean operation would probably be slow anyway, be sure to test for ref($@) *first* and only after that for trueness ($@ seems to never be undef so you can't test for that)
);

sub import {
	my $class=shift;
	$class->SUPER::import(@_);
	my $caller=caller;
	no strict 'refs';
	if (${"${caller}::".__PACKAGE__."::filtered"}) {
		#print "$caller Already filtered\n";
	} else {
		Class::Array::ExceptionFilter->import;
		${"${caller}::".__PACKAGE__."::filtered"}=1;
	}
}

sub new {
	my $class=shift;
	my ($text,$value)=@_;
	#my $self= $class->SUPER::new;
	my $self = bless [], $class;
	@$self[ExceptionText,ExceptionValue]= ($text,$value);
	$self
}

sub throw {
	my $class=shift;
	my ($text,$value)=@_;
	#my $self= $class->SUPER::new;
	my $self = bless [], $class;
	@$self[ExceptionText,ExceptionValue]= ($text,$value);
	@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller; ## is this a costly operation?
	die $self
}

sub rethrow {
	my $self=shift;
	push @{$self->[ExceptionRethrown]}, [ caller ];
	die $self
}

sub stringify {
	my $self=shift;
	ref($self).
	(defined $self->[ExceptionText] ? ": $self->[ExceptionText]" : "").
	( defined($$self[ExceptionFile]) and !defined($self->[ExceptionText]) || $self->[ExceptionText]!~/\n/s
		? " at $self->[ExceptionFile] line $self->[ExceptionLine].\n".
			join("",map { "\t...rethrown at $_->[1] line $_->[2]\n" } @{$self->[ExceptionRethrown]})
		: ""
	)
}

sub value {
	shift->[ExceptionValue]
}


1;
