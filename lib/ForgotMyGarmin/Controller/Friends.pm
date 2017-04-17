package ForgotMyGarmin::Controller::Friends;
use Mojo::Base 'Mojolicious::Controller';

sub under {
  my $self = shift;
  return 1 if $self->session('id');
  $self->redirect_to('index');
  return undef;
}

sub update {
  my $self = shift;

  foreach ( split /[,\s]+/, $self->param('grant_pull') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    next if $self->pg->db->select('pull', ['id'], {id => $self->session('id'), friend => $friend->{id}})->hash;
    $self->pg->db->insert('pull', {id => $self->session('id'), friend => $friend->{id}});
  }
  foreach ( split /[,\s]+/, $self->param('grant_push') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    next if $self->pg->db->select('push', ['id'], {id => $self->session('id'), friend => $friend->{id}})->hash;
    $self->pg->db->insert('push', {id => $self->session('id'), friend => $friend->{id}});
  }
  foreach ( split /[,\s]+/, $self->param('revoke_pull') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    next unless $self->pg->db->select('pull', ['id'], {id => $self->session('id'), friend => $friend->{id}})->hash;
    $self->pg->db->delete('pull', {id => $self->session('id'), friend => $friend->{id}});
  }
  foreach ( split /[,\s]+/, $self->param('revoke_push') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    next unless $self->pg->db->select('push', ['id'], {id => $self->session('id'), friend => $friend->{id}})->hash;
    $self->pg->db->delete('push', {id => $self->session('id'), friend => $friend->{id}});
  }
  foreach ( split /[,\s]+/, $self->param('request_pull') ) {
    my $me = $self->pg->db->select('strava', ['email'], {id => $self->session('id')})->hash or next;
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    my $jwt = Mojo::JWT->new(claims => {request => 'pull', id => $friend->{id}, friend => $self->session('id')}, secret => $self->app->secrets->[0])->encode;
    #next unless $self->pg->db->select('pull', ['id'], {id => $friend->{id}, friend => $self->session('id')})->hash;
    #$self->minion->enqueue(request => ['pull', $self->session('id'), $friend->{id}]);
    my $friends_accept = $self->url_for('friends_accept', jwt => $jwt)->to_abs;
    warn $friends_accept;
    $self->app->log->debug($self->sendgrid->mail(to => $_, from => 'no-reply@forgotmygarmin.com', subject => 'Request Pull', html => "Pull access requested by $me->{email}, <a href=\"$friends_accept\">accept</a>?")->send);
  }
  foreach ( split /[,\s]+/, $self->param('request_push') ) {
    my $me = $self->pg->db->select('strava', ['email'], {id => $self->session('id')})->hash or next;
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash or next;
    my $jwt = Mojo::JWT->new(claims => {request => 'push', id => $friend->{id}, friend => $self->session('id')}, secret => $self->app->secrets->[0])->encode;
    #next unless $self->pg->db->select('push', ['id'], {id => $friend->{id}, friend => $self->session('id')})->hash;
    #$self->minion->enqueue(request => ['push', $self->session('id'), $friend->{id}]);
    my $friends_accept = $self->url_for('friends_accept', jwt => $jwt)->to_abs;
    warn $friends_accept;
    $self->app->log->debug($self->sendgrid->mail(to => $_, from => 'no-reply@forgotmygarmin.com', subject => 'Request Push', html => "Push access requested by $me->{email}, <a href=\"$friends_accept\">accept</a>?")->send);
  }
  $self->redirect_to('friends');
}

sub find {
  my $self = shift;
  my $friend = $self->param('friend');
  $self->render(json => $self->pg->db->select('strava', 'id, concat_ws(\' \', firstname, lastname) as name', {-or => [email => $friend, \['lower(concat_ws(\' \', firstname, lastname)) like lower(?)', "%$friend%"]]})->hashes);
}

sub accept {
  my $self = shift;
  warn $self->param('jwt');
  my $claims = Mojo::JWT->new(secret => $self->app->secrets->[0])->decode($self->param('jwt'));
warn Data::Dumper::Dumper($claims);
  if ( $claims->{request} eq 'pull' ) {
    $self->pg->db->insert('pull', {id => $claims->{id}, friend => $claims->{friend}}) unless
      $self->pg->db->select('pull', ['id'], {id => $claims->{id}, friend => $claims->{friend}})->hash;
  }
  if ( $claims->{request} eq 'push' ) {
    $self->pg->db->insert('push', {id => $claims->{id}, friend => $claims->{friend}}) unless
      $self->pg->db->select('push', ['id'], {id => $claims->{id}, friend => $claims->{friend}})->hash;
  }
  $self->flash(message => 'Accepted!')->redirect_to('friends');
}

1;
