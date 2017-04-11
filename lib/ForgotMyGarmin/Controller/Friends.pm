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
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash->{id};
    next if $self->pg->db->select('pull', ['id'], {id => $self->session('id'), friend => $friend})->hash;
    $self->pg->db->insert('pull', {id => $self->session('id'), friend => $friend}) if $friend;
  }
  foreach ( split /[,\s]+/, $self->param('grant_push') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash->{id};
    next if $self->pg->db->select('push', ['id'], {id => $self->session('id'), friend => $friend})->hash;
    $self->pg->db->insert('push', {id => $self->session('id'), friend => $friend}) if $friend;
  }
  foreach ( split /[,\s]+/, $self->param('revoke_pull') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash->{id};
    next unless $self->pg->db->select('pull', ['id'], {id => $self->session('id'), friend => $friend})->hash;
    $self->pg->db->delete('pull', {id => $self->session('id'), friend => $friend});
  }
  foreach ( split /[,\s]+/, $self->param('revoke_push') ) {
    my $friend = $self->pg->db->select('strava', ['id'], {email => $_})->hash->{id};
    next unless $self->pg->db->select('push', ['id'], {id => $self->session('id'), friend => $friend})->hash;
    $self->pg->db->delete('push', {id => $self->session('id'), friend => $friend});
  }
  #$self->minion->enqueue(request_pull => [$self->session('id'), $self->param('request_pull')]);
  #$self->minion->enqueue(request_push => [$self->session('id'), $self->param('request_push')]);
  $self->redirect_to('friends');
}

1;
