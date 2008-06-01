package Class::Array::XMLException;

# Sat Apr 20 18:34:17 2002  Christian Jaeger, pflanze@gmx.ch
# 
# Copyright 2001 by ethlife renovation project people
# (christian jaeger, cesar keller, philipp suter, peter rohner)
# Published under the terms of the GNU General Public License
#
# $Id: XMLException.pm,v 1.2 2002/04/27 19:03:41 chris Exp $

=head1 NAME

Class::Array::XMLException - exception base class for use with AxKit

=head1 DESCRIPTION

Exceptions based on this class can be handled by AxKit's main_handler routine,
for printing a nice error page to the browser.

This is done by providing a method 'as_errorxml' which is called
by AxKit and which returns an xml string. It calls the 'text' method
to get the exception contents as text.  (I've choosen to call this
method 'as_errorxml' since it uses '<error></error>' as it's root
tag.)

=head1 AUTHOR

Christian Jaeger, pflanze@gmx.ch

=head1 SEE ALSO

L<AxKit>, www.axkit.org

=cut


use strict;

use Class::Array::Exception -extend=> qw(
);

my %escapes = (
        '<' => '&lt;',
        '>' => '&gt;',
        '\'' => '&apos;',
        '&' => '&amp;',
        '"' => '&quot;',
        );

sub xml_escape {
    my $text = shift;
    $text =~ s/([<>'&"])/$escapes{$1}/egsx;
    return $text;
}

sub as_errorxml {
	my $self=shift;
	my ($i,$j)=(1,0);
	'<error><type>'.xml_escape(ref($self)).'</type>'
	.'<file>'.xml_escape($self->[ExceptionFile]) .'</file>'
	.'<line>'.xml_escape($self->[ExceptionLine]) .'</line>'
	.'<msg>' .xml_escape($self->text) . '</msg>'
	.($self->[ExceptionRethrown] && @{$self->[ExceptionRethrown]} ?
		'<rethrown>'
		.join("",
			map { '<bt level="' . $i++ . '">' .			### really use 'bt'?
				'<file>' . xml_escape($_->[1]) . '</file>' .
				'<line>' . xml_escape($_->[2]) . '</line>' .
				'</bt>' } @{$self->[ExceptionRethrown]}
		)
		.'</rethrown>'
		: '')
	.($self->[ExceptionStacktrace] ?
		'<stack_trace>'.
# 		'<bt level="0">'.  is included in stacktrace anyway, so..
# 		'<file>' . xml_escape($self->[ExceptionFile]) . '</file>' .
# 		'<line>' . xml_escape($self->[ExceptionLine]) . '</line>' .
# 		'</bt>'. ($self->[ExceptionRethrown] ? 
		join("",
		map { '<bt level="' . $j++ . '">' .
				'<file>' . xml_escape($_->[0]) . '</file>' .
				'<line>' . xml_escape($_->[1]) . '</line>' .
				'<what>' . xml_escape($_->[2]) . '</what>' .
				'</bt>' } $self->stacktrace_loa
		)
#		 : "")
		.'</stack_trace>'
		: ''
	)
	.'</error>'
}

1;
