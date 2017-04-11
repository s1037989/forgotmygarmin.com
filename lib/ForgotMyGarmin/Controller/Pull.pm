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
  $self->render(athletes => $self->pg->db->query('select strava.* from pull left join strava using(id) where pull.friend = ?', $self->session('id'))->hashes);
}

sub listactivities {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('pull', ['id'], {id => $self->param('destination'), friend => $self->session('id')})->hash;
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

sub pullactivity {
  my $self = shift;
  return $self->reply->not_found unless $self->pg->db->select('pull', ['id'], {id => $self->param('destination'), friend => $self->session('id')})->hash;
  $self->render_later;
  $self->delay(
    sub {
      my $delay = shift;
      my $activity = $self->param('activity');
      my $access_token = $self->pg->db->select('strava', ['access_token'], {id => $self->session('id')})->hash->{access_token};
      $self->ua->get("https://www.strava.com/api/v3/activities/$activity" => {Authorization => "Bearer $access_token"} => $delay->begin);
      $self->ua->get("https://www.strava.com/api/v3/activities/$activity/streams/latlng,time,temp,altitude,distance,moving,grade_smooth" => {Authorization => "Bearer $access_token"} => $delay->begin);
    },
    sub {
      my ($delay, $activity, $stream) = @_;
      $activity = $activity->res->json;
      $stream = $stream->res->json;
      my $access_token = $self->pg->db->select('strava', ['access_token'], {id => $self->param('destination')})->hash->{access_token};
      my ($latlng) = grep { $_->{type} eq 'latlng' } @$stream;
      my ($distance) = grep { $_->{type} eq 'distance' } @$stream;
      my ($time) = grep { $_->{type} eq 'time' } @$stream;
      my ($altitude) = grep { $_->{type} eq 'altitude' } @$stream;
      my ($temp) = grep { $_->{type} eq 'temp' } @$stream;
      my $t = $activity->{start_date_local};
      $t =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
      $t = DateTime->new(year => $1, month => $2, day => $3, hour => $4, minute => $5, second => $6)->epoch;
      my $gpx = Geo::Gpx->new;
      $gpx->time($t);
      $gpx->name($activity->{name});
      my $tracks = [];
      for ( 0 .. $#{$latlng->{data}}-1 ) {
        push @{$tracks->[0]->{segments}->[0]->{points}}, {
          lat => $latlng->{data}->[$_]->[0],
          lon => $latlng->{data}->[$_]->[1],
          time => $t + $time->{data}->[$_],
          ele => $altitude->{data}->[$_],
        };
      }
      $gpx->tracks($tracks);
      my $tempfile = tempfile;
      $tempfile->spurt($gpx->xml('1.0'));
      $self->ua->post('https://www.strava.com/api/v3/uploads' => {Authorization => "Bearer $access_token"} => form => {data_type => 'gpx', file => {file => "$tempfile"}} => $delay->begin);
    },
    sub {
      my ($delay, $upload) = @_;
      $self->redirect_to('index');
      #$self->redirect_to($self->url_for('pushdestination', destination => $self->param('destination')));
    },
  );
}

1;
