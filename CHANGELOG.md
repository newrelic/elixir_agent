## CHANGELOG

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
