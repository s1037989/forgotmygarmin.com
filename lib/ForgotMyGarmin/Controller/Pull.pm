package ForgotMyGarmin::Controller::Pull;
use Mojo::Base 'Mojolicious::Controller';

sub under {
  my $self = shift;
  return 1 if $self->session('id');
  $self->redirect_to('index');
  return undef;
}

sub listfriends {
  my $self = shift;
  $self->render(athletes => $self->strava->listfriends);
}

sub listactivities {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('pull', ['id'], {friend => $self->param('source'), id => $self->session('id')})->hash;
  $self->render_later;
  my $access_token = $self->pg->db->select('strava', ['access_token'], {id => $self->param('source')})->hash->{access_token};
  $self->delay(
    sub {
      my $delay = shift;
      $self->ua->get('https://www.strava.com/api/v3/athlete/activities' => {Authorization => "Bearer $access_token"} => $delay->begin);
    },
    sub {
      my ($delay, $activities) = @_;
      $self->render(activities => $activities->res->json);
    }
  );
}

sub pullactivity {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('pull', ['id'], {friend => $self->param('source'), id => $self->session('id')})->hash;
  $self->minion->enqueue(copy_activity => [$self->param('source'), $self->session('id'), $self->every_param('activity')]);
  $self->flash(message => 'Pulling activities')->redirect_to('pull_listfriends');
}

1;
