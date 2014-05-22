#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::More tests => 5;
use Catalyst::Test 'TestApp';

# test defined static dirs
TestApp->config->{'Plugin::Static::Simple'}->{dirs} = [
    'always-static',
];

TestApp->config->{'Plugin::Static::Simple'}->{debug} = 1;

local our $MESSAGES;
{
    close(STDERR);
    open(STDERR, ">>", \$MESSAGES);
}


# a missing file in a defined static dir will return 404 and text/html
ok( my $res = request('http://localhost/always-static/404.txt'), 'request ok' );
is( $res->code, 404, '404 ok' );
is( $res->content_type, 'text/html', '404 is text/html' );
ok(defined $MESSAGES, 'debug message set');
like( $MESSAGES, qr/404/, 'debug message contains 404');

