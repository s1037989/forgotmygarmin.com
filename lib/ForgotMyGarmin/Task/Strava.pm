package ForgotMyGarmin::Task::Strava;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;

  $app->minion->add_task(copy_activities => sub {
    my ($job, $source, $destination, $activities) = @_;

    my @upload;
    foreach my $activity ( @$activities ) {
      $job->app->log->debug($activity);
      push @upload, $job->app->strava->copy_activity($source, $destination, $activity);
    }
    $job->finish({upload => [@upload]});
  });
}

1;
