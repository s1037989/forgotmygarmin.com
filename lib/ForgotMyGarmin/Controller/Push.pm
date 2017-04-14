package ForgotMyGarmin::Controller::Push;
use Mojo::Base 'Mojolicious::Controller';

use Mojo::File 'tempfile';

use Geo::Gpx;
use DateTime;

sub under {
  my $self = shift;

  return 1 if $self->session('id');
  $self->redirect_to('index');
  return undef;
}

sub listfriends {
  my $self = shift;
  $self->render(athletes => $self->pg->db->query('select strava.* from push left join strava using(id) where push.friend = ?', $self->session('id'))->hashes);
}

sub listactivities {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('push', ['id'], {id => $self->param('destination'), friend => $self->session('id')})->hash;
  $self->render_later;
  my $access_token = $self->pg->db->select('strava', ['access_token'], {id => $self->session('id')})->hash->{access_token};
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

sub pushactivity {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('push', ['id'], {id => $self->param('destination'), friend => $self->session('id')})->hash;
  $self->minion->enqueue(copy_activity => [$self->session('id'), $self->param('destination'), $self->every_param('activity')]);
  $self->flash(message => 'Pushing activities')->redirect_to('push_listfriends');
}

1;
