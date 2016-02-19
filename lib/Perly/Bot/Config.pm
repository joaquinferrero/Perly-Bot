use v5.22;
use feature qw(signatures postderef);
no warnings qw(experimental::signatures experimental::postderef);

use utf8;

package Perly::Bot::Config;

use namespace::autoclean;
use Perly::Bot::CommonSetup;
use File::Spec::Functions;

our $VERSION = '1.001';
my $logger = Log::Log4perl->get_logger();


BEGIN {
my $self;

sub new ( $class, $file = catfile( $ENV{HOME}, '.perlybot', 'config' ) ) {
	$logger->debug( "config file is [$file]" );
	return $self if defined $self;

	$self = bless {}, $class;

	$self->load_config( $file );

	$self->init_cache;
	$self->load_media;


	$self;
	}

sub get_config ( $class ) {
	unless( $class->_config_setup ) {
		$logger->logcroak( "Config is not setup! Call new() first" );
		}

	$self;
	}

sub _config_setup ( $class ) { defined $self }
}

sub AUTOLOAD ( $self ) {
	our $AUTOLOAD;

	my( $method ) = $AUTOLOAD =~ m/.+::(.+)/;

	if( exists $self->{$method} ) {
		return $self->{$method};
		}
	else {
		$logger->warn( "$method is not configured" );
		return;
		}
	}

sub get_config ( $class ) {
	unless( $class->_config_setup ) {
		$logger->error( "Config is not setup! Call new() first" );
		}

	$class->new;
	}

sub load_config ( $self,
	$file = do { 'config.yml' ? 'config.yml' : "$ENV{HOME}/.perly_bot/config.yml" }
	) {
	$self->{_file} = $file;

	# use canonpath for cross platform support
	my $file_hash = YAML::XS::LoadFile( Path::Tiny->new($file)->canonpath );
	%$self = ( $self->%*, $file_hash->%* );

    $self->{perlybot_home} = $self->perlybot_path
    	// catfile( $ENV{HOME}, '.perly_bot' );
	}

sub init_cache ( $self, $cache_class='Perly::Bot::Cache' ) {
    # init cache
    $logger->logdie( "Cache class <$cache_class> does not look like a valid namespace!" )
    	unless $cache_class =~ / \A [A-Z0-9_]+ ( :: [A-Z0-9_]+ )* \z /xi;
	state $module = do {
		my $rc = eval "require $cache_class; 1";
		if( $@ ) { $logger->warn( "$@" ) }
		$rc;
		};
    $self->{cache} = $cache_class->new(
    	catfile( $self->perlybot_home, $self->{cache}{path} ),
      	$self->{cache}{expiry_secs}
		);
	$self;
	}

sub cache ( $self ) { $self->{cache} }

sub load_media ( $self ) {
	state $module = require YAML::XS;
    foreach my $module_name ( keys $self->media->%* ) {
    	unless( $module_name =~ m/ \A [A-Z0-9_]+ ( :: [A-Z0-9_]+ )+ \z /xi ) {
    		$logger->error( "Invalid namespace [$module_name]!" );
    		next;
    		}

		my $config_path = catfile(
			$self->perlybot_home,
			$self->media->{$module_name}{config_path}
			);

		$self->add_media_object( $module_name, $config_path );
    	}

	return $self;
	}

sub add_media_object ( $self, $module_name, $config_path ) {
	unless( $module_name =~ m/ \A [A-Z0-9_]+ ( :: [A-Z0-9_]+ )+ \z /xi ) {
		$logger->warn( "Invalid namespace [$module_name]!" );
		next;
		}

	unless( eval "require $module_name; 1" ) {
		$logger->error( "Could not load [$module_name]: $@" );
		return;
		}

	my $media_config = YAML::XS::LoadFile($config_path);

	my $object = eval { $module_name->new( $media_config ) };
	unless( ref $object ) {
		$logger->error( "Could not make object for [$module_name]! $@" );
		return;
		}

	$self->{media}{$module_name}{object} = $object;
	}

sub has_media_object ( $self, $module_name ) {
	my $has = eval{ defined $self->media->{$module_name}{object} };
	if( $@ ) {
		$logger->warn( "Could not check for $module_name: $@" );
		}

	return $has;
	}

sub get_media_object ( $self, $module_name ) {
	return eval { $self->media->{$module_name}{object} };
	}

sub get_media_classes ( $self ) {
	return keys $self->media->%*;
	}

sub get_all_media_objects ( $self ) {
	my @objects;
	foreach my $module_name ( $self->get_media_classes ) {
		next unless $self->has_media_object( $module_name );
		push @objects, $self->get_media_object( $module_name );
		}
	\@objects;
	}

sub add_media_type ( $self, $type ) {
	push @{ $self->{media} }, $type;
	}

sub media_config ( $self, $class ) {
	unless( exists $self->{media}{$class}{config} ) {
		$logger->logwarn( "There's no config for media target $class" );
		return;
		}

	my $args = $self->{media}{$class}{config};
	unless( ref $args eq ref {} ) {
		$logger->logwarn( "Data for media target $class isn't a hash ref" );
		return;
		}

	$args;
	}

sub media_targets ( $self ) {
	return $self->{media_targets}->@*;
	}

sub feeds ( $self, $file='feeds.yml' ) {
	state $module =
		require YAML::XS,
		require Perly::Bot::Feed;

	state $config = do {
		YAML::XS::LoadFile( $file // $self->feeds_path );
		};
	state $feeds = [];
	return $feeds if @$feeds;

	foreach my $feed ( $config->@* ) {
		push @$feeds, Perly::Bot::Feed->new( $feed );
		}

	$feeds;
	}

sub agent_string ( $self ) {
	$self->{agent_string} . $VERSION;
	}

sub	age_threshold_secs ( $self ) {
	$self->{should_emit}{age_threshold_secs}
	}
