-- 1 up
create table strava (id text primary key, access_token text, firstname text, lastname text, email text);

-- 1 down
drop table strava;
