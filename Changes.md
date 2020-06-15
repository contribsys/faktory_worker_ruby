# Changes

## HEAD

- Run client middleware before pushing a job to Faktory [#48]
- Implement read timeouts for Faktory::Client for faktory#297

## 1.0.0

- Ruby 2.5+ is now required
- Support for Faktory Enterprise, job batches and job tracking
- Support for the MUTATE command.
- Notify Faktory when a worker process is going quiet so that the UI shows this
- Refactor Faktory::Client error handling for faktory#208

## 0.8.1

- Fix breakage with non-ActiveJobs [#29]
- Ruby 2.3+ is now required

## 0.8.0

- Add `-l LABEL` argument for adding labels to a process [#27, jpwinans]
- Support the quiet and shutdown heartbeat signals from the server [#28]

## 0.7.1

- Add an ActiveJob adapter for FWR. [#17, jagthedrummer]

## 0.7.0

- Add testing API, almost identical to Sidekiq's `sidekiq/testing` API.
  [#7, thebadmonkeydev, jagthedrummer]

## 0.6.1

- Fix password hashing

## 0.6.0

- Updates for Faktory 0.6.0 and protocol V2.

## 0.5.0

- Initial release
