use strict;
use warnings;
use lib 't/lib';
use V2Tester;

subtest 'full' => sub {
  my $test = notify({
    config => {
      environment_name => 'test',
      base_url => 'https://example.com/net-airbrake-v2/blah',
    },
    code => sub {
      eval { die 'エラー！！' };
      return shift->notify($@, {
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
    },
  });

  my $tx = $test->{tx};

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

subtest 'minimal' => sub {
  my $test = notify({
    config => {
      environment_name => 'tiny',
      base_url => 'https://example.com/err',
    },
    code => sub {
      shift->notify('Oops');
    },
  });

  my $tx = $test->{tx};

  tags_are($tx, error => {
    class   => 'error', # Net::Airbrake fabricates this.
    message => 'Oops',
  });

  $tx->ok("$xml_root/error/backtrace", 'backtrace required');

  not_present($tx, request => [qw(
    url
    component
    action
    params
    session
    cgi-data
  )]);

  not_present($tx, 'server-environment' => [qw(
    project-root
    app-version
  )]);
};

done_testing;
