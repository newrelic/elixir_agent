## CHANGELOG

### `v1.17.0`

Features
* Report "Scoped" Transaction metrics.

------

### `v1.16.2`

Fixes

* Handle error queries properly. [#173](https://github.com/newrelic/elixir_agent/pull/173)

### `v1.16.1`

Fixes

* Safely access optional Ecto config attributes. [#172](https://github.com/newrelic/elixir_agent/pull/172)

### `v1.16.0`

Features

* Support the W3C Trace Context spec for Distributed Tracing. [#169](https://github.com/newrelic/elixir_agent/pull/169)
* Upgrade to New Relic "Protocol 17" which includes support for faster event harvest (sent every 5 seconds!). [#168](https://github.com/newrelic/elixir_agent/pull/168)

------

### `v1.15.0`

Features

* Adds automatic Ecto instrumentation via `telemetry`. [#161](https://github.com/newrelic/elixir_agent/pull/161)
* Deprecates `@trace {_, category: :datastore}`. These trace annotations will now be ignored, and a warning logged during compilation.
  * Metric name change: Datastore Metrics reported now follow New Relic naming conventions, based on the table name

------

### `v1.14.0`

Features

* Minor internal refactor to enable reporting spans after they complete. [#160](https://github.com/newrelic/elixir_agent/pull/160)

------

### `v1.13.1`

Fixes

* Handle rare edge cases connecting to New Relic. [#156](https://github.com/newrelic/elixir_agent/pull/156)

### `v1.13.0`

Features

* `OTP 21+` has been required for a while, and now the agent will enforce this version requirement [#151](https://github.com/newrelic/elixir_agent/pull/151)
* Truncate super large nested attribute structure [#153](https://github.com/newrelic/elixir_agent/pull/153)

------

### `v1.12.0`

Features

* Add support for detecting request queuing via `x-request-start`. [#143](https://github.com/newrelic/elixir_agent/pull/143) Thanks @sb8244!
  - https://docs.newrelic.com/docs/apm/applications-menu/features/configure-request-queue-reporting

------

### `v1.11.0`

Features

* Add support for detecting if the app is running inside Kubernetes. [#140](https://github.com/newrelic/elixir_agent/pull/140)

------

### `v1.10.2`

Fixes

* Protect against huge arguments blowing out memory [#136](https://github.com/newrelic/elixir_agent/pull/136)

### `v1.10.1`

Tweaks

* Handle lists inside objects passed to `add_attributes` [#135](https://github.com/newrelic/elixir_agent/pull/135) Thanks @emeryotopalik!

### `v1.10.0`

Features

* Add an option to not track `async_nolink` task as part of the Transaction. [#123](https://github.com/newrelic/elixir_agent/pull/123)
* Ignore extraneous Plug errors (ie: 400s). [#125](https://github.com/newrelic/elixir_agent/pull/125)

Tweaks

* Improve formatting of ErlangError. [#126](https://github.com/newrelic/elixir_agent/pull/126)

------

### `v1.9.12`

Fixes

* Prevent a rare harvester leak. [#124](https://github.com/newrelic/elixir_agent/pull/124)

### `v1.9.11`

Fixes

* Protect against missing attribute under race condition. [#120](https://github.com/newrelic/elixir_agent/pull/120)

### `v1.9.10`

Fixes

* Revert `async_nolink` change. [#119](https://github.com/newrelic/elixir_agent/pull/119)

### `v1.9.9`

Fixes

* Fix a race condition around error reporting and `async_nolink` [#118](https://github.com/newrelic/elixir_agent/pull/118). Thanks @zoevkay!

### `v1.9.8`

Fixes

* Fix a bug causing extra spans to be reported [#116](https://github.com/newrelic/elixir_agent/pull/116)

### `v1.9.7`

Tweaks

* Improve formatting for `EXIT` errors
  - [#112](https://github.com/newrelic/elixir_agent/pull/112)
  - [#113](https://github.com/newrelic/elixir_agent/pull/113)

### `v1.9.5`

Tweaks

* Track CPU count. [#110](https://github.com/newrelic/elixir_agent/pull/110)

### `v1.9.4`

Fixes

* Fix a bug in `PriorityQueue`. [#109](https://github.com/newrelic/elixir_agent/pull/109) Thanks @jasondew!

### `v1.9.3`

Tweaks

* Lowers the log level for harvester output. [#105](https://github.com/newrelic/elixir_agent/pull/105)

### `v1.9.2`

Fixes

* Fix a error that can happen if required attributes aren't captured. [#103](https://github.com/newrelic/elixir_agent/pull/103)

### `v1.9.1`

Fixes

* Fix the transaction event name attribute. [#100](https://github.com/newrelic/elixir_agent/pull/100)

### `v1.9.0`

Features

* Use erlang's `httpc` client. [#70](https://github.com/newrelic/elixir_agent/pull/70)
* Calculate and report the Total Time in a Transaction. [#98](https://github.com/newrelic/elixir_agent/pull/98)

Fixes

* Attempt to flush each harvester upon graceful shutdown. [#94](https://github.com/newrelic/elixir_agent/pull/94)
* Report External metrics based on transaction type. [#99](https://github.com/newrelic/elixir_agent/pull/99)

-------

### `v1.8.0`

Features

* Enable ignoring a Transaction. [#93](https://github.com/newrelic/elixir_agent/pull/93)
* Track the number of processes spawned during a Transaction. [#88](https://github.com/newrelic/elixir_agent/pull/88)

Fixes

* Handle error fetching AWS fargate metadata. [#89](https://github.com/newrelic/elixir_agent/pull/89)
* Avoid a compiler warning for some traced functions. [#92](https://github.com/newrelic/elixir_agent/pull/92)
* Prevent nested spans from duplicating attributes. [#97](https://github.com/newrelic/elixir_agent/pull/97)

-------

### `v1.7.0`

* Support for "Other" (non-web) Transactions. [#84](https://github.com/newrelic/elixir_agent/pull/84)
* Calculate and report Apdex metric. [#87](https://github.com/newrelic/elixir_agent/pull/87)

-------

### `v1.6.2`

* Improve error logging when encountering a bad DT payload

### `v1.6.1`

* Clear up some deprecation warnings in Elixir `1.8.0`

### `v1.6.0`

* Add support for applying labels. [#79](https://github.com/newrelic/elixir_agent/pull/79)
* Detect Heroku dyno hostnames. [#80](https://github.com/newrelic/elixir_agent/pull/80)
* Provide better error structure for wrapped exceptions. [#78](https://github.com/newrelic/elixir_agent/pull/78)

-------

### `v1.5.0`

* More flexible datastore metric reporting in prep for `Ecto` instrumentation. [#76](https://github.com/newrelic/elixir_agent/pull/76)

-------

### `v1.4.0`

* Support nested Function Tracers in Transaction Traces and Distributed Tracing. [#58](https://github.com/newrelic/elixir_agent/pull/58)

-------

### `v1.3.2`

* Specify `Plug` and `Cowboy` versions via `plug_cowboy` package.

### `v1.3.1`

* Properly handle when no app name has been supplied.

### `v1.3.0`

* Enable the NewRelic logger to use the Elixir Logger [#67](https://github.com/newrelic/elixir_agent/pull/67)
* Properly assign multiple app names [#66](https://github.com/newrelic/elixir_agent/pull/66).
* Log the collector method along with failed requests [#65](https://github.com/newrelic/elixir_agent/pull/65).

-------

### `v1.2.1`

* Fix a bug that caused a subset of Span Events to be sent even though the Transaction wasn't sampled [#63](https://github.com/newrelic/elixir_agent/pull/63)

### `v1.2.0`

* Leverage the new Erlang `:logger` when running OTP 21 for improved Transaction / Error connecting [#55](https://github.com/newrelic/elixir_agent/pull/55)
* Record process memory & reductions at the end of a Transaction [#56](https://github.com/newrelic/elixir_agent/pull/56)

-------

### `v1.1.0`

* Report as `elixir`. [#19](https://github.com/newrelic/elixir_agent/pull/19)

APM now has first-class support for Elixir! Along with this agent upgrade, you will find the BEAM stats page availble with easy access to information about the VM, including Processes, Memory and Network. See https://github.com/newrelic/elixir_agent/wiki/BEAM-stats-page for more info.

* Note: I haven't followed semver very well, from now on I'll be bumping the minor version for each release of new features, and reserve the patch for bugfixes.

-------

### `v1.0.5`

* Report more Beam VM stats. [#38](https://github.com/newrelic/elixir_agent/pull/38), [#46](https://github.com/newrelic/elixir_agent/pull/46)
* Report process stats for top consuming processes. [#41](https://github.com/newrelic/elixir_agent/pull/41)
* Re-factor a few agent innards to enable transaction name and errors.

### `v1.0.4`

* Enable configuring Error collection via `:error_collector_enabled` [#36](https://github.com/newrelic/elixir_agent/pull/36) (Thanks @sb8244)

### `v1.0.3`

* Report basic CPU and Memory metrics [#34](https://github.com/newrelic/elixir_agent/pull/34)
* Report caller metrics to enable relationship generation
* Extend the timeout waiting for data to post to New Relic
* Add `HTTPoison.request/5` instrumented function (Thanks @rhruiz)
