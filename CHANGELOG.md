## CHANGELOG

### `v1.40.2`

#### Tweaks
* Lower log level for shutdown msg [#553](https://github.com/newrelic/elixir_agent/pull/553)

### `v1.40.1`

#### Fixes
* Fix a bug from bandit missing conn [#548](https://github.com/newrelic/elixir_agent/pull/548)

### `v1.40.0`

#### Features
* Improve Distributed Tracing error reporting [#545](https://github.com/newrelic/elixir_agent/pull/545)

------

### `v1.39.0`

#### Fixes
* Handle finch streaming error result tuple [#539](https://github.com/newrelic/elixir_agent/pull/539)
* Handle nested error report [#541](https://github.com/newrelic/elixir_agent/pull/541)
* Handle shutdown cleaner [#542](https://github.com/newrelic/elixir_agent/pull/542)

------

### `v1.38.0`

#### Features
* Add spans for phoenix controller view rendering [#531](https://github.com/newrelic/elixir_agent/pull/531)

------

### `v1.37.0`

#### Fixes
* Move `:os_mon` from included_applications to extra_applications (optional) to avoid release conflicts with other libraries [#529](https://github.com/newrelic/elixir_agent/pull/529)

------

### `v1.36.0`

#### Features
* Add error blame metrics, tweak error classification [#526](https://github.com/newrelic/elixir_agent/pull/526)

------

### `v1.35.0`

#### Features
* Add extended attributes for manual macro spans [#517](https://github.com/newrelic/elixir_agent/pull/517)

#### Fixes
* Fix bandit duration with exception [#524](https://github.com/newrelic/elixir_agent/pull/524)
* Fix bandit error reporting [#523](https://github.com/newrelic/elixir_agent/pull/523)

#### Tweaks
* Increase resolution of finch request duration [#518](https://github.com/newrelic/elixir_agent/pull/518)

------

### `v1.34.0`

#### Fixes
* Handle when LiveView meta.uri is `nil` [#512](https://github.com/newrelic/elixir_agent/pull/512)
* Enable adding span attributes inside span macro [#515](https://github.com/newrelic/elixir_agent/pull/515)
* Fix NewRelic.Logger warning level [#510](https://github.com/newrelic/elixir_agent/pull/510) Thanks @thiagogsr!
* Fix Finch category-specific attributes [#513](https://github.com/newrelic/elixir_agent/pull/513)

#### Tweaks
* Increase resolution of span duration attribute [#514](https://github.com/newrelic/elixir_agent/pull/514)

------

### `v1.33.0`

#### Fixes
* Fix unit for Oban queue time attribute [#504](https://github.com/newrelic/elixir_agent/pull/504)

#### Tweaks
* Improve nested attribute flattening [#505](https://github.com/newrelic/elixir_agent/pull/505)
* Support Logger "report" messages in Logs in Context [#506](https://github.com/newrelic/elixir_agent/pull/506)

------

### `v1.32.0`

#### Features
* Improved Phoenix LiveView instrumentation [#500](https://github.com/newrelic/elixir_agent/pull/500)
* Support connecting an Other Transaction to a Distributed Trace [#503](https://github.com/newrelic/elixir_agent/pull/503)
* Support for native JSON library [#494](https://github.com/newrelic/elixir_agent/pull/494) Thanks @TylerWitt!

#### Fixes
* Fix incomplete bandit response time metrics [#498](https://github.com/newrelic/elixir_agent/pull/498)
* Fix another bug with missing bandit conn [#497](https://github.com/newrelic/elixir_agent/pull/497)
* Fix double reported segments in TTs for bandit [#491](https://github.com/newrelic/elixir_agent/pull/491)

#### Tweaks
* Add transaction.name to Spansaction [#492](https://github.com/newrelic/elixir_agent/pull/492)

------

### `v1.31.1`

#### Fixes
* Fixes for a few bugs: transaction time attribute, span macro, bandit missing conn [#483](https://github.com/newrelic/elixir_agent/pull/483)

### `v1.31`

A big release after a long time dormant!

#### Notable changes
* Use Elixir Logger as the default agent logger [#455](https://github.com/newrelic/elixir_agent/pull/455)
  - Changes where internal New Relic agent logs will go by default
* Use logger primary filter to hook into error reporting [#466](https://github.com/newrelic/elixir_agent/pull/466)
  - No longer need to add `ErrorLogger` to your `:logger` `:backend` config
* Finch Instrumentation [#469](https://github.com/newrelic/elixir_agent/pull/469)
  - No longer need to `@trace` with `category: :external` to instrument Finch based HTTP requests

#### Features
* Make Distributed Tracing configurable [#457](https://github.com/newrelic/elixir_agent/pull/457)
* Support ignoring web transaction paths via configuration [#451](https://github.com/newrelic/elixir_agent/pull/451)
* Support host display name [#464](https://github.com/newrelic/elixir_agent/pull/464)
* Oban Instrumentation [#463](https://github.com/newrelic/elixir_agent/pull/463)
* Absinthe Instrumentation [#471](https://github.com/newrelic/elixir_agent/pull/471)
* Added `NewRelic.notice_error` to report rescued exceptions [#470](https://github.com/newrelic/elixir_agent/pull/470)
* Added `NewRelic.add_span_attributes` [#478](https://github.com/newrelic/elixir_agent/pull/478)
* Added `NewRelic.span` macro [#471](https://github.com/newrelic/elixir_agent/pull/471)

#### Tweaks
* Doc improvements [#453](https://github.com/newrelic/elixir_agent/pull/453) Thanks @axelson!
* Performance refactor to use map_reduce [#423](https://github.com/newrelic/elixir_agent/pull/423) Thanks @bradhanks!
* Handle binary attribute values better [#458](https://github.com/newrelic/elixir_agent/pull/458)
* Safer math in Process sampler [#461](https://github.com/newrelic/elixir_agent/pull/461)
* Speed up BackoffSampler with counters [#460](https://github.com/newrelic/elixir_agent/pull/460)
* Conditional compilation to address warnings [#456](https://github.com/newrelic/elixir_agent/pull/456)
* Add spansaction for regular DT [#467](https://github.com/newrelic/elixir_agent/pull/467)
* Only start telemetry handlers when agent is enabled [#474](https://github.com/newrelic/elixir_agent/pull/474)
* Only start os_mon when agent enabled [#473](https://github.com/newrelic/elixir_agent/pull/473)
* Add extended attributes for function tracers, make extended attributes configurable [#479](https://github.com/newrelic/elixir_agent/pull/479)

#### Fixes
* Handle when Bandit telemetry doesn't include the conn [#449](https://github.com/newrelic/elixir_agent/pull/449)
* Fix a few Bandit attributes [#480](https://github.com/newrelic/elixir_agent/pull/480)
* Enable Logger calls to be compile time purgable [#402](https://github.com/newrelic/elixir_agent/pull/402) Thanks @TylerWitt!
* Tracer - Create a proper list when tail of list is ignored [#465](https://github.com/newrelic/elixir_agent/pull/465)
* Add bandit optional dependency [#472](https://github.com/newrelic/elixir_agent/pull/472)

------

### `v1.30`

Features
* adjust metadata_reporter :transaction report_error [#443](https://github.com/newrelic/elixir_agent/pull/443)
* Identify Phoenix LiveView metrics [#424](https://github.com/newrelic/elixir_agent/pull/424)
* Add Bandit HTTP server support [#445](https://github.com/newrelic/elixir_agent/pull/445)

------

### `v1.29`

Features
* Ensure working support for newer versions, up to Erlang 26 and Elixir 15
  [#420](https://github.com/newrelic/elixir_agent/pull/420),
  [#421](https://github.com/newrelic/elixir_agent/pull/421),
  [#426](https://github.com/newrelic/elixir_agent/pull/426),
  [#427](https://github.com/newrelic/elixir_agent/pull/427). Thank you so
  much @tmaszk and @XiXiaPdx!

------

### `v1.28`

Features
* Add feature to remove function argument data from stacktraces reported to New Relic.
[#417](https://github.com/newrelic/elixir_agent/pull/417) Thanks @griffitr!
* Add support for [Dimensional Metrics](https://docs.newrelic.com/docs/query-your-data/nrql-new-relic-query-language/nrql-query-tutorials/query-infrastructure-dimensional-metrics-nrql/).
[#408](https://github.com/newrelic/elixir_agent/pull/408) Thanks @XiXiaPdx!

------

### `v1.27.8`

Features
* Allow user to provide global override of some HTTP client settings. [#391](https://github.com/newrelic/elixir_agent/pull/391) Thanks @edds!

### `v1.27.7`

Fixes
* Handle DT payload with unknown version. [#374](https://github.com/newrelic/elixir_agent/pull/374) Thanks @renanlage!

### `v1.27.6`

Tweaks
* Update Telemetry dependency to allow Telemetry 1.0. [#363](https://github.com/newrelic/elixir_agent/pull/363) Thanks @jimsynz!

### `v1.27.5`

Fixes
* Avoid a race condition during Task instrumentation compilation. [#359](https://github.com/newrelic/elixir_agent/pull/359) Thanks @mhanberg!

### `v1.27.4`

Fixes
* Don't fail an Other Transaction upon expected error. [#357](https://github.com/newrelic/elixir_agent/pull/357)

### `v1.27.3`

Fixes
* Fix categorization of simple SQL queries in Ecto. [#354](https://github.com/newrelic/elixir_agent/pull/354) Thanks @mrz!

### `v1.27.2`

Fixes
* Fix a leak in other transactions when not manually closed. [#352](https://github.com/newrelic/elixir_agent/pull/352)

### `v1.27.1`

Features
* Auto-require `NewRelic` in `use NewRelic.Tracer` for convenience. [#350](https://github.com/newrelic/elixir_agent/pull/350)

### `v1.27.0`

Features
* Include start_link in transaction tracing. [#344](https://github.com/newrelic/elixir_agent/pull/344)

------

### `v1.26.0`

Features
* Increase timestamp resolution. [#343](https://github.com/newrelic/elixir_agent/pull/343)

------

### `v1.25.3`

Fixes
* Handle exception asking for remote process name. [#342](https://github.com/newrelic/elixir_agent/pull/342) Thanks @benhaney!

### `v1.25.2`

Fixes
* Fix edge case in new `Ecto` table name parsing. [#340](https://github.com/newrelic/elixir_agent/pull/340)

### `v1.25.1`

Fixes
* Fix edge case in new `Ecto` table name parsing. [#338](https://github.com/newrelic/elixir_agent/pull/338)

### `v1.25.0`

Features
* Support for any `Ecto` adapter, including Sqlite and MSSQL. [#337](https://github.com/newrelic/elixir_agent/pull/337) Thanks @marocchino!

------

### `v1.24.5`

Fixes
* Ensure instrumentation calls don't fail if app not started. [#332](https://github.com/newrelic/elixir_agent/pull/332)

### `v1.24.4`

Tweaks
* Support per-log message metadata. [#330](https://github.com/newrelic/elixir_agent/pull/330) Thanks @mattgibson!
* Properly render IO list log message. [#329](https://github.com/newrelic/elixir_agent/pull/329) Thanks @mattgibson!

### `v1.24.3`

Fixes
* Fix Telemetry API URLs for EU customers. [#326](https://github.com/newrelic/elixir_agent/pull/326) Thanks @mattgibson!

### `v1.24.2`

Tweaks
* Use `castore` for certificates. [#320](https://github.com/newrelic/elixir_agent/pull/320) Thanks @chulkilee!

### `v1.24.1`

Tweaks
* Add a helper module for auto-instrumenting a `Task`. [#318](https://github.com/newrelic/elixir_agent/pull/318)

### `v1.24.0`

Features
* `Plug` instrumentation is now fully automatic based on `telemetry` events!
  * Please remove deprecated calls:
    - `use NewRelic.Transaction`
    - `NewRelic.Transaction.handle_errors/2`
* `Phoenix` instrumentation is now fullly automatic based on `telemetry` events!
  * Please remove deprecated instrumentation library:
    - https://github.com/binaryseed/new_relic_phoenix
* Transaction tracking is now faster and better in the face of overload
  * Note: Transactions no longer follow processes that aren't linked (ex: `Task.Supervisor.async_nolink`). They can be connected manually if desired using `NewRelic.connect_to_transaction`.

------

### `v1.23.6`

Fixes
* Coerce Transaction Trace segment attribute values. [#316](https://github.com/newrelic/elixir_agent/pull/316)

### `v1.23.5`

Fixes
* Inspect failed output going to log. [#315](https://github.com/newrelic/elixir_agent/pull/315)

### `v1.23.4`

Tweaks
* Add ability to increment custom metric. [#314](https://github.com/newrelic/elixir_agent/pull/314) Thanks @edds!

### `v1.23.3`

Tweaks
* Add automatic attributes to the Spansaction. [#312](https://github.com/newrelic/elixir_agent/pull/312)
* Track tracer reductions. [#313](https://github.com/newrelic/elixir_agent/pull/313)

### `v1.23.2`

Tweaks
* Minor change to External span tracer attributes. [#311](https://github.com/newrelic/elixir_agent/pull/311)

### `v1.23.1`

Tweaks
* Improve External span names. [#309](https://github.com/newrelic/elixir_agent/pull/309)

### `v1.23.0`

Features
* Adds support for Infinite Tracing. [#307](https://github.com/newrelic/elixir_agent/pull/307)

------

### `v1.22.6`

Tweaks
* Add `ERTS Version` to environment values. [#302](https://github.com/newrelic/elixir_agent/pull/302)

### `v1.22.5`

Fixes
* Handle formatting exit edge case. [#300](https://github.com/newrelic/elixir_agent/pull/300)
* Work around CPU util shutdown issue. [#301](https://github.com/newrelic/elixir_agent/pull/301)

### `v1.22.4`

Features
* Adds a macro for defining an Other Transaction. [#264](https://github.com/newrelic/elixir_agent/pull/264)

Fixes
* Handle when a string winds up in a stacktrace list. [#294](https://github.com/newrelic/elixir_agent/pull/294)
* Properly handle boolean config option. [#295](https://github.com/newrelic/elixir_agent/pull/295)
* Prevent error when bad attribute values get in. [#296](https://github.com/newrelic/elixir_agent/pull/296)

### `v1.22.3`

Tweaks
* Make request queuing collection configurable [#292](https://github.com/newrelic/elixir_agent/pull/292)

### `v1.22.2`

Tweaks
* Optimize metric aggregation with `:counter`

### `v1.22.1`

Fixes
* Fix a compile time warning about `:scheduler` [#288](https://github.com/newrelic/elixir_agent/pull/288)
* Avoid a shutdown bug in `:cpu_sup` [#287](https://github.com/newrelic/elixir_agent/pull/287)

### `v1.22.0`

Features
* Report a custom metric. [#283](https://github.com/newrelic/elixir_agent/pull/283)

------

### `v1.21.2`

Fixes
* Handle encoding an unexpected nil sampled flag. [#282](https://github.com/newrelic/elixir_agent/pull/282)

### `v1.21.1`

Fixes
* Properly handle a bad tracestate sampled / priority value. [#273](https://github.com/newrelic/elixir_agent/pull/273)

### `v1.21.0`

Features
* Logs in context - connect `Logger` messages to the current Distributed Trace / Error Trace. [#272](https://github.com/newrelic/elixir_agent/pull/272)

Logs in context requires Elixir 1.10 or greater.

------

### `v1.20.0`

Removals:
* Stop reporting redundant `ElixirAggregate` custom events for `Transaction`. [#276](https://github.com/newrelic/elixir_agent/pull/276)
* Stop reporting redundant `ElixirAggregate` custom events for `FunctionTrace`. [#277](https://github.com/newrelic/elixir_agent/pull/277)

Alternatives for querying this data are available and noted in the PRs.

Fixes
* Don't warn for untraced functions. [#269](https://github.com/newrelic/elixir_agent/pull/269) Thanks @barthez!
* Spread the Samplers across the full sample cycle. [#278](https://github.com/newrelic/elixir_agent/pull/278)

------

### `v1.19.7`

Tweaks
* Log the number of events seen by harvesters. [#274](https://github.com/newrelic/elixir_agent/pull/274)

### `v1.19.6`

Fixes
* Properly handle bad values in Custom and Span Events. [#267](https://github.com/newrelic/elixir_agent/pull/267) & [#268](https://github.com/newrelic/elixir_agent/pull/268)

### `v1.19.5`

Fixes
* Fix memory leak in long running transactions. [#263](https://github.com/newrelic/elixir_agent/pull/263) Thanks @mopp!

### `v1.19.4`

Fixes
* Fix tracer compilation bug. [#255](https://github.com/newrelic/elixir_agent/pull/255)

### `v1.19.3`

Features
* Report more Error metrics based on transaction type. [#251](https://github.com/newrelic/elixir_agent/pull/251)

### `v1.19.2`

Tweaks
* Optimize memory usage in Metric harvester. [#242](https://github.com/newrelic/elixir_agent/pull/242)
* Silence warnings in Elixir 1.10. [#243](https://github.com/newrelic/elixir_agent/pull/243)

### `v1.19.1`

Fixes
* Fix a regression from 1.18 with Transaction error attribute. [#240](https://github.com/newrelic/elixir_agent/pull/240)

### `v1.19.0`

Features
* Automatic `Redix` instrumentation based on `telemetry` events! [#210](https://github.com/newrelic/elixir_agent/pull/210)

------

### `v1.18.5`

Fixes

* Fix one more tracer compilation bug. [#239](https://github.com/newrelic/elixir_agent/pull/239)

### `v1.18.4`

Fixes

* Fix another interesting tracer compilation bug. [#235](https://github.com/newrelic/elixir_agent/pull/235)

### `v1.18.3`

Fixes

* Fix another tracer compilation bug. [#230](https://github.com/newrelic/elixir_agent/pull/230)

### `v1.18.2`

Fixes

* Fix a tracer compilation bug. [#228](https://github.com/newrelic/elixir_agent/pull/228)

### `v1.18.1`

Tweaks

* Report additional Datastore metrics. [#224](https://github.com/newrelic/elixir_agent/pull/224)

### `v1.18.0`

Features

* Read the Docker container ID for accurate container detection. [#207](https://github.com/newrelic/elixir_agent/pull/207) Thanks @alejandrodnm!
* Report Ecto queries that result in an error. [#202](https://github.com/newrelic/elixir_agent/pull/202)
* Coerce and handle all custom attribute values. [#205](https://github.com/newrelic/elixir_agent/pull/205)
* `Mix.Task` instrumentation. [#221](https://github.com/newrelic/elixir_agent/pull/221)

Tweaks

* Make `plug_cowboy` an optional dep. [#201](https://github.com/newrelic/elixir_agent/pull/201)
* Use Erlang/OTP 21+ built-in SSL hostname verification. [#197](https://github.com/newrelic/elixir_agent/pull/197)
* Reduce contention on transaction storage. [#209](https://github.com/newrelic/elixir_agent/pull/209)
* Detect Ecto repo via telemetry event instead of an Erlang tracer. [#214](https://github.com/newrelic/elixir_agent/pull/214)
* Fix for Distributed Traces that start from a Browser Agent. [#215](https://github.com/newrelic/elixir_agent/pull/215)
* Fix for error reporting during Other Transactions. [#220](https://github.com/newrelic/elixir_agent/pull/220) Thanks @prabello.

------

### `v1.17.1`

Fixes

* Handle cases where another New Relic agent sends a bad `tracestate` header. [#206](https://github.com/newrelic/elixir_agent/pull/206)

### `v1.17.0`

Features

* Report "Scoped" Transaction metrics:
  * Externals [#175](https://github.com/newrelic/elixir_agent/pull/175)
  * Function traces [#189](https://github.com/newrelic/elixir_agent/pull/189)
  * Database calls [#195](https://github.com/newrelic/elixir_agent/pull/195)

* Enable disabling function argument tracing globally & per-trace. [#186](https://github.com/newrelic/elixir_agent/pull/186)

* Provide an API for manually stopping an Other transaction. [#198](https://github.com/newrelic/elixir_agent/pull/198)

------

### `v1.16.7`

Fixes

* Handle Ecto stream telemetry results. [#192](https://github.com/newrelic/elixir_agent/pull/192)

### `v1.16.6`

Fixes

* Prevent boot process from getting blocked if New Relic is slow. [#187](https://github.com/newrelic/elixir_agent/pull/187)

### `v1.16.5`

Fixes

* Fix macro compilation with Elixir `1.10`. Thanks @ethangunderson! [#185](https://github.com/newrelic/elixir_agent/pull/185)

### `v1.16.4`

Tweaks

* Remove ecto metadata catchall for better debugging.

### `v1.16.3`

Fixes

* Fix sampling decision default value. [#177](https://github.com/newrelic/elixir_agent/pull/177)

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
