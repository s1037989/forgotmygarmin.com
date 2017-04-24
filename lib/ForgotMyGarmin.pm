package ForgotMyGarmin;
use Mojo::Base 'Mojolicious';

use Mojo::Pg;
use Minion;

use ForgotMyGarmin::Model::Strava;

use POSIX 'strftime';
use SQL::Abstract::Limit;

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
  $self->plugin('RemoteAddr');

  $self->helper(pg => sub { state $pg = Mojo::Pg->new($config->{pg}) });
  $self->helper(strava => sub { my $c = shift; state $strava = ForgotMyGarmin::Model::Strava->new(pg => $c->pg, ua => $c->ua) });
  $self->helper(auth_url => sub {
    my $c = shift;
    $c->oauth2->auth_url("strava", response_type => 'code', scope => "view_private,write", redirect_uri => $c->url_for('connect')->userinfo(undef)->to_abs);
  });
  $self->helper(pagination => sub {
    # Mojo::Message used to have this, here's the code
    # https://github.com/kraih/mojo/commit/b5c4de20d3f75b4e17fb583af105963d4fcce184
    # https://github.com/kraih/mojo/commit/fdd6c579b31145bed0f762544c94013f57a3851d 
    my $c = shift;
    my $pager = shift or return $c;
    $c->res->headers->link(join ', ', map { sprintf "<%s>; %s", $c->url_with($c->current_route)->query([page => $pager->$_, per_page => $pager->offset])->to_abs, qq(rel="$_") } grep { $pager->$_ } qw/prev next current start end/);
    return $c;
  });
  # Check whether or not this request is a development request made by the developer (for debugging)
  $self->helper(developer => sub {
    my $c = shift;
    my $ip = $c->app->config('developer_ip') || '';
    $c->app->mode ne 'production' && ($c->session('id') && $c->remote_addr eq $ip) || $c->remote_addr eq '127.0.0.1';
  });

  # Move these to a plugin
  $self->helper(elapsed_time => sub { shift; strftime "%T", gmtime shift }); # convert seconds to hh:mm::ss
  $self->helper(distance => sub { shift; sprintf "%.2f", shift(@_) * 0.000621371 }); # convert meters to miles
  $self->helper(date => sub { shift; shift });

  # Minion tasks
  $self->plugin('ForgotMyGarmin::Task::Strava');

  # Use SQL::Abstract::Limit for using abstract methods, but also being able to supply a LIMIT
  # Also, set queries to be case insensitive
  $self->pg->abstract(SQL::Abstract::Limit->new(convert => 'lower', limit_dialect => 'LimitOffset'));

  $self->sessions->default_expiration(315360000);

  # Migrate to latest version if necessary
  my $path = $self->home->child('migrations', 'forgot_my_garmin.sql');
  $self->app->pg->auto_migrate(1)->migrations->from_file($path);

  # Router
  my $r = $self->routes;

  # Move these conditions to a plugin
  # Add a condition for checking whether or not this request is a development request made by the developer (for debugging)
  $r->add_condition(developer => sub {
    my ($route, $c, $captures) = @_;
    return $c->developer;
  });
  $r->add_condition(is_xhr => sub {
    my ($route, $c, $captures) = @_;
    return $c->req->is_xhr;
  });

  $r->get('/')->name('index');
  $r->get('/connect')->to('auth#connect');
  $r->get('/logout')->to('auth#logout');

  #my $api = $r->under('/api')->over('is_xhr')->to('api#under');
  #my $v1  = $api->under('/v1')->to(controller => 'api1');
  
  # my $r = $self->routes;
  # $r->get('/' => sub { shift->redirect_to('posts') });
  # my $posts = $r->under('/posts');
  # $posts->get('/')->to('posts#index');
  # $posts->get('/create')->to('posts#create')->name('create_post');
  # $posts->post('/')->to('posts#store')->name('store_post');
  # $posts->get('/:id')->to('posts#show')->name('show_post');
  # $posts->get('/:id/edit')->to('posts#edit')->name('edit_post');
  # $posts->put('/:id')->to('posts#update')->name('update_post');
  # $posts->delete('/:id')->to('posts#remove')->name('remove_post');

  my $friends = $r->under('/friends')->to('friends#under');
  $friends->get('/')->to('friends#home')->name('friends_home');
  $friends->post('/')->to('friends#update')->name('friends_update');
  $friends->get('/accept/#jwt')->to('friends#accept')->name('friends_accept');
  $r->get('/friends/find')->to('friends#find')->name('friends_find');

  my $pull = $r->under('/pull')->to('pull#under');
  $pull->get('/')->to('pull#friends')->name('pull_friends');
  $pull->get('/:source')->to('pull#activities')->name('pull_activities');
  $pull->post('/:source')->to('pull#pullactivities')->name('pull_pullactivities');

  my $push = $r->under('/push')->to('push#under');
  $push->get('/')->to('push#listfriends')->name('push_listfriends');
  $push->get('/:destination')->to('push#listactivities')->name('push_listactivities');
  $push->post('/:destination')->to('push#pushactivity')->name('push_pushactivity');

  # Debugging route to allow the developer to assume the role of any user (dangerous!)
	$r->get('/session/:id')->over('developer')->to(cb => sub {
	  my $c = shift;
	  $c->session(original_id => $c->session('id'))->session(id => $c->param('id'))->redirect_to($c->req->headers->referrer || 'index');
	});
}

1;
