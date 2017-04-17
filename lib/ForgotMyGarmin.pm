package ForgotMyGarmin;
use Mojo::Base 'Mojolicious';

use Mojo::Pg;
use Mojo::JWT;
use Mojo::File 'tempfile';
use Minion;

use ForgotMyGarmin::Model::Strava;

use POSIX 'strftime';
use SQL::Abstract;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by "my_app.conf"
  my $config = $self->plugin('Config');

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer') if $config->{perldoc};
  $self->plugin('Minion' => {Pg => $config->{pg}});
  $self->plugin('Sendgrid');
  $self->plugin('OAuth2' => $config->{oauth2});

  $self->helper(pg => sub { state $pg = Mojo::Pg->new($config->{pg}) });
  $self->pg->abstract(SQL::Abstract->new(convert => 'lower'));
  $self->helper(strava => sub { my $c = shift; state $strava = ForgotMyGarmin::Model::Strava->new(pg => $c->pg, ua => $c->ua, id => $c->session('id')) });
  $self->helper(auth_url => sub {
    my $c = shift;
    $c->oauth2->auth_url("strava", response_type => 'code', scope => "view_private,write", redirect_uri => $c->url_for('connect')->userinfo(undef)->to_abs);
  });

  $self->helper(elapsed_time => sub { shift; strftime "%T", gmtime shift });
  $self->helper(distance => sub { shift; sprintf "%.2f", shift(@_) * 0.000621371 });
  $self->helper(date => sub { shift; shift });

  $self->plugin('ForgotMyGarmin::Task::Strava');

  $self->sessions->default_expiration(315360000);

  # Migrate to latest version if necessary
  my $path = $self->home->child('migrations', 'forgot_my_garmin.sql');
  $self->app->pg->auto_migrate(1)->migrations->from_file($path);

  # Router
  my $r = $self->routes;

  $r->get('/')->name('index');
  $r->get('/connect')->to('auth#connect');
  $r->get('/logout')->to('auth#logout');

  my $friends = $r->under('/friends')->to('friends#under');
  $r->get('/friends')->to('friends#home')->name('friends_home');
  $r->post('/friends')->to('friends#update')->name('friends_update');
  $r->get('/friends/accept/#jwt')->to('friends#accept')->name('friends_accept');
  $r->get('/friends/find/:friend')->to('friends#find')->name('friends_find');

  my $pull = $r->under('/pull')->to('pull#under');
  $pull->get('/')->to('pull#listfriends')->name('pull_listfriends');
  $pull->get('/:source')->to('pull#listactivities')->name('pull_listactivities');
  $pull->post('/:source')->to('pull#pullactivity')->name('pull_pullactivity');

  my $push = $r->under('/push')->to('push#under');
  $push->get('/')->to('push#listfriends')->name('push_listfriends');
  $push->get('/:destination')->to('push#listactivities')->name('push_listactivities');
  $push->post('/:destination')->to('push#pushactivity')->name('push_pushactivity');
}

1;
