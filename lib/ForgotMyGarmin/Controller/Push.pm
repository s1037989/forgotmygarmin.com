package ForgotMyGarmin::Controller::Push;
use Mojo::Base 'Mojolicious::Controller';

use Data::Pager;

sub under {
  my $self = shift;
  return 1 if $self->session('id') || $self->developer;
  $self->redirect_to('index');
  return undef;
}

sub friends {
  my $self = shift;
  return $self->render unless $self->req->is_xhr;
  my ($friends, $pager) = $self->strava->users($self->session('id'), $self->req->query_params->to_hash);
  $_->{link} = $self->url_for('push_activities', {destination => $_->{id}}) foreach @$friends;
  $self->pagination($pager)->render(json => $friends);
}

sub activities {
  my $self = shift;
  return $self->render unless $self->req->is_xhr;
  return $self->reply->not_found unless $self->strava->can_push($self->session('id'), $self->param('destination'));
  my $page = $self->param('page') // 1;
  my $per_page = $self->param('per_page') // 10;
  $self->render_later;

  $self->delay(
    sub {
      my $delay = shift;
      $self->strava->get($self->session('id'), "/athlete/activities?per_page=$per_page&page=$page" => $delay->begin);
    },
    sub {
      my ($delay, $tx) = @_;
      my $activities = $tx->result->json;
      my $pager = Data::Pager->new({current => $tx->req->url->query->param('page'), offset => $tx->req->url->query->param('per_page'), limit => 200});
      foreach ( @$activities ) {
        $_->{elapsed_time} = $self->elapsed_time($_->{elapsed_time});
        $_->{distance} = $self->distance($_->{distance});
      }
      $self->pagination($pager)->render(json => $activities);
    }
  );
}

sub pushactivities {
  my $self = shift;
  return $self->reply->not_found unless $self->strava->can_push($self->session('id'), $self->param('destination'));
  $self->minion->enqueue(copy_activities => [$self->session('id'), $self->param('destination'), $self->every_param('activity')]);
  $self->flash(message => sprintf 'Pushing activities: %s', join ', ', @{$self->every_param('activity')})->redirect_to('push_friends');
}

1;
