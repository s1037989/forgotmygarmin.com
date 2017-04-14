package ForgotMyGarmin::Model::Strava;
use Mojo::Base -base;

use Mojo::File 'tempfile';

use Geo::Gpx;
use DateTime;

has [qw/pg ua/];

sub copy_activity {
  my ($self, $source, $destination, $activity_id) = @_;
  my $access_token = $self->pg->db->select('strava', ['access_token'], {id => $source})->hash->{access_token};
  my $activity = $self->ua->get("https://www.strava.com/api/v3/activities/$activity_id" => {Authorization => "Bearer $access_token"})->res->json;
  my $stream = $self->ua->get("https://www.strava.com/api/v3/activities/$activity_id/streams/latlng,time,temp,altitude,distance,moving,grade_smooth" => {Authorization => "Bearer $access_token"})->res->json;
  $access_token = $self->pg->db->select('strava', ['access_token'], {id => $destination})->hash->{access_token};
  my ($latlng) = grep { $_->{type} eq 'latlng' } @$stream;
  my ($distance) = grep { $_->{type} eq 'distance' } @$stream;
  my ($time) = grep { $_->{type} eq 'time' } @$stream;
  my ($altitude) = grep { $_->{type} eq 'altitude' } @$stream;
  my ($temp) = grep { $_->{type} eq 'temp' } @$stream;
  my $t = $activity->{start_date};
  $t =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
  $t = DateTime->new(year => $1, month => $2, day => $3, hour => $4, minute => $5, second => $6, time_zone  => 'UTC')->epoch;
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
  return $self->ua->post('https://www.strava.com/api/v3/uploads' => {Authorization => "Bearer $access_token"} => form => {activity_type => $activity->{type}, data_type => 'gpx', file => {file => "$tempfile"}});
}

1;
