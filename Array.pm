package Class::Array;

# Mon Jul 23 16:31:09 2001  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the same terms as perl itself (i.e. Artistic license/GPL)
#
# $Id: Array.pm,v 1.19 2002/04/24 16:37:57 chris Exp $


$VERSION = '0.04pre14';

use strict;
use Carp;

#use constant DEBUG=>0;
sub DEBUG () {$ENV{CLASS_ARRAY_DEBUG}||0};

#use enum qw(PUBLIC PROTECTED PRIVATE);
sub PUBLIC () {0}; sub PROTECTED () {1}; sub PRIVATE () {2}; # enum is not in the base perl 5.005 dist

sub import {
	my $class=shift;
	my $calling_class;
	
	# sort out arguments:
	my (@normal_import, @only_fields, @newpublicfields, @newprotectedfields, @newprivatefields);
	my $publicity= PROTECTED; # default behaviour!
	my $namehash;
	my ($flag_fields, $flag_extend, $flag_onlyfields, $flag_base, $flag_nowarn, $flag_namehash,
		$flag_caller);#hmm it really starts to cry for a $i or shift approach.
	for (@_) {
		if ($flag_base) {
			$flag_base=0;
			$class= $_;
		} elsif ($flag_namehash) {
			$flag_namehash=0;
			$namehash= $_;
		} elsif ($flag_caller) {
			$flag_caller=0;
			$calling_class= $_;
		} elsif ($_ eq '-caller') {
			croak "Multiple occurrence of -caller argument" if defined $calling_class;
			$flag_caller=1;
		} elsif ($_ eq '-nowarn') {
			$flag_nowarn=1;
		} elsif ($_ eq '-fields' or $_ eq '-members') {
			$flag_fields=1;
		} elsif ($_ eq '-extend') {
			$flag_extend=1;
		} elsif ($_ eq '-public') {
			if ($flag_extend || $flag_fields) {
				$publicity=PUBLIC;
			} else {
				croak __PACKAGE__.": missing -extend or -fields option before -public";
			}
		} elsif ($_ eq '-shared'|| $_ eq '-protected') {
			if ($flag_extend || $flag_fields) {
				$publicity=PROTECTED;
			} else {
				croak __PACKAGE__.": missing -extend or -fields option before -protected";
			}
		} elsif ($_ eq '-private') {
			if ($flag_extend || $flag_fields) {
				$publicity=PRIVATE;
			} else {
				croak __PACKAGE__.": missing -extend or -fields option before -private";
			}
		} elsif ($_ eq '-onlyfields' or $_ eq '-onlymembers') {
			if ($flag_extend || $flag_fields) {
				croak __PACKAGE__.": -onlyfields option not allowed after -extend or -fields";
			} else {
				$flag_onlyfields=1;
			}
		} elsif ($_ eq '-class') {
			if (defined $flag_base) {
				croak __PACKAGE__.": only one -class option possible";
			} else {
				$flag_base=1;
			}
			$flag_base=1;
		} elsif ($_ eq '-namehash') {
			$flag_namehash=1; ## wieso dieser hack?, warum nicht nächstes argument clobbern? Hmm.
		} elsif (/^-/) {
			croak __PACKAGE__.": don't understand option `$_'";
		} else {
			if ($flag_fields || $flag_extend) {
				if ($publicity == PUBLIC) {
					push @newpublicfields,$_;
				} elsif ($publicity == PROTECTED) {
					push @newprotectedfields,$_;
				} else {
					push @newprivatefields,$_;
				}
			} elsif ($flag_onlyfields) {
				push @only_fields, $_;
			} else {
				push @normal_import, $_;
			}
		}
	}
	
	croak "Missing argument to '-caller'" if $flag_caller;
	unless (defined $calling_class) {
		$calling_class= caller;
		croak "Won't import class '$class' into itself (use the -caller option to specify the export target)" if $class eq $calling_class;
	}
	warn "importing '$class' to '$calling_class'" if DEBUG;
	
	#if ($flag_namehash && ! $namehash) {
	#	croak __PACKAGE__.": missing argument to -namehash option";
	#} els
	# nein, es soll undef erlaubt sein für den Fall von fields/inherit, dann einfach kein alias kreieren?
	# çç
	if ($flag_fields && defined $flag_base) {
		croak __PACKAGE__.": you can't give both -fields and -class options";
	} elsif ($flag_fields && $flag_extend) {
		croak __PACKAGE__.": you can't give both -fields and -extend options";
	} elsif ($flag_fields and $flag_onlyfields) {
		croak __PACKAGE__.": you can't give both -fields and -onlyfields options";
	} elsif ($flag_fields) {  # set up $calling_class as base class
		my $counter=0; ##PS. könnte bei 1 anfangen und ins arrayelement 0 was anderes stopfen...
		create_fields_and_bless_class ($calling_class, $counter, \@newpublicfields, \@newprotectedfields, \@newprivatefields, $class);
		if ($namehash) {
			$calling_class->class_array_namehash($namehash,1,$calling_class,1);
		}

	} elsif ($flag_extend) {  # Inherit a class
		no strict 'refs';
		my $counter= ${"${class}::_CLASS_ARRAY_COUNTER"};
		unless (defined $counter) {
			if ($class eq __PACKAGE__) {
				croak __PACKAGE__.": please use the '-fields' argument instead of '-extend' for deriving from the Class::Array base class";
				# (Hmm, does it really make sense?, should we just drop the '-fields' arg in favour of -extend in all cases?)
			} else {
				croak __PACKAGE__.": class $class doesn't seem to be a Class::Array type class";
			}
		}
		create_fields_and_bless_class ($calling_class, $counter, \@newpublicfields, \@newprotectedfields, \@newprivatefields, $class);
		if (#$class ne __PACKAGE__) {
				defined ${"${class}::_CLASS_ARRAY_COUNTER"}) {
			alias_fields ($class, $calling_class, $flag_onlyfields ? { map { $_=> 1 } @only_fields } : undef, 
				$flag_nowarn, !$flag_fields);
		}
		if ($namehash) {
			$calling_class->class_array_namehash($namehash,1,$calling_class,1);
		}

	} else {  # 'normal' use of a class without inheriting it.
		croak "$class is of no use without defining fields on top of it" unless defined ${"${class}::_CLASS_ARRAY_COUNTER"}; # don't simply test '$class eq __PACKAGE__' since this would stop one to extent Class::Array itself.
		alias_fields ($class, $calling_class, $flag_onlyfields ? { map { $_=> 1 } @only_fields } : undef, 
			$flag_nowarn, 0);
		if ($namehash) { # create (if needed) and import name lookup hash (and cache it)
			$class->class_array_namehash($namehash,0,$calling_class,1);
		}
	}
	
	# 'normal' export mechanism
	for (@normal_import) {
		transport ([$_],$class,$calling_class, $flag_nowarn);
	}
}


sub alias_fields {
	my ($class, $calling_class, $only_fields, $flag_nowarn, $flag_inherit) =@_;
	no strict 'refs';
	if (defined *{"${class}::_CLASS_ARRAY_PUBLIC_FIELDS"}{ARRAY}) {
		for (@{"${class}::_CLASS_ARRAY_PUBLIC_FIELDS"}, ($flag_inherit ? @{"${class}::_CLASS_ARRAY_PROTECTED_FIELDS"}: ()) ) { 
			if (!$only_fields or $only_fields->{$_}) {
				if (defined *{"${calling_class}::$_"}{CODE}) {
					if (*{"${calling_class}::$_"}{CODE} == *{"${class}::$_"}{CODE}) {
						warn "${calling_class}::$_ exists already but is the same as ${class}::$_" if DEBUG;
					} else {
						carp __PACKAGE__.": conflicting name `$_': ignoring and also removing existing entry (all of \*$_ !)" unless $flag_nowarn;
						#delete *{"${calling_class}::$_"}{CODE}; ## geht nicht, muss undef?:
						#undef *{"${calling_class}::$_"}{CODE}; ## geht auch nicht, Can't modify glob elem in undef operator
						#*{"${calling_class}::$_"}= undef; ## ist doch wüst weil es auch alle andern löscht.
						#*{"${calling_class}::$_"}= *Class::Array::nonexistant{CODE}; ist genaudasselbe.
						#*{"${calling_class}::$_"}= sub { print "SCheisse\n" };  #"
						delete ${"${calling_class}::"}{$_}; #"  OK! Works, but deletes all glob fields, not only CODE. Does anybody know how to do this correctly? In Perl?, in a C extension?
					}
				} else {
					*{"${calling_class}::$_"}= *{"${class}::$_"}{CODE};
				}
			}
		}
		my $isaref= *{"${class}::ISA"}{ARRAY};
		if ($isaref and @$isaref == 1) {
			alias_fields ( ${$isaref}[0], $calling_class, $only_fields, $flag_nowarn, $flag_inherit);
		} else {
			croak __PACKAGE__.": Error: class $class is set up as Class::Array type class, but doesn't have a valid \@ISA (multiple inheritance is not supported for Class::Array!)";
		}
	} # else something is strange, isn't it? ##
}	

#use Carp 'cluck';

sub class_array_namehash { ##replaces create_name_lookup_hash
# Aufruf a) von neuem class, um eigene UND obenstehende reinzukriegen.  b) von outer, um nur public von der class zu kriegen.
# Maybe we should also take optional $hashname and $cachehash arguments and put the hash HERE into the CLASS_ARRAY_NAMEHASH var and do aliases
	my $class=shift;
#cluck "DEBUG namehash" if DEBUG;
	my ($hashname, $flag_inherit, $calling_class, $flag_cachehash, $incomplete_hashref) =@_; # flag_inherit sagt quasi "ich bin n member und will die protected von oberhalb und meine eigenen protected + private sehen."
	$calling_class= caller unless defined $calling_class;
	$flag_inherit= $calling_class->isa($class) unless defined $flag_inherit; ##korrekt?
warn "flag_inherit=$flag_inherit, calling_class=$calling_class, class=$class" if DEBUG;
	no strict 'refs';
	my $hashref;
	# check if not already cached:
	if ($hashref= do {
		if ($flag_inherit) {
			*{"${calling_class}::CLASS_ARRAY_NAMEHASH"}{HASH}
		} else {
			*{"${class}::_CLASS_ARRAY_NAMEHASHFOREXTERNALUSE"}{HASH}
		}
	}) {
		# already done
		warn "Using cached namehash for '$class'" if DEBUG;
	} else {
		# need to create it
		$hashref= $incomplete_hashref ? $incomplete_hashref : {};
		my $superclass= do {
			my $isaref= *{"${class}::ISA"}{ARRAY};
			if ($isaref and @$isaref == 1) {
				$isaref->[0]
			} else {
				croak __PACKAGE__.": Error: class $class doesn't have a valid \@ISA (multiple inheritance is not supported for Class::Array!)";
			}
		};
		if (defined ${"${superclass}::_CLASS_ARRAY_COUNTER"}) {
warn "DEBUG: going to call $superclass->class_array_namehash(undef, $flag_inherit, $calling_class, 0, \$hashref) where hash has ".(keys %$hashref)." keys" if DEBUG;
			$superclass->class_array_namehash(undef, $flag_inherit, $calling_class, 0, $hashref); ## eigentlich würd ein flag anstelle calling_class ja reichen.
warn "DEBUG: now hash has ".(keys %$hashref)." keys" if DEBUG;
		}
		for (@{"${class}::_CLASS_ARRAY_PUBLIC_FIELDS"}, 
			($flag_inherit ? @{"${class}::_CLASS_ARRAY_PROTECTED_FIELDS"}: ()),
			(($flag_inherit and $calling_class eq $class) ? @{"${class}::_CLASS_ARRAY_PRIVATE_FIELDS"}: ())
		) { 
			if (exists $hashref->{$_}) {	
				die "???????FEHLER DUPLIKAT KEY für '$_' in '$class'";##
			}
			$hashref->{$_}= eval "${class}::$_";
		}
		# save it?
		if ($hashname && $hashname ne '1' or $flag_cachehash) {
			if ($flag_inherit) {
				*{"${calling_class}::CLASS_ARRAY_NAMEHASH"}= $hashref;
warn "DEBUG: saved namehash as ${calling_class}::CLASS_ARRAY_NAMEHASH" if DEBUG;
			} else {
				*{"${class}::_CLASS_ARRAY_NAMEHASHFOREXTERNALUSE"}= $hashref;
warn "DEBUG: saved namehash as ${class}::_CLASS_ARRAY_NAMEHASHFOREXTERNALUSE" if DEBUG;
			}
		} 
	}
	# create alias for it?
	if ($hashname and $hashname ne '1' and (!$flag_inherit or $hashname ne 'CLASS_ARRAY_NAMEHASH')) {
		*{"${calling_class}::$hashname"}= $hashref;
	}
	$hashref
}

sub class_array_indices {
	my $class=shift;
	my $hash= $class->class_array_namehash(undef,undef,caller); # is is required to get caller already here!, it would be Class::Array otherwise
#use Data::Dumper;
#warn "class_array_indices bekam ".Dumper($hash);
	map { exists $hash->{$_} ? $hash->{$_} : confess "class_array_indices: '$_': no such field (known in your namespace)" } @_;
}

sub transport {
	my ($items, $class, $calling_class, $flag_nowarn)=@_;
	no strict 'refs';
	for (@$items) {
		if (/^\$(.*)/) { # scalar
			if (defined *{"${class}::$1"}{SCALAR}) { ## DOES IN FACT ALWAYS RETURN TRUE!
				if (defined *{"${calling_class}::$1"}{SCALAR}) { ## DOES IN FACT ALWAYS RETURN TRUE!
					if (*{"${calling_class}::$1"}{SCALAR} == *{"${class}::$1"}{SCALAR}) {
						carp __PACKAGE__.": symbol `$_' already imported" if DEBUG;
					} else {
						carp __PACKAGE__.": conflicting name `$_' - ignoring" unless $flag_nowarn;
					}
				} else {
					*{"${calling_class}::$1"}= *{"${class}::$1"}{SCALAR};
				}
			} else {
				croak __PACKAGE__.": can't export \$${class}::$1 since it doesn't exist";
			}
		} elsif (/^\@(.*)/) { # array
			if (defined *{"${class}::$1"}{ARRAY}) {
				if (defined *{"${calling_class}::$1"}{ARRAY}) { 
					if (*{"${calling_class}::$1"}{ARRAY} == *{"${class}::$1"}{ARRAY}) {
						carp __PACKAGE__.": symbol `$_' already imported" if DEBUG;
					} else {
						carp __PACKAGE__.": conflicting name `$_' - ignoring" unless $flag_nowarn;
					}
				} else {
					*{"${calling_class}::$1"}= *{"${class}::$1"}{ARRAY};
				}
			} else {
				croak __PACKAGE__.": can't export \@${class}::$1 since it doesn't exist";
			}
		} elsif (/^\%(.*)/) { # hash
			if (defined *{"${class}::$1"}{HASH}) {
				if (defined *{"${calling_class}::$1"}{HASH}) {
					if (*{"${calling_class}::$1"}{HASH} == *{"${class}::$1"}{HASH}) {
						carp __PACKAGE__.": symbol `$_' already imported" if DEBUG;
					} else {
						carp __PACKAGE__.": conflicting name `$_' - ignoring" unless $flag_nowarn;
					}
				} else {
					*{"${calling_class}::$1"}= *{"${class}::$1"}{HASH};
				}
			} else {
				croak __PACKAGE__.": can't export \%${class}::$1 since it doesn't exist";
			}
		} else { # subroutine/constant
			if (defined *{"${class}::$_"}{CODE}) {
				if (defined *{"${calling_class}::$_"}{CODE}) {
					if (*{"${calling_class}::$_"}{CODE} == *{"${class}::$_"}{CODE}) {
						carp __PACKAGE__.": symbol `$_' already imported" if DEBUG;
					} else {
						carp __PACKAGE__.": conflicting name `$_' - ignoring" unless $flag_nowarn;
					}
				} else {
					*{"${calling_class}::$_"}= *{"${class}::$_"}{CODE};    #"
				}
			} else {
				croak __PACKAGE__.": can't export ${class}::$_ since it doesn't exist";
			}
		}
	}
}
#use Carp 'cluck';
# sub create_name_lookup_hash { # only call this if needed since it's slow; only call if sure that the given class is Class::Array based.
# 	my $class=shift;
# #cluck "DEBUG: create_name_lookup_hash for class '$class'";
# 	my $superclass;
# 	no strict 'refs';
# 	for (@{"${class}::ISA"}) {
# 		if (defined ${"${_}::_CLASS_ARRAY_COUNTER"}) { # ok it's the class::array based class
# 			$superclass=$_;
# 
# 			# copy lookup hash from super class
# 			unless (*{"${superclass}::CLASS_ARRAY_NAMEHASH"}{HASH}) {
# 				$superclass->create_name_lookup_hash;
# 			}
# 			%{"${class}::CLASS_ARRAY_NAMEHASH"}= %{"${superclass}::CLASS_ARRAY_NAMEHASH"};
# 
# 			last;# for
# 		}
# 	} # else there is no superclass. (Except ("hopefully") Class::Array itself)
# 	
# 	# Put members from this class into the hash
# 	for (@{"${class}::_CLASS_ARRAY_PUBLIC_FIELDS"}, @{"${class}::_CLASS_ARRAY_PROTECTED_FIELDS"}, @{"${class}::_CLASS_ARRAY_PRIVATE_FIELDS"}) {
# 		${"${class}::CLASS_ARRAY_NAMEHASH"}{$_}= eval "${class}::$_";
# 	}
# }

sub create_fields_and_bless_class {
	my ($calling_class, $counter, $newpublicfields, $newprotectedfields, $newprivatefields, $class)=@_;
	no strict 'refs';
# 	if ($namehash and $class ne __PACKAGE__) { # last compare is needed (for -fields creation step) to stop from creating stuff in Class::Array itself
# ##ç				defined ${"${class}::_CLASS_ARRAY_COUNTER"}) {
# ##der scheiss ist   aber eigtl sollt ichs doch von oben von params her kriegen?
# 		# copy nameindex from inherited class.
# 		unless (*{"${class}::CLASS_ARRAY_NAMEHASH"}{HASH}) {
# 			$class->create_name_lookup_hash;
# 		}
# 		%{"${calling_class}::CLASS_ARRAY_NAMEHASH"}= %{"${class}::CLASS_ARRAY_NAMEHASH"};
# 	}
	for (@$newpublicfields, @$newprotectedfields, @$newprivatefields) {
		if (defined *{"${calling_class}::$_"}{CODE}) { # coderef exists
			croak __PACKAGE__.": conflicting name `$_': can't create initial member constant";
		} else {
			my $scalar= $counter++;
			*{"${calling_class}::$_"}= sub () { $scalar };
			# The following isn't any better. It's accelerated in both cases (perl5.00503). In both cases the constants are valid during global destruction. The following doesn't work if $_ eq 'ç' or some such.
			#eval "sub ${calling_class}::$_ () { $scalar }"; ## somewhat dangerous, maybe we should check vars
			#warn "Class::Array: $@ (`$_')" if $@;
# 			if ($namehash) {
# 				${"${calling_class}::CLASS_ARRAY_NAMEHASH"}{$_}=$scalar;
# 			}
		}
	}
	*{"${calling_class}::_CLASS_ARRAY_PUBLIC_FIELDS"}= $newpublicfields;
	*{"${calling_class}::_CLASS_ARRAY_PROTECTED_FIELDS"}= $newprotectedfields;
	*{"${calling_class}::_CLASS_ARRAY_PRIVATE_FIELDS"}= $newprivatefields; # required for creating name lookup hashes and the like.
	*{"${calling_class}::_CLASS_ARRAY_COUNTER"}= \$counter;
	*{"${calling_class}::ISA"}= [$class];  
}


# default constructor:
sub new {
	my $class=shift;
	bless [], $class;
}

# default destructor: (this is needed so subclasses can call ->SUPER::DESTROY regardless whether there is one or not)
sub DESTROY {
}

1;
__END__

=head1 NAME

Class::Array - array based perl objects

=head1 SYNOPSIS

 package My::BaseClass;
 use strict;
 use Class::Array -fields=> -public=> qw(Name Firstname),
                            -protected=> qw(Age),
                            -private=> qw(Secret);

 # Method example
 sub age {
     my $self=shift;
     if (@_) {
         my $val=shift;
         if ($val>=18) {
             $self->[Age]=$val;
         } else {
             carp "not old enough";
             $self->[Secret]=$val;
         }
     } else {
         $self->[Age]
     }
 }
 ----
 package My::DerivedClass;
 use strict;
 use My::BaseClass -extend=> -public=> qw(Nickname),
                             -private=> qw(Fiancee);

 # The best way to generate an object, if you want to 
 # initialize your objects but let parent classes 
 # initialize them too:
 sub new {
     my $class=shift;
     my $self= $class->SUPER::new;
        # Class::Array::new will catch the above if 
        # no one else does
     # do initialization stuff of your own here
     $self
 }

 sub DESTROY {
     my $self=shift;
     # do some cleanup here
     $self->SUPER::DESTROY; 
        # can be called without worries, 
        # Class::Array provides an empty default DESTROY method.
 }
 
 ----
 # package main:
 use strict;
 use My::DerivedClass;
 my $v= new My::DerivedClass;
 $v->[Name]= "Bla";
 $v->age(19);
 $v->[Age]=20; # gives a compile time error since `Age' 
               # does not exist here


=head1 DESCRIPTION

So you don't like objects based on hashes, since all you can do to  prevent
mistakes while accessing object data is to create accessor methods which are
slow and inconvenient (and you don't want to use depreciated  pseudohashes
either) - what's left? Some say, use constants and  array based objects. Of
course it's a mess since the constants and the objects aren't coupled, and
what about inheritance? Class::Array tries to help you with that.

Array based classes give the possibility to access data fields of your
objects directly without the need of slow (and inconvenient) wrapper methods
but still with some protection against typos and overstepping borders of
privacy.

=head1 USAGE

Usage is somewhat similar to importing from non-object oriented modules. `use
Class::Array', as well as `use ' of any Class::Array derived class,  takes a
number of arguments. These declare which parent class you intend to use, and
which object fields you want to create. See below for an explanation of all
options. Option arguments begin with a minus `-'

Arguments listed I<before the first option> are interpreted as symbol names
to be imported into your namespace directly (apart from the field names).
This is handy to import constants and `L<enum|enum>'s. (Note that unlike the
usual L<Exporter|Exporter>, the one from Class::Array doesn't look at the
@EXPORT* variables yet. Drop me a note if you would like to have that.)

=over 4

=item -fields => I<list>

This option is needed to set up an initial Class::Array based class (i.e. not
extend an existing class). The following arguments are the names of the object
fields in this class. (For compatibility reasons with older versions of this
module, `-members' is an alias for -fields.)

=item -extend => I<list>

This is used to inherit from an existing class. The following names are
created in addition to the member names inherited from the parent class.

=item -public | -protected | -private => I<list>

These options may be used anywhere after the -fields and -extend options to
define the scope of the subsequent names. They can be used multiple times.
Public means, the member will be accessible from anywhere your class is
`use'd.
Protected means, the member will only be accessible from the class itself as
well as from derived classes (but not from other places your class is used). 
Private means, the member will only be accessible inside the class which has
defined it. (For compatibility reasons with older versions there is also a
`-shared' option which is the same as protected.)

Note that you could always access all array elements
by numeric index, and you could also fully qualify the member name
constant in question. The member name is merely not put `before your nose'.

The default is protected.

=item -onlyfields I<list>

Optional. List the fields you want to use after this option. If not given,
all (public) member names are imported. Use this if you have name conflicts
(see also the IMPORTANT section). (`-onlymembers' is an alias for -onlyfields.)

=item -nowarn

If you have a name conflict, and you don't like being warned all the time,
you can use this option (instead of explicitely listing all non-conflicting
names with -onlyfields).

=item -class => 'Some::Baseclass'

In order to make it possible to define classes independant from module files
(i.e. package Some::Baseclass is not located in a file .../Some/Baseclass.pm)
you can inherit from such classes by using the -class option. Instead of `use
Some::Baseclass ...'  you would type `use Class::Array
-class=>"Some::Baseclass", ...'.

=item -namehash => 'hashname'

By default, there is no way to convert field name strings into the 
correspondent array index except to use eval ".." to interpret the string 
as a constant. If you need fast string-to-index lookups, use this option
to get a hash with the given name into your namespace that has the field
name strings as keys and the array index as value.

Use this only if needed since it takes some time to create the hash.

Note that the hash only has the fields that are accessible to you.

You could use the reverse of the hash to get the field names for an index,
i.e. for debugging.

There's also a C<class_array_namehash> class method with which you can create the hash 
(or get the cached copy of it) at a later time:

 class->class_array_namehash( [ aliasname [, some more args ]] )

This returns a reference to the hash. Depending on whether you are in a
class inheriting from 'class' or not, or whether you *are* the 'class' or not,
you will get a hash containing protected (and your private) fields or not.
If 'aliasname' is given, the hash is imported into your namespace with that name.

To get a list of indices for a list of field names, there is also a method:

 class->class_array_indices( list of fieldnames )

This will croak if a field doesn't exist or is not visible to you.

=back


=head1 IMPORTANT

1.) Be aware that object member names are defined as constants (like in the
`L<constant|constant>' module/pragma) that are independant from the actual
object. So there are two sources of mistakes: 

=over 4

=item * Use of member names that are also used as subroutine names, perl
builtins, or as member names of another array based class you use in the same
package (namespace). When a particular name is already used in your namespace
and you call `use' on a Class::Array  based class, Class::Array will detect
this, warn you and either die (if it's about a member name you're about to
newly create), or both not import the member name into your namespace and
also *remove* the existant entry, so you can't accidentally use the wrong
one. You can still access the field by fully qualifying it's constant name,
i.e. $v->[My::SomeClass::Name] (note that this way you could also access
private fields). Use the -onlyfields or -nowarn options if you don't like the
warning messages.

=item * Using the member constants from another class than the one the object
belongs to. I.e. if you have two classes, `My::House' and `My::Person', perl
and Class::Array won't warn you if you accidentally type $me->[Pissoire]
instead of $me->[Memoire]. 

=back


2.) The `use Class::Array' or `use My::ArraybasedClass' lines should always
be the *LAST*  ones importing something from another module. Only this way
name conflicts can be detected by Class::Array. But there is one important
exception to this rule: use of other Class::Array based modules should be
even *later*. This is to resolve circularities: if there are two array
bases modules named A and B, and both use each other, they will have to
create their field names before they can be imported by the other one.
To rephrase: always put your "use" lines in this order: 1. other, not
Class::Array based modules, 2. our own definition, 3. other Class::Array
based modules.

3.) Remember that Class::Array relies on the module import mechanism and
thus on it's `import' method. So either don't define subroutines called
`import' in your modules, or call SUPER::import from there after having
stripped the arguments meant for your own import functionality, and 
specify -caller=> scalar caller() as additional arguments.

4.) (Of course) remember to never `use enum' or `use constant' to define your
field names. (`use enum' is fine however for creating *values* you
store in your object's fields.)

5.) Don't forget to `use strict' or perl won't check your field names!

=head1 TIPS

=over 4

=item * To avoid name conflicts, always use member names starting with an
uppercase letter (and the remaining part in mixed case, so to distinguish
from other constants), and use lowercase names for your methods / subs.
Define fields private, if you don't need them to be accessible outside 
your class.

=back

=head1 BUGS

Scalars can't be checked for conflicts/existence. This is due to a strange
inconsistency in perl (5.00503 as well as 5.6.1). This will probably
not have much impact. (Note that constants are not SCALARs but CODE
entries in the symbol table.)

=head1 CAVEATS

Class::Array only supports single inheritance. I think there's no way to
implement multiple inheritance with arrays / member name constants. Another
reason not to use multiple inheritance with arrays is that  users can't both
inherit from hash and array based classes, so any class aiming to be
compatible to other classes to allow multiple inheritance  should use the
standard hash based approach.

=head1 NOTE

There is also another helper module for array classes (on CPAN),
L<Class::ArrayObjects|Class::ArrayObjects> by Robin Berjon. I didn't know
about his module at the time I wrote Class::Array. You may want to have a
look at it, too.

=head1 FAQ

(Well it's not yet one but I put this in here before it becomes one:)

=over 4

=item Q: Why does perl complain with 'Bareword "Foo" not allowed' when I have defined Foo as -public in class X and I have a 'use X;' in my class Y?

A: Could it be there is a line 'use Y;' in your X module and you have placed it before defining X's fields?
(See also "IMPORTANT" section.)

=back

=head1 AUTHOR

Christian J. <pflanze@gmx.ch>. Published under the same terms as perl itself.

=head1 SEE ALSO

L<constant>, L<enum>, L<Class::Class>, L<Class::ArrayObjects>

=cut

# NOTE:
# This is written for perl 5.005. (Maybe one could take advantage of
# some perl 5.6 features (is it possible to hide constants with perl5.6?)?)
# It should also work on 5.004x
#'

Wed,  2 Jan 2002 13:20:30 +0100
Idee:
-laxchecking
oder
-allowmerge ..
oder
-acceptsame => ("Id","FileId","ContainerNumber"...)


Frage: hat Class::Array selber auch einen _CLASS_ARRAY_COUNTER ? Nein, glaub nicht.



TODO:
- optimierung dass unterklassen schaun ob oberklassen das Argument bekommen haben und dann gleich 
right away den hash kreieren  fehlt noch. Derzeit führen superklassen stets eval methode durch.

- sollten doch auch private teile rein ?? !!!!!!!!
  aber bei subklassen geht das im Nachhinein ja gar nich mehr?
  Hmmm, muss also private auch in n array schreiben! Weil sons gehts weder mit hash noch array gar nicht in WithDBI.pm.
  

Sat,  9 Mar 2002 18:38:21 +0100

Shit fehler:

die private fields dürfen natürlich nicht in namelookuphash sein der Klasse obendran. Sondern nur im
hash der Klasse selber, wenn überhaupt. D.h. das hashkopieren geht nich so. Halt 3 verschiedene hashes
machen, einer mit allen für Gebrauch in Klasse selber, einer nur mit public für export nach draussen,
und einer mit public und protected für inheritance.

Oder: innerhalb der Klasse immer alle public+protected von superklassen  und die private von selber
drin haben.  Dann für inheritance nich einfach hash kopieren sondern checken ob's ein private ist und 
wenn ja, nicht kopieren.   Für export checken ob public sonst verwerfen. Gleich wie beim Export der Konstanten.
Das führt mich zur Frage ob überhaupt der Export bisher korrekt war?!!! Ob public von superklassen exportiert
wurden oder nicht.
digdig. Hmm doch es wurde rekursiv erledigt. ABER: dafür seh ich keinen Unterschied zwischen export nach aussen
und export für inheritance.!!!
Tatsächlich, protected fields werden auch exportiert. Nur private nicht.
Aha, das war aber nur ein kleiner copypaste bug von mir. War alles schon vorbereitet.
Oky, nun geflickt.

--
Neu: zusammen mit dem alias_fields erledigen. Gleich in das hash stecken.
Oder eben doch separat, dann aber gleiches Prinzip.

----
Thu, 28 Mar 2002 01:03:26 +0100

Bug von cesar gemeldet:
 Person
 Author
 Who
use Who -namehash A
use Author -namehash B
	sei korrekt, aber
use Author -namehash B
use Who -namehash A
	sei falsch, in A sei dann NUR das von Who.

Hmmmm, wieso dies    $superclass->class_array_namehash   auf Zeile 215? Buggybuggybuggybuggybuggy
Soll ich erst Glacé essen gehen oder zuersst das hier fertig machen?
Philipp hat wieder eine lange wartephase.
Und Nadia schreibt mir nicht zurück und fw auch nicht.

Hmmm wie funktionniert das mit dam incomplete_hashref ??
Das ist so dass von oben kommend schon gefüllt?, und dann untenzeugrein?   Oder umgekehrt?
umgekehrt: leer. rauf. rauf. rauf. füllen. zurück. weiterfüllen. zurück. weiterfüllen.
Aber heee scheissbuggyfalsch, ich mach ja gar keine Kopie?? für das caching?

Also das mit dem incomplete kann ich ja vergessen. Muss super holen. ......
