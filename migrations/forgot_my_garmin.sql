-- 1 up
create table strava (id text primary key, access_token text, firstname text, lastname text, email text);

-- 1 down
drop table strava;

-- 2 up
create table push (id text, friend text);
create table pull (id text, friend text);

-- 2 down
drop table push;
drop table pull;
