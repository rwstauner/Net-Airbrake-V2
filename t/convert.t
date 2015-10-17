use strict;
use warnings;
use Test::More 0.96;
use Test::MockModule;
use Test::XPath;

my $mod = 'Net::Airbrake::V2';
eval "require $mod" or die $@;

my $xml_root = '/notice';

warn "Net::Airbrake VERSION may not be compatible"
  if Net::Airbrake->VERSION ne '0.02';

sub tags_are {
  my ($tx, $parent, $vals) = @_;
  subtest $parent => sub {
    while( my ($tag, $content) = each %$vals ){
      $tx->is("$xml_root/$parent/$tag", $content, $tag);
    }
  };
}

sub vars_are {
  my ($tx, $parent, $vars) = @_;

  my $count = 0;
  $tx->ok(qq!$xml_root/request/$parent!, sub { ++$count }, $parent);
  is $count, 1, "$parent occurs once";

  subtest $parent => sub {
    while( my ($key, $val) = each %$vars ){
      $tx->is(qq!$xml_root/request/$parent/var[\@key="$key"]!, $val, "$parent var $key");
    }
  };
}

subtest 'notify' => sub {
  my %config = (
    environment_name => 'test',
    base_url => 'https://example.com/net-airbrake-v2/blah',
  );
  my $client = new_ok($mod, [%config]);

  my $mock = Test::MockModule->new('HTTP::Tiny');

  my ($exp_res) = map { { id  => $_, url => "https://example.com/locate/$_" } }
    '9ef134aa-2118-9e28-fc51-cd52ecf75b91';

  my @req;
  $mock->mock(request => sub {
    push @req, [ @_[1,2,3] ];
    return {
      success => 1,
      status  => 200,
      headers => { 'Content-Type' => 'application/xml' },
      content => <<XML,
  <notice>
    <id>$exp_res->{id}</id>
    <url>$exp_res->{url}</url>
  </notice>
XML
    };
  });

  eval { die 'エラー！！' };
  my $res = $client->notify($@, {
    context => {
      url       => 'u',
      component => 'c',
      action    => 'a',
      rootDirectory => '/tmp',
      version       => '1.0',
    },
    params      => { p1 => 'p2' },
    session     => { s1 => 's2' },
    # Test more than one var.
    environment => { e1 => 'e2', x => 'y' },
  });

  ok $res, 'response';
  is $res->{$_}, $exp_res->{$_}, "response $_" for qw( id url );

  is scalar(@req), 1, 'one request';

  is $req[0][0], 'POST', 'http post';
  is $req[0][1], "$config{base_url}/notifier_api/v2/notices", 'base url with v2 suffix';

  is( $req[0][2]->{headers}{ 'Content-Type' }, 'application/xml', 'request content type');

  my $xml = $req[0][2]->{content};
  like $xml, qr/^\Q<?xml version="1.0" encoding="utf-8"?>\E/, 'xml declaration with encoding';

  my $tx = Test::XPath->new(xml => $xml);

  $tx->is("$xml_root/\@version", '2.3', 'notice tag with version attribute');

  tags_are($tx, notifier => {
    name    => $mod,
    version => $mod->VERSION || '',
    url     => "https://metacpan.org/pod/$mod"
  });

  tags_are($tx, error => {
    class   => 'CORE::die', # Net::Airbrake fabricates this.
    message => 'エラー！！',
  });

  $tx->ok("$xml_root/error/backtrace/line[1]", sub {
    my ($bt) = @_;
    $bt->is('./@file',     __FILE__, 'file');
    $bt->like('./@number', qr/\d+/,  'line number');
    $bt->is('./@method',   'N/A',    'function');
  }, 'error backtrace');

  tags_are($tx, request => {
    url       => 'u',
    component => 'c',
    action    => 'a',
  });

  vars_are($tx, 'params',   { 'p1' => 'p2' });
  vars_are($tx, 'session',  { 's1' => 's2' });
  vars_are($tx, 'cgi-data', { 'e1' => 'e2', x => 'y'});

  tags_are($tx, 'server-environment' => {
    'environment-name' => 'test',
    'project-root'     => '/tmp',
    'app-version'      => '1.0',
  });
};

done_testing;
