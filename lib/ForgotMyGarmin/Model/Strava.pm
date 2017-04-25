package ForgotMyGarmin::Model::Strava;
use Mojo::Base -base;

use Mojo::Log;
use Mojo::File 'tempfile';

use Geo::Gpx;
use DateTime;
use Data::Pager;

has [qw/pg ua/];

has [qw/id query/];

has log => sub { Mojo::Log->new };

sub name { shift->pg->db->select('strava', 'concat_ws(\' \', firstname, lastname) as name', {id => shift})->hash->{name} }

sub _pagination {
  my ($self, $id, $query, $select) = @_;
  $query->{page} //= 1;
  $query->{per_page} //= 3;
  my @select = my @count = @$select;
  $count[1] = 'count(*)';
  my $count = $self->pg->db->select(@count)->hash->{count};
  my $pager = Data::Pager->new({current => $query->{page}, perpage => 5, offset  => $query->{per_page}, limit => $count}) or return undef;
  $pager->current or return undef;
  my $results = $self->pg->db->select(@select, $pager->offset, $pager->from)->hashes or return undef;
  return $results => $pager;
}

sub access_token {
  my ($self, $id) = @_;
  $self->pg->db->select('strava', ['access_token'], {id => $id})->hash->{access_token};
}
sub can_pull {
  my ($self, $id, $query) = @_;
  return $self->pg->db->select('pull', ['id'], {friend => $query, id => $id})->hash if $query and !ref $query;
  my $where = {"pull.id" => $id, "strava.id" => \"= pull.friend"};
  $where = {%$where, -or => [email => $query->{q}, \['lower(concat_ws(\' \', firstname, lastname)) like lower(?)', "%$query->{q}%"]]} if $query->{q};
  return $self->_pagination($id, $query, ['strava, pull', 'strava.id, profile_url, concat_ws(\' \', firstname, lastname) as name', $where, undef]);
}

sub can_push {
  my ($self, $id, $query) = @_;
  return $self->pg->db->select('push', ['id'], {friend => $id, id => $query})->hash if $query and !ref $query;
  my $where = {friend => $id, "strava.id" => \"= push.id"};
  $where = {%$where, -or => [email => $query->{q}, \['lower(concat_ws(\' \', firstname, lastname)) like lower(?)', "%$query->{q}%"]]} if $query->{q};
  return $self->_pagination($id, $query, ['strava, push', 'strava.id, profile_url, concat_ws(\' \', firstname, lastname) as name', $where, undef]);
}

sub users {
  my ($self, $id, $query) = @_;

  my $where = {-or => [email => $query->{q}, \['lower(concat_ws(\' \', firstname, lastname)) like lower(?)', "%$query->{q}%"]]} if $query->{q};
  return $self->_pagination($id, $query, ['strava', 'id, profile_url, concat_ws(\' \', firstname, lastname) as name', $where, undef]);
}

sub listfriends {
  my $self = shift;
  my $friends;
  if ( my $query = shift ) {
    $friends = $self->pg->db->query('select strava.* from pull left join strava using(id) where pull.friend = ? and lower(concat_ws(\' \', firstname, lastname)) like lower(?) limit 10', $self->id, "%$query%")->hashes
  } else {
    $friends = $self->pg->db->query('select strava.* from pull left join strava using(id) where pull.friend = ? limit 10', $self->id)->hashes
  }
  foreach ( @$friends ) {
    my $id = $_->{id};
    $_->{activities} = $self->get($id, '/athlete/activities' => form => {per_page => 3})->json;
  }
  return $friends;
}

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
  $self->log->debug("Copying activity $activity_id ($source => $destination)");
  my $upload_form = {
    activity_type => $activity->{type},
    name => $activity->{name},
    description => "I forgot my garmin!  I copied this activity from $source using forgotmygarmin.com",
    data_type => 'gpx',
    file => {file => "$tempfile"},
  };
  my $upload_res = $self->ua->post('https://www.strava.com/api/v3/uploads' => {Authorization => "Bearer $access_token"} => form => $upload_form)->result->json;
  return $upload_res if $upload_res->{error};
  #$self->pg->db->insert('uploads', $upload_form);
  return {%$upload_form, %$upload_res};
}

# $ perl script/forgot_my_garmin eval 'app->strava->get(4598390, "/athlete")'
sub get {
  my ($self, $id, $url) = (shift, shift, shift);
  ($id && $url) or return;
  return $self->ua->get($self->_url($id, $url) => @_);
}
sub post {
  my ($self, $id, $url) = (shift, shift, shift);
  ($id && $url) or return;
  return $self->ua->post($self->_url($id, $url) => @_);
}
sub delete {
  my ($self, $id, $url) = (shift, shift, shift);
  ($id && $url) or return;
  return $self->ua->delete($self->_url($id, $url) => @_);
}
sub put {
  my ($self, $id, $url) = (shift, shift, shift);
  ($id && $url) or return;
  return $self->ua->put($self->_url($id, $url) => @_);
}

sub _authorization {
  my $self = shift;
  my $id = shift or return;
  my $data = $self->pg->db->select('strava', ['access_token'], {id => $id})->hash or return;
  return {Authorization => "Bearer $data->{access_token}"};
}

sub _url {
  my $self = shift;
  my $id = shift or return;
  my $url = shift or return;
  return ("https://www.strava.com/api/v3$url" => $self->_authorization($id));
}

1;
