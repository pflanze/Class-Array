package Class::Array::Exception;

# Sat Dec 29 11:50:50 2001  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id: Exception.pm,v 1.7 2002/04/26 16:20:57 chris Exp $

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
     catch * {
         print LOG "Some unknown exception or error: $@";
     }
 }
 catch * {
     print LOG $@;
 }
 finally {
     close FILE; # guaranteed to be executed
 }

=head1 DESCRIPTION

Base class for building Class::Array based Exception classes
acting similar to Error.pm.

Whenever a subclass of Class::Array::Exception is use'd,
it invokes a perl source filter (Error::Filter) that 
translates try, catch, otherwise and finally keywords to native perl.
For details see L<Error::Filter>.

Class::Array::Exception defines a few public fields (sorry
about the namespace pollution, should I keep them protected?):

    ExceptionText       Text,
    ExceptionValue      value given as arguments to throw.
    ExceptionPackage    Package,
    ExceptionFile       file and
    ExceptionLine       line from where throw was called.
    ExceptionRethrown   True if rethrown (it's an array ref of
                        arrayrefs containing all values from 'caller')

The class is overloaded so you can simply access $@ in string
or number context and get a nice error summary or the ExceptionValue
respectively.

=head1 CLASS METHODS

=over 4

=item new( text, value [, caller_i ] )

=item throw( text, value [, caller_i ]  )

These are the same except that throw actually calls die, and
that throw always records the package/file/line where it is called from
whereas new only does this if caller_i is defined. caller_i defines 
which caller (how many levels up the call stack) should be recorded.

NOTE: you can use throw as an object method as well, it then behaves
identical to rethrow. (I find it better to explicitely use "rethrow" 
for this purpose though, since it expresses better what it does.
'throw' is only a hybrid class/object method since
Error.pm uses 'throw' to rethrow an exception (as does C++).)

=back

=head1 OBJECT METHODS

=over 4

=item ethrow ([ caller_i ])

=item throw_existing ([ caller_i ])

These do the same (I didn't find a really good name for them yet,
I would like to just use 'throw' for that purpose but that's already
used for compatibility (see above)), namely throw an existing exception object
that has been created by 'new'. 
They record the package/file/line where they are called from,
erase the ExceptionRethrown field and then call die.
This makes it possible to reuse exception objects.
For caller_i see 'new'/'throw'.

=item rethrow

Records package, file and line where rethrow is called from
into ExceptionRethrown and then calls die. 

=item stringify

=item value

The two methods used for overloading in string or number context.
Override them if you want.

=item text

Returns the contents of the exception as text, without class, line or
backtrace information (by default "ExceptionText (ExceptionValue)").

=back

=head1 AUTHOR

Christian Jaeger, pflanze@gmx.ch

=cut


use strict;
require Error::Filter; # we don't need to be filtered here so don't use it.

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
	'0+'	   =>	'value',
	'bool'     =>   sub (){1}, # short cut this segfaulting bool 
	'fallback' =>	1  # 1 will give segfaults under 5.6.1 when falling back from boolean test, and since the fallen back boolean operation would probably be slow anyway, be sure to test for ref($@) *first* and only after that for trueness ($@ seems to never be undef so you can't test for that)
);

sub import {
	my $class=shift;
	my $caller=caller;
	$class->SUPER::import(-caller=> $caller, @_);
	no strict 'refs';
	if (${"${caller}::".__PACKAGE__."::filtered"}) {
		#print "$caller Already filtered\n";
	} else {
		Error::Filter->import;
		${"${caller}::".__PACKAGE__."::filtered"}=1;
	}
}

sub new {
	my $class=shift;
	my ($text,$value,$caller_i)=@_;
	#my $self= $class->SUPER::new;
	my $self = bless [], $class;
	@$self[ExceptionText,ExceptionValue]= ($text,$value);
	@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller($caller_i) if defined $caller_i;
	$self
}

sub throw {
	my $class=shift;
	if (ref $class) {
		#if ($self->[ExceptionRethrown]) {
			if (defined $class->[ExceptionPackage]) {
				# rethrow
				push @{$class->[ExceptionRethrown]}, [ caller ];
				die $class
			} else {
				my ($p,$f,$l)=caller;
				die "'throw' of a pristine exception object not allowed, use ethrow instead at $f line $l\n";
			}
		#} else {
		#	# throw the existing but never thrown exception object
		#	...see below
		#	$class->[ExceptionRethrown]=[];
		#	die $class
		#}
		#  We *could* do all this, to make it possible to 'throw' a 'new'ly created
		#  exception object so it is distinct from being rethrown, but I doubt this
		#  makes much sense, I think it's better to always use ethrow for that purpose.
	} else {
		# create new object
		my ($text,$value,$caller_i)=@_;
		#my $self= $class->SUPER::new;
		my $self = bless [], $class;
		@$self[ExceptionText,ExceptionValue]= ($text,$value);
		@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller($caller_i||0); ## is this a costly operation?
		# do this   $self->[ExceptionRethrown]=[];  and then check above so throw $@ can decide if it's the first throw or not?
		die $self
	}
}

sub throw_existing { # throw existing  (erase rethrow data before doing so)
	my $self=shift;
	undef $self->[ExceptionRethrown];# or $self->[ExceptionRethrown]=[];
	@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller(@_);
	die $self
}

sub ethrow { # same as throw_existing
	my $self=shift;
	undef $self->[ExceptionRethrown];# or $self->[ExceptionRethrown]=[];
	@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller(@_);
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
	(defined $self->[ExceptionValue] ? " ($self->[ExceptionValue])" : "").
	( defined($$self[ExceptionFile]) and !defined($self->[ExceptionText]) || $self->[ExceptionText]!~/\n/s
		? " at $self->[ExceptionFile] line $self->[ExceptionLine].\n".
			join("",map { "\t...rethrown at $_->[1] line $_->[2]\n" } @{$self->[ExceptionRethrown]})
		: ""
	)
}

sub text {
	my $self=shift;
	(defined $self->[ExceptionText] ? "$self->[ExceptionText]" : "").
	(defined $self->[ExceptionValue] ? " ($self->[ExceptionValue])" : "(no value)")
}

sub value {
	shift->[ExceptionValue]
}


1;
