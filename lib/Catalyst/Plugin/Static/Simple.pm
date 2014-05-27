package Catalyst::Plugin::Static::Simple;
use Moose::Role;
use namespace::autoclean;

use Plack::App::File;
use Catalyst::Utils;

use Catalyst::Plugin::Static::Simple::Middleware;

our $VERSION = '0.32';

before setup_finalize => sub {
    my $app = shift;

    my $config
        = $app->config->{'Plugin::Static::Simple'}
        = $app->config->{'static'}
        = Catalyst::Utils::merge_hashes(
            $app->config->{'Plugin::Static::Simple'} || {},
            $app->config->{static} || {}
        );

    $config->{dirs} ||= [];
    $config->{include_path} ||= [ $app->config->{root} ];
    $config->{ignore_extensions} ||= [ qw/tmpl tt tt2 html xhtml/ ];
    $config->{ignore_dirs} ||= [];
    $config->{debug} ||= $app->debug;

    my $static_middleware = Catalyst::Plugin::Static::Simple::Middleware->new({
        config          => $config,
        cat_app         => ref($app) || $app,
        content_type    => $app->_build_content_type_callback,
    });

    $app->setup_middleware( $static_middleware );
};

sub _build_content_type_callback {
    my ( $c ) = @_;

    my $config = $c->config->{'Plugin::Static::Simple'};
    return sub {
        my $full_path = shift;
        my $mime_type;

        if ( $config->{mime_types} && $full_path =~ /.*\.(\S{1,})$/xms ) {
            $mime_type = $config->{mime_types}->{ $1 };
        }

        return $mime_type || Plack::MIME->mime_type($full_path) || 'text/plain';
    }
}

sub serve_static_file {
    my ( $c, $full_path ) = @_;

    my $res;

    if(! -f $full_path ) {
        $res = Catalyst::Plugin::Static::Simple::Middleware->return_404;
    } else {
        my $file_app = Plack::App::File->new( {
            file            => $full_path,
            content_type    => $c->_build_content_type_callback
        } );
        $res = $file_app->call($c->req->env);
    }

    $c->res->from_psgi_response($res);
}

1;

__END__

=head1 NAME

Catalyst::Plugin::Static::Simple - Make serving static pages painless.

=head1 SYNOPSIS

    package MyApp;
    use Catalyst qw/ Static::Simple /;
    MyApp->setup;
    # that's it; static content is automatically served by Catalyst
    # from the application's root directory, though you can configure
    # things or bypass Catalyst entirely in a production environment
    #
    # one caveat: the files must be served from an absolute path
    # (i.e. /images/foo.png)

=head1 DESCRIPTION

The Static::Simple plugin is designed to make serving static content in
your application during development quick and easy, without requiring a
single line of code from you.

This plugin detects static files by looking at the file extension in the
URL (such as B<.css> or B<.png> or B<.js>). The plugin uses the
lightweight L<MIME::Types> module to map file extensions to
IANA-registered MIME types, and will serve your static files with the
correct MIME type directly to the browser, without being processed
through Catalyst.

Note that actions mapped to paths using periods (.) will still operate
properly.

If the plugin can not find the file, the request is dispatched to your
application instead. This means you are responsible for generating a
C<404> error if your applicaton can not process the request:

   # handled by static::simple, not dispatched to your application
   /images/exists.png

   # static::simple will not find the file and let your application
   # handle the request. You are responsible for generating a file
   # or returning a 404 error
   /images/does_not_exist.png

Though Static::Simple is designed to work out-of-the-box, you can tweak
the operation by adding various configuration options. In a production
environment, you will probably want to use your webserver to deliver
static content; for an example see L<USING WITH APACHE>, below.

=head1 DEFAULT BEHAVIOUR

By default, Static::Simple will deliver all files having extensions
(that is, bits of text following a period (C<.>)), I<except> files
having the extensions C<tmpl>, C<tt>, C<tt2>, C<html>, and
C<xhtml>. These files, and all files without extensions, will be
processed through Catalyst. If L<MIME::Types> doesn't recognize an
extension, it will be served as C<text/plain>.

To restate: files having the extensions C<tmpl>, C<tt>, C<tt2>, C<html>,
and C<xhtml> I<will not> be served statically by default, they will be
processed by Catalyst. Thus if you want to use C<.html> files from
within a Catalyst app as static files, you need to change the
configuration of Static::Simple. Note also that files having any other
extension I<will> be served statically, so if you're using any other
extension for template files, you should also change the configuration.

Logging of static files is turned off by default.

=head1 ADVANCED CONFIGURATION

Configuration is completely optional and is specified within
C<MyApp-E<gt>config-E<gt>{Plugin::Static::Simple}>.  If you use any of these options,
this module will probably feel less "simple" to you!

=head2 Enabling request logging

Since Catalyst 5.50, logging of static requests is turned off by
default; static requests tend to clutter the log output and rarely
reveal anything useful. However, if you want to enable logging of static
requests, you can do so by setting
C<MyApp-E<gt>config-E<gt>{Plugin::Static::Simple}-E<gt>{logging}> to 1.

=head2 Forcing directories into static mode

Define a list of top-level directories beneath your 'root' directory
that should always be served in static mode.  Regular expressions may be
specified using C<qr//>.

    MyApp->config(
        'Plugin::Static::Simple' => {
            dirs => [
                'static',
                qr/^(images|css)/,
            ],
        }
    );

=head2 Including additional directories

You may specify a list of directories in which to search for your static
files. The directories will be searched in order and will return the
first file found. Note that your root directory is B<not> automatically
added to the search path when you specify an C<include_path>. You should
use C<MyApp-E<gt>config-E<gt>{root}> to add it.

    MyApp->config(
        'Plugin::Static::Simple' => {
            include_path => [
                '/path/to/overlay',
                \&incpath_generator,
                MyApp->config->{root},
            ],
        },
    );

With the above setting, a request for the file C</images/logo.jpg> will search
for the following files, returning the first one found:

    /path/to/overlay/images/logo.jpg
    /dynamic/path/images/logo.jpg
    /your/app/home/root/images/logo.jpg

The include path can contain a subroutine reference to dynamically return a
list of available directories.  This method will receive the C<$c> object as a
parameter and should return a reference to a list of directories.  Errors can
be reported using C<die()>.  This method will be called every time a file is
requested that appears to be a static file (i.e. it has an extension).

For example:

    sub incpath_generator {
        my $c = shift;

        if ( $c->session->{customer_dir} ) {
            return [ $c->session->{customer_dir} ];
        } else {
            die "No customer dir defined.";
        }
    }

=head2 Ignoring certain types of files

There are some file types you may not wish to serve as static files.
Most important in this category are your raw template files.  By
default, files with the extensions C<tmpl>, C<tt>, C<tt2>, C<html>, and
C<xhtml> will be ignored by Static::Simple in the interest of security.
If you wish to define your own extensions to ignore, use the
C<ignore_extensions> option:

    MyApp->config(
        'Plugin::Static::Simple' => {
            ignore_extensions => [ qw/html asp php/ ],
        },
    );

=head2 Ignoring entire directories

To prevent an entire directory from being served statically, you can use
the C<ignore_dirs> option.  This option contains a list of relative
directory paths to ignore.  If using C<include_path>, the path will be
checked against every included path.

    MyApp->config(
        'Plugin::Static::Simple' => {
            ignore_dirs => [ qw/tmpl css/ ],
        },
    );

For example, if combined with the above C<include_path> setting, this
C<ignore_dirs> value will ignore the following directories if they exist:

    /path/to/overlay/tmpl
    /path/to/overlay/css
    /dynamic/path/tmpl
    /dynamic/path/css
    /your/app/home/root/tmpl
    /your/app/home/root/css

=head2 Custom MIME types

To override or add to the default MIME types set by the L<MIME::Types>
module, you may enter your own extension to MIME type mapping.

    MyApp->config(
        'Plugin::Static::Simple' => {
            mime_types => {
                jpg => 'image/jpg',
                png => 'image/png',
            },
        },
    );

=head2 Controlling caching with Expires header

The files served by Static::Simple will have a Last-Modified header set,
which allows some browsers to cache them for a while. However if you want
to explicitly set an Expires header, such as to allow proxies to cache your
static content, then you can do so by setting the "expires" config option.

The value indicates the number of seconds after access time to allow caching.
So a value of zero really means "don't cache at all", and any higher values
will keep the file around for that long.

    MyApp->config(
        'Plugin::Static::Simple' => {
            expires => 3600, # Caching allowed for one hour.
        },
    );

=head2 Compatibility with other plugins

Since version 0.12, Static::Simple plays nice with other plugins.  It no
longer short-circuits the C<prepare_action> stage as it was causing too
many compatibility issues with other plugins.

=head2 Debugging information

Enable additional debugging information printed in the Catalyst log.  This
is automatically enabled when running Catalyst in -Debug mode.

    MyApp->config(
        'Plugin::Static::Simple' => {
            debug => 1,
        },
    );

=head1 USING WITH APACHE

While Static::Simple will work just fine serving files through Catalyst
in mod_perl, for increased performance you may wish to have Apache
handle the serving of your static files directly. To do this, simply use
a dedicated directory for your static files and configure an Apache
Location block for that directory  This approach is recommended for
production installations.

    <Location /myapp/static>
        SetHandler default-handler
    </Location>

Using this approach Apache will bypass any handling of these directories
through Catalyst. You can leave Static::Simple as part of your
application, and it will continue to function on a development server,
or using Catalyst's built-in server.

In practice, your Catalyst application is probably (i.e. should be)
structured in the recommended way (i.e., that generated by bootstrapping
the application with the C<catalyst.pl> script, with a main directory
under which is a C<lib/> directory for module files and a C<root/>
directory for templates and static files). Thus, unless you break up
this structure when deploying your app by moving the static files to a
different location in your filesystem, you will need to use an Alias
directive in Apache to point to the right place. You will then need to
add a Directory block to give permission for Apache to serve these
files. The final configuration will look something like this:

    Alias /myapp/static /filesystem/path/to/MyApp/root/static
    <Directory /filesystem/path/to/MyApp/root/static>
        allow from all
    </Directory>
    <Location /myapp/static>
        SetHandler default-handler
    </Location>

If you are running in a VirtualHost, you can just set the DocumentRoot
location to the location of your root directory; see
L<Catalyst::Engine::Apache2::MP20>.

=head1 PUBLIC METHODS

=head2 serve_static_file $file_path

Will serve the file located in $file_path statically. This is useful when
you need to  autogenerate them if they don't exist, or they are stored in a model.

    package MyApp::Controller::User;

    sub curr_user_thumb : PathPart("my_thumbnail.png") {
        my ( $self, $c ) = @_;
        my $file_path = $c->user->picture_thumbnail_path;
        $c->serve_static_file($file_path);
    }

=head1 INTERNAL EXTENDED METHODS

Static::Simple extends the following steps in the Catalyst process.

=head2 prepare_action

C<prepare_action> is used to first check if the request path is a static
file.  If so, we skip all other C<prepare_action> steps to improve
performance.

=head2 dispatch

C<dispatch> takes the file found during C<prepare_action> and writes it
to the output.

=head2 finalize

C<finalize> serves up final header information and displays any log
messages.

=head2 setup

C<setup> initializes all default values.

=head1 SEE ALSO

L<Catalyst>, L<Catalyst::Plugin::Static>,
L<http://www.iana.org/assignments/media-types/>

=head1 AUTHOR

Andy Grundman, <andy@hybridized.org>

=head1 CONTRIBUTORS

Marcus Ramberg, <mramberg@cpan.org>

Jesse Sheidlower, <jester@panix.com>

Guillermo Roditi, <groditi@cpan.org>

Florian Ragwitz, <rafl@debian.org>

Tomas Doran, <bobtfish@bobtfish.net>

Justin Wheeler (dnm)

Matt S Trout, <mst@shadowcat.co.uk>

Toby Corkindale, <tjc@wintrmute.net>

Graeme Lawton <cpan@per.ly>

Mark Ellis <markellis@cpan.org>

=head1 THANKS

The authors of Catalyst::Plugin::Static:

    Sebastian Riedel
    Christian Hansen
    Marcus Ramberg

For the include_path code from Template Toolkit:

    Andy Wardley

=head1 COPYRIGHT

Copyright (c) 2005 - 2011
the Catalyst::Plugin::Static::Simple L</AUTHOR> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
