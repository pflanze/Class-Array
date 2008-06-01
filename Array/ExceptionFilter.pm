package Class::Array::ExceptionFilter;

# copyright 2002 by christian jaeger , pflanze@gmx.ch
# published under the same terms as perl
#
# $Id: ExceptionFilter.pm,v 1.5 2002/04/10 02:51:37 chris Exp $

=head1 NAME

Class::Array::ExceptionFilter

=head1 SYNOPSIS

See synopsis from L<Class::Array::Exception>.

=head1 DESCRIPTION

This uses the perl source filtering technique to implement a 'proper'
try/catch syntax. It's paragon is L<Error> (from Graham Barr), but it
dispenses with closures altogether and so should be both faster and not risk any
memory leaks.

Currently it's not fully backwards compatible to Error.pm, though I guess
it's mainly only missing some rewritten base class to be so.

ExceptionFilter sets up a check for all classes used in catch phrases
(and also those used for throw and rethrow, see below),
so you will get a compile time warning if warnings are on and a listed class 
is not loaded or does not provide 'throw' and 'rethrow' methods. 

=head1 SYNTAX

The filter currently introduces the following syntax:

 try BLOCK [;] [ catch LIST [with] BLOCK | otherwise BLOCK | finally BLOCK ]

=over 4

=item try BLOCK [;]

Exceptions (any form of 'die') thrown inside this block is catched
(just places an eval wrapper around BLOCK).
If a semicolon is given after the block, you can assign the return
value from BLOCK to a variable like in 'my $ret= try {...}; catch...'.
When there's no semicolon, the return value of the last catch/otherwise/finally
block is returned instead.

=item catch LIST [with] BLOCK

LIST is a list of CLASS names separated by commas.
If an exception is an object and it matches the requirement ->isa(CLASS), 
the BLOCK is executed with $@ set to the object. If the optional 'with'
keyword is given, @_ is set to contain the object as well (this is for compatibility
with the syntax from Error.pm; it will be slower of course, though).
Multiple catch phrases can be given.

=item otherwise BLOCK

If none of the catch phrases matches, the optional otherwise block is 
executed. If no otherwise block is given, such an exception is propagated 
(rethrown). Only one otherwise block can be given.

=item finally BLOCK

This (optional) block is always executed, regardless whether an error/exception
occured or not, and it is also executed even when an error/exception occurs
in a catch or otherwise block. Uncatched errors/exceptions are
rethrown after the finally block is finished. If another exception occurs
during the finally block, the previously uncatched error/exception is lost.

=back

Note that "throw" and "rethrow" are really methods in the class you call them on, 
but if you use them in indirect object syntax ('throw My::Namespace ()' as opposed
to 'My::Namespace->throw()') ExceptionFilter does check their namespace argument
at compile time, too.

Note that ExceptionFilter will filter your source code each time it is use'd
(from the point of the use statement until a 'no Class::Array::ExceptionFilter;' or
other end marker, see Filter::Simple for details).
So in order not to waste cpu time, you should or could catch the case of multiple
load of your exception base class in the latter. (Class::Array::Exception is
doing this.)

=head1 IMPORTANT

I had to patch Filter::Simple to allow for proper line number accounting.
I also tried to fix a bug in Text::Balanced. You can find the patches
in the Class::Array source distribution. Hopefully some time these patches
will be merged into the main distribution.

=head1 NOTES

I'm open to rename this to Error::Filter if MattS (who first made use of
the namespace) thinks that's ok  and as soon as it is (fully or enough)
backwards compatible to Error.pm

=head1 BUGS

Since this uses the not yet perfect filtering infrastructure
(Filter::Simple, Text::Balanced), and on top of that introduces it's own
lexer, I'm sure that there are cases where it fails. The one I know of is
HERE docs (probably a bug  in Text::Balanced) - be sure not to put a 'try'
right after a here doc,  or put a semicolon before it). Tell me about other
bugs you find.

Another problem may be compilation performance with bigger projects. I'm
sure that this can be improved much, but it will take some effort
(suggestions are to rewrite Filter::Simple/  Text::Balanced to use less
subroutine calls, to integrate their code straight into the exception
filter so only one pass through the text is needed, or to rewrite it in C
or C++. Another one might be to patch perl itself?).

=head1 AUTHOR

Christian Jaeger, pflanze@gmx.ch

=cut

use strict;

use Filter::Simple;
use Text::Balanced qw(extract_codeblock);

use constant DEBUG=> $ENV{DEBUG_EXCEPTIONFILTER}||0;

my @operators= qw(
		->
		<= >= == <=> 
		=~
		!~
		 ||
		+= -= *= **= /*
		 =>
		<<
		>>
		!
		~
		\
		 /  
		...
		..
		< > 
		| ^
		? 
		=
); # ('<<' should be unproblematic here since <<heredocs have already been stripped by Filter::Simple;)  are there more 'X=' operators?
	# % and & have temporarily been removed since there's no easy way to differentiate between the operator and dereferencor
	# well, * (and **?) and && are risky too, so removed them too
push @operators,',';
my @operatorwords= qw(
		lt gt le ge eq ne cmp
		not and or xor x
);
my @specoperators= (
	'(?<!\:)\:(?!\:)', # do not match :: (namespace separator)
	'(?<!\+)\+(?!\+)', # do not match ++ (unary/nonassoc)
	'(?<!\-)\-(?!\-)', # do not match -- (unary/nonassoc)
	'(?<!\d)\.(?!\d)', # do not match decimal point     (is that enough?)
);
my $OPERATOR= join('|', (map { quotemeta } @operators), (map {'\b'.$_.'\b'} @operatorwords), @specoperators);

# we need to create our own marker regex since the one available from Filter::Simple doesn't include parens (and I hacked Filter::Simple, not finished)
my $MARKER= quotemeta("$;\0").'(?:\C{3})(\C{2})'.quotemeta($;); 
		# we can be pretty sure we never filter more than 2**24 strings
		# the (\C{2}) is for the number of newlines in my hacked version of Filter::Simple.
		# the (?:) around \C{3} is to silence some strange warning.


sub jump_afterbracket {
	(extract_codeblock($_, "{}"))[0]   # extract_bracketed doesn't work since #... comment parts are not stripped before we see them
}

sub linesin {
	my ($copy)=@_;
	my $line=0;
	$copy=~ s/$MARKER/$line+= unpack('n',$1); "mZZZZNNm"/sgoe; # is replacing with samesized string really faster?
	$line+= $copy=~ tr/\n/\n/;
	$line
}

sub lineformat {
	my ($line,$filename)=@_;
	$filename=~ s/\"/\\"/g;
	qq{#line $line "$filename"}
}

use vars '$line';
sub transform { # pass in *references* for string and line
	#print "MEINE PArams sind ".join("--",@_)."\n";
	my ($checknamespaces)=pop;
	my ($filename)=pop;# wow!, das geht. Buggybuggybuggy. Dafür unteres nich mehr
	#local (*_) =shift;
	#local (*line) =shift;
	#my ($filename)=shift;
	local (*_,*line)=@_;
	
	if (DEBUG>=2){
	print "Filename='$filename'\n";
	print "----CODE:-------------------\n";
	print "$_\n";
	print "----/CODE-------------------\n";
	}

	my $copy;
	my ($beginpos, $endpos);
	pos($_)=0;
	NEWSTATEMENT: while(1) {
		# advance until something different than whitespace or markers appear
		# (jump over markers since pod sections are converted to markers, too. As are heredocs. And after them, it's (still) newstatement expected.
		#  regrettably this is not that good since it could be a real string, or
		#  even worse, qw() operator as well :/  (is there a way to get back the original
		#  content for a placeholder from filter::simple?))
		CATCHUP: {
			/\G[^\n\S]*/sgoc;
			if (/\G\n/sgoc) {
				$line++;
				print "GOT NEWLINE, incremented line to $line\n" if DEBUG>=2;
				redo CATCHUP;
			}
			if (/\G$MARKER/sgoc) {
				print "GOT MARKER, before line is $line, after it's " if DEBUG>=2;
				$line+= unpack('n',$1);
				print "$line\n" if DEBUG>=2;
				redo CATCHUP;
			}
		}


		if (/\Gtry\b/sgoc) {
			#$beginpos= $-[0]; # *start* of last match
			$beginpos= pos($_)-3; # maybe better for old perls
			if (/\G(\s*)(?={)/sgoc) {
				$copy=$1; $line+= $copy=~ tr/\n/\n/;
				
				my $rethrowlinecode= lineformat($line,$filename); # *start* of the try block

				my (@catchblocks);
				my ($otherwiseblock,$finallyblock);

				my $inter= &jump_afterbracket; # we *have* to copy it since it's a readonly value
#defined $inter ? warn "       inter ist defined\n" : warn "        inter ist undef !\n";
#defined $@ ? warn "       \$\@ ist '$@'\n" : warn "        \$\@ ist undef !\n";
if (defined $@) { # trust defined? or better use ref? or plain bool?
	warn __PACKAGE__." warning (or really a bug of one of the filtering libraries?): $@->{error} in $filename lines $line - "
		.($line+linesin(substr($_,$beginpos,pos($_)-$beginpos)))."\n"
		if $^W;
	last NEWSTATEMENT; # still let earlier modifications through?
}

				$endpos= pos($_);
				if (DEBUG>=2) {
				print "***  try  ***: von $beginpos - $endpos (length of our segment is ".length($_)."), line $line\n";
				print "  --CODE: -------------\n";
				print "  $inter\n";
				print "  --/CODE -------------\n";
				}
# sollten $inter checken offenbar.  Was ist der richtige fehlermeldung vom balanced?
# Dann wenn fehler, gracefully einfach returnen. (Noch ne warnung ausgebn). Hm.
# (Weil AH wenn nich, dann ->'eval;')
				transform(\$inter,\$line,$filename,$checknamespaces);
				pos($_)= $endpos;

				my $replacement;

				# is it followed by a ; ?
				if (/\G(\s*);/sgoc) {
					$copy=$1; $line+= $copy=~ tr/\n/\n/;
					# make  'my $bla= try { }; catch ....;' possible
					$replacement= "eval".$inter."; {";
				} else {
					$replacement= "{ eval".$inter.";";
				}

				# followed by catch|otherwise|finally ?
				while (/\G(\s*)(catch|otherwise|finally)\b/sgoc) {
					$copy=$1; $line+= $copy=~ tr/\n/\n/;
					if ($2 eq 'catch') {
						if (/\G(\s*)([\w:]+(?:\s*,\s*[\w:]+)*)(\s*)(\bwith\b)?(\s*)(?={)/sgoc) {
							$copy= $1.$2.$3.$5; $line+= $copy=~ tr/\n/\n/;
							my @namespaces= split(/\s*,\s*/, $2);
							my $error_pm_compatible= !!$4;
							$inter= substr(&jump_afterbracket,1,-1);

							print "OK GOT CATCH with namespaces (".join("),(",@namespaces).") and interpart (at line $line) '$inter'\n" if DEBUG>=2;
							my $startline=$line;
							$endpos= pos($_);
							transform(\$inter,\$line,$filename,$checknamespaces);
							pos($_)= $endpos;
							push @catchblocks, [
								join(q{') or $@->isa('},@namespaces), # no need to escape single quotes since they can't pass the above regex
								($error_pm_compatible ? 'local @_=($__ExceptionFilterTmp);':'')."\n".
								lineformat($startline,$filename)."\n".$inter
							];
							push @$checknamespaces, map {[ $startline, $_ ]} @namespaces;

						} else {
							die __PACKAGE__.": invalid syntax after 'catch' at $filename line $line\n";
						}
					} elsif ($2 eq 'otherwise') {
						if (/\G(\s*)(?={)/sgoc) {
							if (!defined $otherwiseblock) {
								$copy= $1; $line+= $copy=~ tr/\n/\n/;
								$inter= substr(&jump_afterbracket,1,-1);
								
								print "OK GOT OTHERWISE with interpart (at line $line) '$inter'\n" if DEBUG>=2;
								my $startline=$line;
								$endpos= pos($_);
								transform(\$inter,\$line,$filename,$checknamespaces);
								pos($_)= $endpos;
								$otherwiseblock= lineformat($startline,$filename)."\n".$inter;
								
							} else {
								die __PACKAGE__.": multiple definition of 'otherwise' clause at $filename line $line\n";
							}
						} else {
							die __PACKAGE__.": invalid syntax after 'otherwise' at $filename line $line\n";
						}
					} else { # $2 eq 'finally'
						if (/\G(\s*)(?={)/sgoc) {
							if (!defined $finallyblock) {
								$copy= $1; $line+= $copy=~ tr/\n/\n/;
								$inter= substr(&jump_afterbracket,1,-1);
								
								print "OK GOT FINALLY with interpart (at line $line) '$inter'\n" if DEBUG>=2;
								my $startline=$line;
								$endpos= pos($_);
								transform(\$inter,\$line,$filename,$checknamespaces);
								pos($_)= $endpos;
								$finallyblock= lineformat($startline,$filename)."\n".$inter;

							} else {
								die __PACKAGE__.": multiple definition of 'finally' clause at $filename line $line\n";
							}
						} else {
							die __PACKAGE__.": invalid syntax after 'finally' at $filename line $line\n";
						}
					}
				}

				# Put replacement together:
				$replacement.= 'try__please_put_a_do_block_around_me: { ';
				if (@catchblocks) {
					$replacement.= '
					if(ref $@){
						if($@->isa(\''.
					join( 
						'} elsif($@->isa(\'', map {
							$_->[0].'\')) {
								my $__ExceptionFilterTmp= $@; eval { $@= $__ExceptionFilterTmp;'."\n".
								$_->[1].
								'};
								last try__please_put_a_do_block_around_me;
								'
						} @catchblocks
					).
						'}
					} elsif(! $@){ last try__please_put_a_do_block_around_me }
					'; # now otherwise block following
				} else {
					$replacement.= 
					'if(!ref($@) && !($@)){ last try__please_put_a_do_block_around_me }
					'; # now otherwise block following
				}
				if (defined $otherwiseblock) {
					$replacement.= '
					my $__ExceptionFilterTmp= $@; eval { $@= $__ExceptionFilterTmp;'."\n".
					$otherwiseblock .'
					};';
				}
				$replacement.= '}'; # end of try__please_put_a_do_block_around_me block
				if (defined $finallyblock) {
					$replacement.= 
					'my $__ExceptionFilterTmp= $@;'."\n".
					$finallyblock."\n;\n".
					$rethrowlinecode."\n".
					'if (ref $__ExceptionFilterTmp) { rethrow $__ExceptionFilterTmp '.
					'} elsif ($__ExceptionFilterTmp) { $@= $__ExceptionFilterTmp; die;'.
					'}'  # just make one long line since we have to put the #line marker before the if (at least under 5.6.1)
				} else {
					$replacement.= 
					"\n".$rethrowlinecode."\n".
					'if (ref $@) { rethrow $@ } elsif ($@) { die }'
						# just make one long line since we have to put the #line marker before the if (at least under 5.6.1)
				}
				$replacement.= "}\n".lineformat($line,$filename)."\n";

				# replace it
				$endpos= pos($_);
				substr($_,$beginpos,$endpos-$beginpos)= $replacement;
				pos($_)= $beginpos+length($replacement);

				next NEWSTATEMENT; # we already are at the beginning of new statement

			} else {
				print "-- no real try (is only a marker or something) (line $line) --\n" if DEBUG>=2;
			}

		} elsif (/\G(?:re)?throw\b(\s*)([\w:]+)/sgoc) {
			$copy=$1; $line+= $copy=~ tr/\n/\n/;
			push @$checknamespaces, [$line, $2];
			
		} else {
			print "Beginning of statement with unknown construct\n" if DEBUG>=2;
		}

		# (maybe advance over special constructs so they are not interpreted as statement separations)

		# advance until next beginning of statement
		if (/\G(.*?)($OPERATOR|\;|\{|\}|\()/sgoc) {
			print "  Advanced over '$1' till '$2'.\n" if DEBUG>=2;
			$line+= linesin($1);
			next;
		} else {
			#$line+= substr($_,pos($_))=~ tr/\n/\n/;
			if (/\G(.*)/sgoc) {
				$copy=$1; $line+= $copy=~ tr/\n/\n/;
			}
			last;
		}
	}

	if (DEBUG>=2) {
	print "----CODE AFTERWARDS:-------------------\n";
	print "$_\n";
	print "----/CODE AFTERWARDS-------------------\n";
	}

}

FILTER_ONLY
	codecj=> sub {
		$|=1 if DEBUG; # so we can capture stdout+stderr together in a pipe synchronously
		# get line number
		my ($package,$filename,$line)= caller(3); # hmm, I'm dependant now on filter::simple not changing it's calling stack.
		print "CALLER is $package, at $filename line $line\n" if DEBUG>=2;
		$line++;
		
		my $checknamespaces= [];
		my $startline=$line;
		transform(\$_,\$line,$filename,$checknamespaces);
		no strict 'refs';
		push @{"${package}::__ExceptionFilterCHECK"}, $checknamespaces;
		substr($_,0,0)= 'CHECK { '.__PACKAGE__.'::checknamespaces() } '."\n".lineformat($startline,$filename)."\n";
	}
;

sub checknamespaces {
	return unless $^W;
	my ($package,$filename)= caller;
	no strict 'refs';
	while (my $r= shift @{"${package}::__ExceptionFilterCHECK"}) { # should only be 1
		for (@$r) {
			my ($line,$ns)= @$_;
			if (%{"${ns}::"}) {
				if ($ns->can('throw')) {# would be nice to trap the warning "Can't locate package sss for @Ahd::ISA at ..."
					if ($ns->can('rethrow')) {
						print "'$ns' exists and is ok\n" if DEBUG>=2;
					} else {
						warn __PACKAGE__." warning: package '$ns' is loaded, but misses a rethrow method at $filename line $line\n";
					}
				} else {
					warn __PACKAGE__." warning: package '$ns' is loaded, but misses a throw method at $filename line $line\n";
				}
			} else {
				warn __PACKAGE__." warning: package '$ns' does not exist (not loaded?) at $filename line $line\n";
			}
		}
	}
}

1;

