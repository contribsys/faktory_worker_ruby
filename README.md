# faktory\_worker\_ruby

![CI status](https://github.com/contribsys/faktory_worker_ruby/actions/workflows/ci.yml/badge.svg)

Faktory\_worker\_ruby is the official Ruby client and worker process for the
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
|    pushes       |                            |     fetches       |
|     jobs        |                            |      jobs         |
|                 |                            |                   |
|                 |                            |                   |
+-----------------+                            +-------------------+
```

* Client - an API any process can use to push jobs to the Faktory server.
* Worker - a process that pulls jobs from Faktory and executes them.
* Server - the Faktory daemon which stores background jobs in
  queues to be processed by Workers.

This gem contains only the client and worker parts.  The
server part is [here](https://github.com/contribsys/faktory/)

## Requirements

* Ruby 2.5 or higher
* Faktory 1.2 or higher [Installation](https://github.com/contribsys/faktory/wiki/Installation)

Optionally, Rails 5.2+ for ActiveJob.

## Installation

    gem install faktory_worker_ruby

## Documentation

See the [wiki](//github.com/contribsys/faktory_worker_ruby/wiki) for more details.

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

then just call `SomeJob.perform_async(...)` to create a job.

Arguments to the perform method must be simple types supported
by JSON, exactly like Sidekiq.

## Start the worker

Once you've created a job, you need to start a Worker process to execute
those jobs.

```ruby
bundle exec faktory-worker
```

## Why not Sidekiq?

Sidekiq is awesome; it's stable and useful. It suffers from two design limitations:

1. Sidekiq uses Redis and Redis is dumb datastore, all Sidekiq features are
   implemented in Ruby and have to travel over the network to access data.
2. Because of (1), Sidekiq is limited to Ruby.  You can't execute jobs
   with, e.g., Python and get the same Sidekiq features.

Instead Faktory is a "smart" server that implements all major features
within the server itself; the worker process can be dumb and rely on
the server for job retries, reservation, Web UI, etc.  This also means
we can create workers in any programming language.

If your organization is 100% Ruby, Sidekiq will serve you well.  If your
organization is polyglot, Faktory will be a better fit.

faktory\_worker\_ruby tries to be Sidekiq API compatible where possible (and
PRs to improve this are very welcome).

## Author

Mike Perham, @getajobmike, mike @ contribsys.com
