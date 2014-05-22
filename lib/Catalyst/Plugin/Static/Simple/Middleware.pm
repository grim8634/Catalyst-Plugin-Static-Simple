package Catalyst::Plugin::Static::Simple::Middleware;
use strict;
use warnings;

use parent qw/Plack::Middleware/;

use Plack::Util::Accessor qw/content_type config cat_app/;
use Plack::App::File;
use Carp;

sub call {
    my ( $self, $env )  = @_;

    #wrap everything in an eval so if something goes wrong the user
    #gets an "internal server error" message, and we get a warning
    #instead of the user getting the warning and us getting nothing
    my $return = eval {
        my ( $res, $c );

        if(! $self->_check_static_simple_path( $env->{PATH_INFO} ) ) {
            return $self->app->($env)
        }

        my @ipaths = @{$self->config->{include_path}};
        while ( my $ipath = shift @ipaths ) {
            my $root;
            if ( ref($ipath) eq 'CODE' ) {
                $c ||= $self->cat_app->prepare(env => $env, response_cb => sub {});
                my $paths = $ipath->( $c );

                unshift @ipaths, @{$paths};
                next;
            } else {
                $root = $ipath;
            }

            if(! -f $root . $env->{PATH_INFO} ) {
                next;
            }

            my $file = Plack::App::File->new( {
                root            => $root,
                content_type    => $self->content_type
            } );
            $res = $file->call($env);

            if( $res && ($res->[0] != 404) ) {
                return $res;
            }
        }

        if(! scalar ( @{$self->config->{dirs}})) {
            $self->_debug( "Forwarding to Catalyst (or other middleware)." );
            return $self->app->($env);
        }

        $self->_debug( "404: file not found: " . $env->{PATH_INFO} );
        return $self->return_404;
    };

    if ( $@ ) {
        carp $@;
        return $self->return_500;
    }

    return $return;
}

sub _check_static_simple_path {
    my ( $self, $path ) = @_;

    for my $ignore_ext ( @{ $self->config->{ignore_extensions} } ) {
        if ( $path =~ /.*\.${ignore_ext}$/ixms ) {
            $self->_debug ( "Ignoring extension `$ignore_ext`" );
            return undef
        }
    }

    for my $ignore ( @{ $self->config->{ignore_dirs} } ) {
        $ignore =~ s{(/|\\)$}{};

        if ( $path =~ /^\/$ignore(\/|\\)/ ) {
            $self->_debug( "Ignoring directory `$ignore`" );
            return undef;
        }
    }

    #we serve everything if it exists and dirs is not set
    #we check if it exists in the middleware, once we've built the include paths
    return 1 if ( !scalar(@{$self->config->{dirs}}) );

    if( $self->_path_matches_dirs($path, $self->config->{dirs}) ) {
        return 1;
    }

    return undef;
}

sub _path_matches_dirs {
    my ( $self, $path, $dirs ) = @_;

    $path =~ s!^/!!; #Remove leading slashes

    foreach my $dir ( @$dirs ) {
        my $re;
        if (ref($dir) eq 'Regexp') {
            $re = $dir;
        } elsif ( $dir =~ m{^qr/}xms ) {
            $re = eval $dir;

            if ($@) {
                die( "Error compiling static dir regex '$dir': $@" );
            }
        } else {
            my $dir_re = quotemeta $dir;
            $dir_re =~ s{/$}{};
            $re = qr{^${dir_re}/};
        }

        if( $path =~ $re ) {
            return 1;
        }
    }

    return undef;
}

sub _debug {
    my ( $self, $msg ) = @_;
    warn "Static::Simple: $msg\n" if $self->config->{debug};
}

sub return_404 {
    #for backcompat we can't use the one in Plack::App::File as it has the content-type of plain
    return [404, ['Content-Type' => 'text/html', 'Content-Length' => 9], ['not found']];
}

sub return_500 {
    return [500, ['Content-Type' => 'text/pain', 'Content-Length' => 9], ['internal server error']];
}

1;