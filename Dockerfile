FROM ruby:2.6-alpine

RUN apk add --no-cache git build-base

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY Gemfile /usr/src/app/
RUN bundle install

COPY . /usr/src/app

ADD docker/init /init

ENTRYPOINT ["/init"]

