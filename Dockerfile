FROM ruby:2.6

RUN apt-get update && \
    apt-get install -yy git && \
    apt-get -y -q autoclean && \
    apt-get -y -q autoremove

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY Gemfile /usr/src/app/
RUN bundle install

COPY . /usr/src/app

ADD docker/init /init

ENTRYPOINT ["/init"]

