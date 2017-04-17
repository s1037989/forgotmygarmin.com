-- 1 up
create table strava (id text primary key, access_token text, firstname text, lastname text, email text, profile_url text);

-- 1 down
drop table strava;

-- 2 up
create table push (id text, friend text); # id (source) can push to friend (destination)
create table pull (id text, friend text); # friend (destination) can pull from id (source)

-- 2 down
drop table push;
drop table pull;
