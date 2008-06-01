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
                        arrayrefs containing package/file/line
                        of the 'caller' of rethrow[/throw];
                        each rethrow[/throw] pushes another row)
    ExceptionStacktrace May be filled upon calling 'throw' or 'ethrow'
						(see below)

The class is overloaded so you can simply access $@ in string
or number context and get a nice error summary or the ExceptionValue
respectively.

'ExceptionStacktrace' is only set if stacktraces have been switched on
prior to throwing the exception using the set_stacktrace() class method.


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

=item set_stacktrace( false/true [, 0/n [, true/false [, stacktrace_maxarglen]]] )

Sets the value of $Class::Array::Exception::stacktrace [and
$Class::Array::Exception::stacktrace_nargs, ...::stacktrace_output 
and ...::stacktrace_maxarglen].
(Using an inheritable method seems cooler for this purpose since
users of your derived exception class don't have to remember that your
class inherits from Class::Array::Exception.) 

First argument:
false (which is the default) means that the 'ExceptionStacktrace' will not
be set upon throwing an exception (which will be faster). 

Second argument (defaults to 10):
0 means that 'ExceptionStacktrace'
will be set to contain only the caller information (subroutine arguments),
a higher value means that also up to the n first subroutine arguments of each stack 
frame will be included in 'ExceptionStacktrace' as array ref in column 10.

Third argument:
true (which is the default) meant that the stacktrace will 
also be included in the output of 'stringify' (if you happen to override 
stringify, you should make it append the output of the 'stacktrace' object method)

Forth argument: the maximum length output of each string subroutine argument (default: 10).

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

Pushes package, file and line where rethrow has been called from
into ExceptionRethrown and then calls die. 

=item stringify

=item value

The two methods used for overloading in string or number context.
stringify uses the 'text' method to retrieve the contents of the
exception, so you should only ever need to override the text method.

=item text

Returns the contents of the exception as text, without class, line or
rethrow tracing information (by default "ExceptionText (ExceptionValue)").

=item stacktrace

If switched on by means of set_stacktrace (package var stacktrace_output), 
returns the stacktrace formatted as text, otherwise returns the empty string.

=item stacktrace_loa

Returns a list of arrays each representing a frame of the stacktrace (containing
[ file, line, "subroutine(args)"], where args are shortened according to the 
stacktrace settings).
Used by the 'stacktrace' method.

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
	ExceptionStacktrace
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

use vars qw/$stacktrace $stacktrace_nargs $stacktrace_output $stacktrace_maxarglen/;
$stacktrace_nargs= 10;
$stacktrace_output=1;
$stacktrace_maxarglen= 10;

sub set_stacktrace {
	my $class=shift;
	if (@_) {
		$stacktrace=shift;
		if (@_) {
			$stacktrace_nargs= shift;
			if (@_) {
				$stacktrace_output= shift;
				if (@_) {
					$stacktrace_maxarglen= shift;
				}
			}
		}
	} else {
		$stacktrace
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
		my $self = bless [], $class; # my $self= $class->SUPER::new;
		@$self[ExceptionText,ExceptionValue]= ($text,$value);
		@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller($caller_i||0); ## is this a costly operation?
		$self->save_stacktrace($caller_i||0+1) if $stacktrace;
		# do this   $self->[ExceptionRethrown]=[];  and then check above so throw $@ can decide if it's the first throw or not?
		die $self
	}
}

sub throw_existing { # throw existing  (erase rethrow data before doing so)
	my $self=shift;
	undef $self->[ExceptionRethrown];# or $self->[ExceptionRethrown]=[];
	@$self[ExceptionPackage,ExceptionFile,ExceptionLine]= caller(@_);
	$self->save_stacktrace($_[0]||0+1) if $stacktrace;
	die $self
}

*ethrow = *throw_existing{CODE};

sub save_stacktrace {
	my $self=shift;
	my ($caller_i)=@_;
	my $i= $caller_i + 1; # (we already got the primary caller)
	if ($stacktrace_nargs) {
		{ 
			package DB; 
			while (caller($i)) {
				push @{$self->[Class::Array::Exception::ExceptionStacktrace]}, 
					[ caller($i), ## should we check if caller is '(eval)' so we don't waste memory copying stale args? 8//
						[@DB::args <= $Class::Array::Exception::stacktrace_nargs ? 
							@DB::args 
							: ( @DB::args[0..$Class::Array::Exception::stacktrace_nargs-1], "...")
						] 
					];
				$i++ 
			};
		}
	} else {
		while (push @{$self->[ExceptionStacktrace]}, [ caller($i) ]) { $i++ };
	}
}

sub rethrow {
	my $self=shift;
	push @{$self->[ExceptionRethrown]}, [ caller ];
	die $self
}

sub stringify {
	my $self=shift;
	my $txt= $self->text;
	ref($self)
	.($txt ? ": $txt " : "")
	.( defined($$self[ExceptionFile]) and !defined($self->[ExceptionText]) || $self->[ExceptionText]!~/\n$/s
		? " at $self->[ExceptionFile] line $self->[ExceptionLine].\n"
			.join("",map { "\t...rethrown at $_->[1] line $_->[2]\n" } @{$self->[ExceptionRethrown]})
			.($stacktrace ? $self->stacktrace : "")
		: "")
}

sub stacktrace {
	my $self=shift;
	if ($stacktrace_output and $self->[ExceptionStacktrace]) {
		"\tStacktrace:\n"
		.join("", map { 
				"\t$_->[0] line $_->[1] called $_->[2]\n"
			} $self->stacktrace_loa)
	} else {
		""
	}
}

sub stacktrace_loa {
	my $self=shift;
	map {
		[$_->[1],$_->[2],
			($_->[3] eq '(eval)' ?
			"eval{} or try{}"  ##possibly we get here from eval""?
			: $_->[4] ? 
				# sub call has args
				$_->[3]
				.($_->[10] ? 
					do {
						# format argument list; code affected by Carp::Heavy
						my $c; # this works! :)
						"(".join(", ", map {
							if (ref) {
								"$_"
							} else {
								$c= length > $stacktrace_maxarglen ? 
									substr($_,0,$stacktrace_maxarglen)."..."
									: $_;
								$c=~ /^-?[\d.]+$/s ? 
									$c
								: 	do{
									$c=~ s/'/\\'/g;
									$c=~ s/([\200-\377])/sprintf("M-%c",ord($1)&0177)/eg;
									$c=~ s/([\0-\37\177])/sprintf("^%c",ord($1)^64)/eg;
									"'$c'"
								}
								# (Hmm, thread id stuff?)
							}
						} @{$_->[10]} )
						.")"
					}
					: "")
				: '&'.$_->[3] # no args
			)
		]
	} @{$self->[ExceptionStacktrace]}
}

sub text {
	my $self=shift;
	(defined $self->[ExceptionText] ? "$self->[ExceptionText]" : "")
	.(defined $self->[ExceptionValue] ? " ($self->[ExceptionValue])" : "(no value)")
}

sub value {
	shift->[ExceptionValue]
}


1;
