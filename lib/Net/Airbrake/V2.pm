# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package Net::Airbrake::V2;

# ABSTRACT: Airbrake Notifier API V2 Client

use parent 'Net::Airbrake';

use XML::Simple qw(xml_out);

sub new {
  my $class = shift;
  my $self;
  $self = $class->SUPER::new(@_,
    _ua => Net::Airbrake::V2::UserAgent->new(sub { $self }),
  );
  return $self;
}

sub _url {
  my ($self) = @_;
  $self->base_url . '/notifier_api/v2/notices';
}

sub _make_vars {
  my ($self, $vars) = @_;
  return [
    {
      var => [
        map {
          {
            key     => $_,
            content => $vars->{$_},
          }
        } keys %{ $vars || {} }
      ]
    }
  ];
}

sub from_v3 {
  my ($self, $req) = @_;

  my $mod = ref($self) || $self;
  my $api_key = $self->api_key;

  my $notice = {
    notice => {
      version => '2.3',
      'api-key' => [ $api_key ],
      notifier  => [
        {
          name    => [ $mod ],
          version => [ $mod->VERSION ],
          url     => [ "https://metacpan.org/pod/$mod" ],
        },
      ],
      error => [
        map {
          {
            class     => [ $_->{type} ],
            message   => [ $_->{message} ],
            backtrace => {
              line => [
                map {
                  +{
                    number => $_->{line},
                    file   => $_->{file},
                    method => $_->{function},
                  }
                }
                  @{ $_->{backtrace} }
              ]
            }
          }
        }
          @{ $req->{errors} || [] }
      ],
      request => {
        url        => [ $req->{context}{url} ],
        component  => [ $req->{context}{component} ],
        action     => [ $req->{context}{action}    ],
        params     => $self->_make_vars($req->{params}),
        session    => $self->_make_vars($req->{session}),
        'cgi-data' => $self->_make_vars($req->{environment}),
      },
      'server-environment' => {
        'environment-name' => [ $req->{context}{environment} ],
      },
    }
  };

  my $xml = xml_out($notice,
    RootName => undef,
    NoIndent => 1,
    XMLDecl  => q[<?xml version="1.0" encoding="utf-8"?>],
  );

  return $xml;
}

{
  package # no_index
    Net::Airbrake::V2::UserAgent;

  use JSON::MaybeXS qw(encode_json decode_json);
  use XML::Simple qw(xml_in);

  sub new {
    bless { get_client => $_[1], }, $_[0];
  }

  sub client {
    $_[0]->{client} ||= delete($_[0]->{get_client})->();
  }

  sub ua {
    $_[0]->{ua} ||= do {
      my $mod = ref($_[0]->client);
      HTTP::Tiny->new(
        agent   => join('/', $mod, $mod->VERSION || 0),
        timeout => 5,
      );
    };
  }

  sub request {
    my ($self, $method, $url, $req) = @_;
    my $ct = 'Content-Type';

    $req->{content} = $self->client->from_v3( decode_json($req->{content}) );
    $req->{headers}{ $ct } = 'application/xml';

    my $res = $self->ua->request($method, $url, $req);

    # TODO: catch xml parse error.
    # TODO: check content type?

    $res->{content} = encode_json( xml_in($res->{content}) );
    $res->{headers}{ $ct } = 'application/json';

    return $res;
  }
}

1;

=head1 SYNOPSIS

=head1 DESCRIPTION

API Compatible with L<Net::Airbrake> but converts v3 requests to v2 and then converts the response back.

This makes it usable with L<Errbit|https://errbit.github.io/errbit/>.

B<Note>: This is currently based heavily on the internals of L<Net::Airbrake> (as of C<0.02>).
This enables laziness at the cost of fragility.

=head1 SEE ALSO

=for :list
* L<Net::Airbrake>
* L<Airbrake|https://airbrake.io>
* L<Airbrake Notifier API v2|https://help.airbrake.io/kb/api-2/notifier-api-v23>
* L<Errbit|https://errbit.github.io/errbit/>

=cut
