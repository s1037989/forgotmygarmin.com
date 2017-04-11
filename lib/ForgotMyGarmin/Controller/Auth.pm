package ForgotMyGarmin::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller';

# This action will render a template
sub connect {
  my $self = shift;

  return $self->render('index') if $self->param('error');
  $self->render_later;
  $self->delay(
    sub {
      my $delay = shift;
      my $args = {redirect_uri => $self->url_for('connect')->userinfo(undef)->to_abs};
      $self->oauth2->get_token(strava => $args, $delay->begin);
    },
    sub {
      my ($delay, $err, $data) = @_;
      return $self->render("connect", error => $err) unless $data->{access_token};
      $delay->data(access_token => $data->{access_token});
      $self->ua->get('https://www.strava.com/api/v3/athlete' => {Authorization => "Bearer $data->{access_token}"} => $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $json = $tx->result->json;
      if ( $json->{id} ) {
        $self->session(id => $json->{id});
        if ( $self->pg->db->select('strava', ['id'], {id => $json->{id}})->hash ) {
          $self->pg->db->update('strava', {access_token => $delay->data->{access_token}, firstname => $json->{firstname}, lastname => $json->{lastname}, email => $json->{email}}, {id => $json->{id}});
        } else {
          $self->pg->db->insert('strava', {id => $json->{id}, access_token => $delay->data->{access_token}, firstname => $json->{firstname}, lastname => $json->{lastname}, email => $json->{email}});
        }
      }
      return $self->redirect_to('index');
    },
  );
}

sub logout { shift->session(expires => 1)->redirect_to('index') }

1;
