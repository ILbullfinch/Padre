package Padre::Task::CPAN2;

use 5.008005;
use strict;
use warnings;
use Padre::Task     ();
use Padre::Constant ();
use Padre::Pod2HTML ();
use LWP::UserAgent  ();
use JSON::XS        ();
use Padre::Logger qw(TRACE);

our $VERSION = '0.91';
our @ISA     = 'Padre::Task';

use constant {

	# Task commands
	CPAN_SEARCH   => 'search',
	CPAN_POD      => 'pod',
	CPAN_RECENT   => 'recent',
	CPAN_FAVORITE => 'favorite',

	# Maximum number of MetaCPAN results
	MAX_RESULTS => 20,
};

######################################################################
# Constructor

sub new {
	my $self = shift->SUPER::new(@_);

	# Assert required command parameter
	unless ( defined $self->{command} ) {
		die "Failed to provide a command to the CPAN task\n";
	}

	return $self;
}

######################################################################
# Padre::Task Methods

sub run {
	my $self = shift;

	# Create empty model
	$self->{model} = [];

	# Pull things off the task so we won't need to serialize
	# it back up to the parent Wx thread at the end of the task.
	return unless defined $self->{command};
	my $command = $self->{command};
	return unless defined $self->{query};
	my $query = delete $self->{query};

	if ( $command eq CPAN_SEARCH ) {

		# Autocomplete search using MetaCPAN JSON API
		$self->{model} = $self->metacpan_autocomplete($query);
	} elsif ( $command eq CPAN_POD ) {

		# Find the POD's HTML and SYNOPSIS section
		# using MetaCPAN JSON API
		$self->{model} = $self->metacpan_pod($query);
	} elsif ( $command eq CPAN_RECENT ) {

		# Find MetaCPAN's top recent distributions
		$self->{model} = $self->metacpan_recent;
	} elsif ( $command eq CPAN_FAVORITE ) {

		# Find MetaCPAN's top favorite distributions
		$self->{model} = $self->metacpan_favorite;
	} else {
		TRACE("Unimplemented $command. Please fix!") if DEBUG;
	}

	return 1;
}

#
# Adopted from https://github.com/CPAN-API/metacpan-web
#
sub metacpan_autocomplete {
	my ( $self, $query ) = @_;

	# Convert :: to spaces so we dont crash request :)
	$query =~ s/::/ /g;

	# Create an array of query keywords that are separated by spaces
	my @query = split( /\s+/, $query );

	# The documentation Module-Name that should be analyzed
	my $should = [
		map {
			(   { field => { 'documentation.analyzed'  => "$_*" } },
				{ field => { 'documentation.camelcase' => "$_*" } }
				)
			}
			grep {
			$_
			} @query
	];

	# The distribution we do not want in our search
	my @ROGUE_DISTRIBUTIONS = qw(kurila perl_debug perl-5.005_02+apache1.3.3+modperl pod2texi perlbench spodcxx);

	# The ElasticSearch query in Perl
	my %payload = (
		query => {
			filtered => {
				query => {
					custom_score => {
						query  => { bool => { should => $should } },
						script => "_score - doc['documentation'].stringValue.length()/100"
					},
				},
				filter => {
					and => [
						{   not => {
								filter => {
									or => [ map { { term => { 'file.distribution' => $_ } } } @ROGUE_DISTRIBUTIONS ]
								}
							}
						},
						{ exists => { field          => 'documentation' } },
						{ term   => { 'file.indexed' => \1 } },
						{ term   => { 'file.status'  => 'latest' } },
						{ not    => { filter         => { term => { 'file.authorized' => \0 } } } }
					]
				}
			}
		},
		fields => [qw(documentation release author distribution)],
		size   => MAX_RESULTS,
	);

	# Convert ElasticSearch Perl query to a JSON request
	my $json_request = JSON::XS::encode_json( \%payload );

	# POST the json request to api.metacpan.org
	my $ua = LWP::UserAgent->new( agent => "Padre/$VERSION" );
	$ua->timeout(10);

	$ua->env_proxy unless Padre::Constant::WIN32;
	my $response = $ua->post(
		'http://api.metacpan.org/v0/file/_search',
		Content => $json_request,
	);

	unless ( $response->is_success ) {
		TRACE( sprintf( "Got '%s' from metacpan.org", $response->status_line ) )
			if DEBUG;
		return [];
	}

	# Decode json response then cleverly map it for the average joe :)
	my $data = JSON::XS::decode_json( $response->decoded_content );
	my @results = map { $_->{fields} } @{ $data->{hits}->{hits} || [] };

	# And return its reference
	return \@results;
}

# Load module's POD using MetaCPAN API
# retrieves the SYNOPSIS section from that POD and returns a POD2HTML text
sub metacpan_pod {
	my ( $self, $query ) = @_;

	# Load module's POD using MetaCPAN API
	my $ua = LWP::UserAgent->new( agent => "Padre/$VERSION" );
	$ua->timeout(10);
	$ua->env_proxy unless Padre::Constant::WIN32;
	my $url      = "http://api.metacpan.org/v0/pod/$query?content-type=text/x-pod";
	my $response = $ua->get($url);
	unless ( $response->is_success ) {
		TRACE( sprintf( "Got '%s for %s", $response->status_line, $url ) )
			if DEBUG;
		return {
			html     => '<b>' . sprintf(Wx::gettext(qq{No documentation for '%s'}), $query) . '</b>',
			synopsis => '',
			distro   => $query,
		};
	}

	# The pod text is here
	my $pod = $response->decoded_content;

	# Convert POD to HTML
	my $pod_html = Padre::Pod2HTML->pod2html($pod);

	# Find the SYNOPSIS section
	my ( $synopsis, $section ) = ( '', '' );
	for my $pod_line ( split /^/, $pod ) {
		if ( $pod_line =~ /^=head1\s+(\S+)/ ) {
			$section = $1;
		} elsif ( $section eq 'SYNOPSIS' ) {

			# Add leading-spaces-trimmed line to synopsis
			$pod_line =~ s/^\s+//g;
			$synopsis .= $pod_line;
		}
	}

	return {
		html     => $pod_html,
		synopsis => $synopsis,
		distro   => $query,
		},

}

# Retrieves the most recent CPAN distributions
sub metacpan_recent {
	my $self = shift;

	# Load most recent distributions using MetaCPAN API
	my $ua = LWP::UserAgent->new( agent => "Padre/$VERSION" );
	$ua->timeout(10);
	$ua->env_proxy unless Padre::Constant::WIN32;
	my $url =
		"http://api.metacpan.org/v0/release/?sort=date:desc&size=" . MAX_RESULTS . "&fields=distribution,abstract";
	my $response = $ua->get($url);

	unless ( $response->is_success ) {
		TRACE( sprintf( "Got '%s for %s", $response->status_line, $url ) );
		return;
	}

	# Decode json response then cleverly map it for the average joe :)
	my $data = JSON::XS::decode_json( $response->decoded_content );
	my @results = map { $_->{fields} } @{ $data->{hits}->{hits} || [] };

	# Fix up the results a bit to workaround undefined stuff
	for my $result (@results) {
		$result->{documentation} = '' unless defined $result->{documentation};
		$result->{abstract}      = '' unless defined $result->{abstract};
	}

	return \@results;
}

# Retrieves the most favorite CPAN distributions
sub metacpan_favorite {
	my $self = shift;

	my %payload = (
		"query"  => { "match_all" => {} },
		"facets" => {
			"leaderboard" => {
				"terms" => {
					"field" => "distribution",
					"size"  => MAX_RESULTS,
				},
			},
		},
		size => 0,

	);

	# Convert ElasticSearch Perl query to a JSON request
	my $json_request = JSON::XS::encode_json( \%payload );

	# Load most favorite distributions using MetaCPAN API
	my $ua = LWP::UserAgent->new( agent => "Padre/$VERSION" );
	$ua->timeout(10);
	$ua->env_proxy unless Padre::Constant::WIN32;
	my $response = $ua->post(
		'http://api.metacpan.org/v0/favorite/_search',
		Content => $json_request,
	);

	unless ( $response->is_success ) {
		die( sprintf( "Got '%s' from metacpan.org", $response->status_line ) );
		return [];
	}

	# Decode json response then cleverly map it for the average joe :)
	my $data = JSON::XS::decode_json( $response->decoded_content );
	my @results = map {$_} @{ $data->{facets}->{leaderboard}->{terms} || [] };

	return \@results;
}


1;

# Copyright 2008-2011 The Padre development team as listed in Padre.pm.
# LICENSE
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl 5 itself.