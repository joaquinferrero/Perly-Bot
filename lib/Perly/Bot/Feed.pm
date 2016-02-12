use v5.22;
use feature qw(signatures postderef);
no warnings qw(experimental::signatures experimental::postderef);

package Perly::Bot::Feed;
use utf8;

use namespace::autoclean;
use Carp;
use Log::Log4perl;

use Perly::Bot::Feed::Post;
use Time::Piece;
use XML::FeedPP;

use base 'Class::Accessor';
Perly::Bot::Feed->mk_accessors(
  qw/url type date_name date_format active proxy media delay_seconds twitter/);


my $logger = Log::Log4perl->get_logger();

=encoding utf8

=head1 NAME

Perly::Bot::Feed - represent a feed

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 get_posts ($xml)

This method requires an xml string of the blog feed and returns an
arrayref of L<Perl::Bot::Feed::Blog> objects.

=cut

sub type_defaults ( $self ) {
  state $type_defaults = {
    rdf => {
      date_name   => 'dc:date',
      date_format => '%Y-%m-%dT%T%z',
      parser      => 'XML::FeedPP::RDF',
      },
    rss => {
      date_name   => 'pubDate',
      date_format => '%a, %d %b %Y %T %z',
      parser      => 'XML::FeedPP::RSS',
      },
    atom => {
      date_name   => 'published',
      date_format => '%Y-%m-%dT%TZ',
      parser      => 'XML::FeedPP::Atom',
      },
    };

  return $type_defaults;
  }

sub defaults_for_type ( $self, $type='rss' ) {
  state $type_defaults = $self->type_defaults;

  unless( exists $type_defaults->{$type} ) {
    carp "No defaults for media type [$type]!";
    return;
    }

  return $self->type_defaults->{$type}
  }

sub defaults ( $class ) {
  state $defaults = {
    active => 1,
    proxy  => 0,
    media  =>
      [ 'Perly::Bot::Media::Twitter', 'Perly::Bot::Media::Reddit' ],
    delay_seconds => 21600,
    };

  $defaults;
  }

sub new ( $class, $args )
{
  my %feed = ( $class->defaults->%*, $args->%* );
  my $self = bless \%feed, $class;

  unless ( defined $self->{type} )
  {
    $self->{type} = 'rss';
    $logger->debug(
      "Config for $self->{url} did not specify a source type. Assuming RSS");
  }


  while( my( $k, $v ) = each $self->defaults_for_type( $self->{type} )->%* )
  {
    next if defined $self->{$k};
    $self->{$k} = $v;
  }

  state $required = [
    qw(url type date_name date_format active media proxy delay_seconds parser)];
  my @missing = grep { ! exists $self->{ $_ } } $required->@*;
  $logger->logcroak("Missing fields (@missing) for feed $self->{url}")
    if @missing;

  $logger->logcroak("Unallowed content parser $self->{parser}")
    unless $self->parser_allowed( $self->{parser} );

  $self;
}

sub parser_allowed ( $self, $parser )
{
  return exists $self->_allowed_parsers->{$parser}
}

sub _allowed_parsers
{
  state $allowed = {
    map { $_ => 1 }
      qw(
      XML::FeedPP::RSS
      XML::FeedPP::RDF
      XML::FeedPP::Atom
      ) };
  $allowed;
}

sub get_posts
{
  my ( $self, $xml ) = @_;

  $logger->logcroak('Error get_posts() requires an $xml argument') unless $xml;

  my @posts = ();

  my @items = $self->{parser}->new( $xml, -type => 'string' )->get_item();
  foreach my $i (@items)
  {
    # extract the post date
    my $datetime_raw   = $i->get( $self->date_name );
    my $date_format    = $self->date_format;
    my $datetime_clean = $datetime_raw;

    # time::piece does not recognise UTC as a time zone
    $datetime_clean =~ s/UTC/GMT/ if $date_format =~ /\%Z/;

    # time::piece requires timezone modifiers to not have a semicolon
    $datetime_clean =~ s/([+\-][0-9][0-9]):([0-9][0-9]$)/$1$2/
      if $date_format =~ /\%z/;

    # time::piece struggles with milliseconds
    if ( $self->date_format =~ /%ms/ )
    {
      $datetime_clean =~ s/\.[0-9][0-9][0-9]//;
      $date_format =~
        s/\%ms//;    # %ms is a Perly bot convention not used by strptime
    }

    # save some useful debugging info, datetimes are weird
    if ( $logger->is_debug )
    {
      $logger->debug( sprintf 'Parsing %s changed to %s using format %s',
        $datetime_raw, $datetime_clean, $date_format );
    }

    my $post = eval {
      my $datetime = Time::Piece->strptime( $datetime_clean, $date_format );
      Perly::Bot::Feed::Post->new( {
        delay_seconds => $self->delay_seconds,
        description   => $i->description,
        datetime      => $datetime,
        title         => $i->title,
        url           => $i->link,
        proxy         => $self->proxy,
        twitter       => $self->twitter,
      } );
    };

    if ($@)
    {
      $logger->warn("Error creating post object: $@");
    }
    else
    {
      push @posts, $post;
    }
  }
  return \@posts;
}

=head1 TO DO

=head1 SEE ALSO

=head1 SOURCE AVAILABILITY

This source is part of a GitHub project.

  https://github.com/dnmfarrell/Perly-Bot

=head1 AUTHOR

David Farrell C<< <dfarrell@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015, David Farrell C<< <dfarrell@cpan.org> >>. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
