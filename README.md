git-sync
========

![Travis](https://img.shields.io/travis/swi-infra/git-sync.svg)
![Score](https://img.shields.io/codeclimate/github/swi-infra/git-sync.svg)
![Coverage](https://img.shields.io/codeclimate/coverage/github/swi-infra/git-sync.svg)
![Issues](https://img.shields.io/codeclimate/issues/github/swi-infra/git-sync.svg)

Synchronize mirror repositories locally from remote sources.
Helpful to maintain a mirror of projects located on various hosts such as GitHub or Gerrit.

Basic
-----

The 'git-sync' script takes a config.yml as a parameter which is formatted like this:

```
global:
    to: '/storage/git'
publishers:
  - type: 'rabbitmq'
    host: 'mirror-host'
    exchange: 'mirror-exchange'
    username: 'guest'
    password: 'guest'
sources:
  - from: 'https://github.com/swi-infra/git-sync'
  - from: 'https://github.com/swi-infra/ruby-git'
    to: '/mnt/external/ruby-git.git'
  - type: 'gerrit'
    host: 'gerrit-host'
    username: 'myuser'
    from: 'git://gerrit-mirror/'
    filters:
      - 'manifest'
      - '/meta.*/'
  - type: 'gerrit-rabbitmq'
    gerrit_host: 'gerrit-host'
    username: 'myuser'
    from: 'git://gerrit-mirror/'
    exchange: 'gerrit.publish'
    filters:
      - 'manifest'
      - '/meta.*/'
```

Sources
-------

#### Single

Default (and simpliest) type. Will synchronize from a Git remote ('from') to some directory ('to').
If a default global 'to' is provided, path will be built using it plus the basename of the Git remote.

```
  - from: 'https://github.com/swi-infra/ruby-git'
    to: '/mnt/external/ruby-git.git'
```

#### Gerrit

Uses Gerrit SSH protocol to list projects and filter the ones to sync using strings or regex (as a string surrounded by '/').
You can optionally specify a mirror using 'from' if you don't want to overload the master.
The optional 'port' is assumed to be 29418 if not specified.

```
  - type: 'gerrit'
    host: 'gerrit-host'
    username: 'myuser'
    from: 'git://gerrit-mirror/'
    filters:
      - 'manifest'
      - '/meta.*/'
```

#### Gerrit-RabbitMQ

Same as Gerrit above, except rabbitmq is used to stream events. The Gerrit SSH protocol is used to
list projects, so `gerrit_host` is still a mandatory parameter (with the optional `gerrit_port`
default to 29418). The rabbitmq host is assumed to be the same as `gerrit_host`, otherwise can be
configured with `rabbitmq_host` (with the optional `rabbitmq_port` default to 5672).
The rabbitmq exchange name is specifed with `exchange` parameter.

```
  - type: 'gerrit-rabbitmq'
    gerrit_host: 'gerrit-host'
    gerrit_username: 'myuser'
    rabbitmq_host: 'other-host'
    rabbitmq_username: 'guest'
    rabbitmq_password: 'guest'
    exchange: 'gerrit.publish'
    from: 'git://gerrit-mirror/'
    filters:
      - 'manifest'
      - '/meta.*/'
```

Events through RabbitMQ are provided by the associated Gerrit plugin: https://gerrit.googlesource.com/plugins/rabbitmq/

By default the script will use the 'stream-events' command to listen for changes on project and re-synchronize them.
It is possible to specify the ```oneshot: true``` option, either in global or in the gerrit source definition to prevent the re-sync.


Events Publishing
-------

#### Publishers

If a publisher is configured, the events received from the Gerrit host (as configured by Gerrit or
Gerrit-RabbitMQ) are published to the downstream host. Events that do not require a Gerrit sync are
published as soon as they are received; and events that do are queued for further processing. When
a worker thread is ready to process an event queue, it first empties the event queue, perform one
sync, and publish those events. This way we ensure that when those events are received by the
downstream host, the associated sync is already completed.  Also we are saving some syncs by
performing one sync for multiple events. The implication is that we are delaying the events requring
sync, and the event arrive at the downstream host out-of-order.

The only available publisher currently is RabbitMQ.

```
  - type: 'rabbitmq'
    host: 'mirror-host'
    exchange: 'mirror-exchange'
    username: 'guest'
    password: 'guest'
```
