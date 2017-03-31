package ForgotMyGarmin;
use Mojo::Base 'Mojolicious';

use Mojo::Pg;
use Mojo::File 'tempfile';

use Geo::Gpx;
use DateTime;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by "my_app.conf"
  my $config = $self->plugin('Config');

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer') if $config->{perldoc};
  $self->plugin('OAuth2' => $config->{oauth2});

  $self->helper(pg => sub { state $pg = Mojo::Pg->new(shift->config('pg')) });

  $self->sessions->default_expiration(315360000);

  # Migrate to latest version if necessary
  my $path = $self->home->child('migrations', 'forgot_my_garmin.sql');
  $self->app->pg->auto_migrate(1)->migrations->from_file($path);

  # Router
  my $r = $self->routes;

  # Normal route to controller
  #$r->get('/')->to('example#welcome');

$r->get('/')->to(cb => sub {
  my $c = shift;
})->name('index');

$r->get('/logout')->to(cb => sub { shift->session(expires => 1)->redirect_to('index') });

$r->get('/push')->to(cb => sub {
  my $c = shift;
  my $activities;
  $c->render_later;
  $c->render(athletes => $c->pg->db->query('select * from strava where id != ?', $c->session('id'))->hashes);
});

$r->get('/push/:destination')->to(cb => sub {
  my $c = shift;
  $c->render_later;
  my $access_token = $c->pg->db->select('strava', ['access_token'], {id => $c->session('id')})->hash->{access_token};
  $c->delay(
    sub {
      my $delay = shift;
      $c->ua->get('https://www.strava.com/api/v3/athlete/activities' => {Authorization => "Bearer $access_token"} => $delay->begin);
    },
    sub {
      my ($delay, $activities) = @_;
      $c->render(activities => $activities->res->json);
    }
  );
});

$r->get('/push/:destination/:activity')->to(cb => sub {
  my $c = shift;
  $c->render_later;
  $c->delay(
    sub {
      my $delay = shift;
      my $activity = $c->param('activity');
      my $access_token = $c->pg->db->select('strava', ['access_token'], {id => $c->session('id')})->hash->{access_token};
      $c->ua->get("https://www.strava.com/api/v3/activities/$activity" => {Authorization => "Bearer $access_token"} => $delay->begin);
      $c->ua->get("https://www.strava.com/api/v3/activities/$activity/streams/latlng,time,temp,altitude,distance,moving,grade_smooth" => {Authorization => "Bearer $access_token"} => $delay->begin);
    },
    sub {
      my ($delay, $activity, $stream) = @_;
      $activity = $activity->res->json;
      $stream = $stream->res->json;
      my $access_token = $c->pg->db->select('strava', ['access_token'], {id => $c->param('destination')})->hash->{access_token};
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
      $c->ua->post('https://www.strava.com/api/v3/uploads' => {Authorization => "Bearer $access_token"} => form => {data_type => 'gpx', file => {file => "$tempfile"}} => $delay->begin);
    },
    sub {
      my ($delay, $upload) = @_;
      $c->redirect_to('index');
      #$c->redirect_to($c->url_for('pushdestination', destination => $c->param('destination')));
    },
  );
});

$r->get("/connect")->to(cb => sub {
  my $c = shift;
  return $c->render('index') if $c->param('error');
  $c->render_later;
  $c->delay(
    sub {
      my $delay = shift;
      my $args = {redirect_uri => $c->url_for('connect')->userinfo(undef)->to_abs};
      $c->oauth2->get_token(strava => $args, $delay->begin);
    },
    sub {
      my ($delay, $err, $data) = @_;
      return $c->render("connect", error => $err) unless $data->{access_token};
      $delay->data(access_token => $data->{access_token});
      $c->ua->get('https://www.strava.com/api/v3/athlete' => {Authorization => "Bearer $data->{access_token}"} => $delay->begin);
    },
    sub {      
      my ($delay, $tx) = @_;
      my $json = $tx->result->json;
      if ( $json->{id} ) {
        $c->session(id => $json->{id});
        if ( $c->pg->db->select('strava', ['id'], {id => $json->{id}})->hash ) {
          $c->pg->db->update('strava', {access_token => $delay->data->{access_token}, firstname => $json->{firstname}, lastname => $json->{lastname}, email => $json->{email}}, {id => $json->{id}});
        } else {
          $c->pg->db->insert('strava', {id => $json->{id}, access_token => $delay->data->{access_token}, firstname => $json->{firstname}, lastname => $json->{lastname}, email => $json->{email}});
        }
      }
      return $c->redirect_to('index');
    },
  );
});

}

1;
