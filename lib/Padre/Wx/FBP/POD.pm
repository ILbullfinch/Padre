package Padre::Wx::FBP::POD;

## no critic

# This module was generated by Padre::Plugin::FormBuilder::Perl.
# To change this module edit the original .fbp file and regenerate.
# DO NOT MODIFY THIS FILE BY HAND!

use 5.008005;
use utf8;
use strict;
use warnings;
use Padre::Wx ();
use Padre::Wx::Role::Main ();
use Padre::Wx::HtmlWindow ();

our $VERSION = '0.97';
our @ISA     = qw{
	Padre::Wx::Role::Main
	Wx::Frame
};

sub new {
	my $class  = shift;
	my $parent = shift;

	my $self = $class->SUPER::new(
		$parent,
		-1,
		Wx::gettext("POD Viewer"),
		Wx::DefaultPosition,
		[ 500, 300 ],
		Wx::DEFAULT_FRAME_STYLE | Wx::RESIZE_BORDER | Wx::TAB_TRAVERSAL,
	);

	$self->{html} = Padre::Wx::HtmlWindow->new(
		$self,
		-1,
		Wx::DefaultPosition,
		Wx::DefaultSize,
		Wx::HW_SCROLLBAR_AUTO,
	);

	my $gSizer3 = Wx::GridSizer->new( 1, 1, 0, 0 );
	$gSizer3->Add( $self->{html}, 0, Wx::EXPAND, 5 );

	$self->SetSizer($gSizer3);
	$self->Layout;

	return $self;
}

sub html {
	$_[0]->{html};
}

1;

# Copyright 2008-2012 The Padre development team as listed in Padre.pm.
# LICENSE
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl 5 itself.

