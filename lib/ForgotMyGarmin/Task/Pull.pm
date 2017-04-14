package ForgotMyGarmin::Task::Pull;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::File 'tempfile';

use Geo::Gpx;
use DateTime;

sub register {
  my ($self, $app) = @_;
  $app->minion->add_task(pullactivity => sub {
    my ($job, $sessionid, $source, $activities) = @_;

    my @upload;
    foreach ( @$activities ) {
      $job->app->log->debug($_);
      my $access_token = $job->app->pg->db->select('strava', ['access_token'], {id => $source})->hash->{access_token};
      my $activity = $job->app->ua->get("https://www.strava.com/api/v3/activities/$_" => {Authorization => "Bearer $access_token"})->res->json;
      my $stream = $job->app->ua->get("https://www.strava.com/api/v3/activities/$_/streams/latlng,time,temp,altitude,distance,moving,grade_smooth" => {Authorization => "Bearer $access_token"})->res->json;
      $access_token = $job->app->pg->db->select('strava', ['access_token'], {id => $sessionid})->hash->{access_token};
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
      my $upload = $job->app->ua->post('https://www.strava.com/api/v3/uploads' => {Authorization => "Bearer $access_token"} => form => {activity_type => $activity->{type}, data_type => 'gpx', file => {file => "$tempfile"}});
      push @upload, $upload->res->json;
    }
    $job->finish({upload => [@upload]});
  });
}

1;
