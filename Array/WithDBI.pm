package Class::Array::WithDBI;

# Fri Mar  8 20:53:40 2002  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id: WithDBI.pm,v 1.7 2003/04/11 16:52:47 chris Exp $

=head1 NAME

Class::Array::WithDBI - setting objects from DBI statement handles

=head1 SYNOPSIS

 my $sth;
 use EL::DB sub {
     $sth = $DB->prepare("select  *  from ....");
 };
 # EL::DB is currently part of ETHLife CMS.
 # You could as well just 
 #  my $sth= $dbh->prepare("select  *  from ....");
 # (EL::DB will take care of re-preparing them after re-connects 
 #  i.e. after a fork, though)
 Some::Class:DerivedFrom::WithDBI->create_sthreader("set_by_fileidArticle", $sth);
 
 # now:
 my $obj= new Some::Class:DerivedFrom::WithDBI;
 $sth->execute("some", "params");
 $obj->set_by_fileidArticle;
 # now the fields from $obj are set to the values of the fields
 # with the same name from the query.

=head1 DESCRIPTION

Makes it easier (and faster) to load sql database content into a Class::Array
based object than it would be to do it manually.

=head1 CLASS METHODS

=over 4

=item create_sthreader( method_name, $statementhandle [, values_to_return ])

Creates a new method with the name 'method_name' in the class
on which you call create_sthreader. When called, this method
figures out which column names the query is returning, and maps
their values onto the object's fields of the same name.
It creates a sub that's optimized for just this statement handle,
so it doesn't have to do any lookups or loops during regular use
and so apart from the additional method call calling

 $obj->method_name
 
should be as fast as a manual

 @$obj[A,Few,Field,Names]= $sth->fetchrow_array

and should be much easier to handle.
It returns a list of those column values that don't have a
corresponding object field, in the same order as they appear
in the result set. These fields should be given as values_to_return
arguments, otherwise a warning will be issued.

You could call $obj->method_name multiple times before re-executing
the statement handle if the result
set contains multiple rows (but usually that won't make sense).

=back

=head1 NOTES

If your database tables have different column names than your
objects or if you make a join from multiple tables, it could
be necessary to use name aliasing in the query (like "select
wrongname as CorrectName,...").

Tested only with MySql but should work with all database drivers
that return a correct $sth->{NAME}.

=cut

#'

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
        my $lookuphash= $class->class_array_namehash(undef,undef,scalar caller); 
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
                ##gar nich n�tig: defined ($idx= $lookuphash->{$_}) or $idx= eval "${class}::$_"; die "???: $@" if $@;
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
