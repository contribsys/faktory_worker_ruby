# faktory-ruby

Faktory-ruby is the official Ruby client and worker process for the
Faktory background job server.  It is similar to [Sidekiq](http://sidekiq.org).

```
                       +--------------------+
                       |                    |
                       |     Faktory        |
                       |     Server         |
        +---------->>>>|                    +>>>>--------+
        |              |                    |            |
        |              |                    |            |
        |              +--------------------+            |
+-----------------+                            +-------------------+
|                 |                            |                   |
|    Client       |                            |     Worker        |
|    pushes       |                            |     pulls         |
|     jobs        |                            |      jobs         |
|                 |                            |                   |
|                 |                            |                   |
+-----------------+                            +-------------------+
```

* Client - an API any process can use to push jobs to the Faktory server.
* Worker - a process that pulls jobs from Faktory and executes them.
* Server - the Faktory daemon which stores background jobs in
  queues to be processed by Workers.

This gem, faktory-ruby, contains only the client and worker parts.  The
server part is [here](https://github.com/contribsys/faktory/#readme)

## Installation

First, make sure you have the [Faktory server](https://github.com/contribsys/faktory/#installation) installed.  Next, install this gem:

    gem install faktory-ruby

## Your First Job

Your Jobs should include the Faktory::Job module and have a `perform`
method.

```ruby
class SomeJob
  include Faktory::Job

  def perform(...)
  end
end
```

then just call `SomeJob.perform_later(...)` to create a job.

Arguments to the perform method must be simple types supported
by JSON, exactly like Sidekiq.

## Start the worker

Once you've created a job, you need to start a Worker process to execute
it.

```ruby
bundle exec faktory-worker
```

## Why not Sidekiq?

Sidekiq is awesome; it's very stable and useful. It suffers from two design limitations:

1. Sidekiq uses Redis and Redis is dumb datastore, all Sidekiq features are
   implemented in Ruby and have to travel over the network to access data.
2. Because of (1), Sidekiq is limited to Ruby.  You can't execute jobs
   with, e.g., Python and get the same Sidekiq features.

Instead Faktory is a "smart" server that implements all major features
within the server itself; the worker process can be dumb and rely on
the server for job retries, reservation, Web UI, etc.  This also means
we can create workers in any programming language.

Faktory-ruby tries to be Sidekiq API compatible where possible (and
PRs to improve this are very welcome).

## Commercial Support

TBD, based on demand.  Want to see Sidekiq Pro / Enterprise features
in a commercial version of Faktory?  Let me know.

## Author

Mike Perham, @mperham, mike @ contribsys.com
