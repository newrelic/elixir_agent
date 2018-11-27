## CHANGELOG

### `v1.2.1`

* Fix a bug that caused a subset of Span Events to be sent even though the Transaction wasn't sampled [#63](https://github.com/newrelic/elixir_agent/pull/63)

-------

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

-------

### `v1.0.4`

* Enable configuring Error collection via `:error_collector_enabled` [#36](https://github.com/newrelic/elixir_agent/pull/36) (Thanks @sb8244)

-------

### `v1.0.3`

* Report basic CPU and Memory metrics [#34](https://github.com/newrelic/elixir_agent/pull/34)
* Report caller metrics to enable relationship generation
* Extend the timeout waiting for data to post to New Relic
* Add `HTTPoison.request/5` instrumented function (Thanks @rhruiz)
