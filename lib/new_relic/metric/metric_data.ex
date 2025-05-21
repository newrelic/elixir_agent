defmodule NewRelic.Metric.MetricData do
  # Heper functions for generating Metrics with the correct timeslice values

  @moduledoc false

  alias NewRelic.Metric

  def transform({:custom, name}, count: count),
    do: %Metric{
      name: join(["Custom", name]),
      call_count: count
    }

  def transform({:custom, name}, count: count, value: value),
    do: %Metric{
      name: join(["Custom", name]),
      call_count: count,
      total_call_time: value,
      min_call_time: value,
      max_call_time: value
    }

  def transform(:http_dispatcher, duration_s: duration_s),
    do: %Metric{
      name: :HttpDispatcher,
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }

  def transform({:transaction, name},
        type: :Web,
        duration_s: duration_s,
        total_time_s: total_time_s
      ),
      do: [
        %Metric{
          name: "WebTransaction",
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["WebTransaction", name]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: "WebTransactionTotalTime",
          call_count: 1,
          total_call_time: total_time_s,
          total_exclusive_time: total_time_s,
          min_call_time: total_time_s,
          max_call_time: total_time_s
        },
        %Metric{
          name: join(["WebTransactionTotalTime", name]),
          call_count: 1,
          total_call_time: total_time_s,
          total_exclusive_time: total_time_s,
          min_call_time: total_time_s,
          max_call_time: total_time_s
        }
      ]

  def transform({:transaction, name},
        type: :Other,
        duration_s: duration_s,
        total_time_s: total_time_s
      ),
      do: [
        %Metric{
          name: "OtherTransaction/all",
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["OtherTransaction", name]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: "OtherTransactionTotalTime",
          call_count: 1,
          total_call_time: total_time_s,
          total_exclusive_time: total_time_s,
          min_call_time: total_time_s,
          max_call_time: total_time_s
        },
        %Metric{
          name: join(["OtherTransactionTotalTime", name]),
          call_count: 1,
          total_call_time: total_time_s,
          total_exclusive_time: total_time_s,
          min_call_time: total_time_s,
          max_call_time: total_time_s
        }
      ]

  def transform(
        {:caller, type, account_id, app_id, transport_type},
        duration_s: duration_s
      ),
      do: %Metric{
        name: join(["DurationByCaller", type, account_id, app_id, transport_type, "all"]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }

  def transform({:datastore, datastore, table, operation},
        type: type,
        scope: scope,
        duration_s: duration_s
      ),
      do: [
        %Metric{
          name: join(["Datastore/statement", datastore, table, operation]),
          scope: join(["#{type}Transaction", scope]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore/operation", datastore, operation]),
          scope: join(["#{type}Transaction", scope]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", datastore, "all#{type}"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: "Datastore/all#{type}",
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        }
      ]

  def transform({:datastore, datastore, table, operation},
        duration_s: duration_s
      ),
      do: [
        %Metric{
          name: join(["Datastore/statement", datastore, table, operation]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore/operation", datastore, operation]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", datastore, "all"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", "all"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        }
      ]

  def transform({:datastore, datastore, operation},
        type: type,
        scope: scope,
        duration_s: duration_s
      ),
      do: [
        %Metric{
          name: join(["Datastore/operation", datastore, operation]),
          scope: join(["#{type}Transaction", scope]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", datastore, "all#{type}"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", "all#{type}"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        }
      ]

  def transform({:datastore, datastore, operation},
        duration_s: duration_s
      ),
      do: [
        %Metric{
          name: join(["Datastore/operation", datastore, operation]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", datastore, "all"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        },
        %Metric{
          name: join(["Datastore", "all"]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        }
      ]

  def transform({:external, url, component, method}, duration_s: duration_s) do
    host = URI.parse(url).host
    method = method |> to_string() |> String.upcase()

    [
      %Metric{
        name: :"External/all",
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      },
      %Metric{
        name: join(["External", host, "all"]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      },
      %Metric{
        name: join(["External", host, component, method]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }
    ]
  end

  def transform({:external, url, component, method},
        type: type,
        scope: scope,
        duration_s: duration_s
      ) do
    host = URI.parse(url).host
    method = method |> to_string() |> String.upcase()

    %Metric{
      name: join(["External", host, component, method]),
      scope: join(["#{type}Transaction", scope]),
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }
  end

  def transform({:external, name}, duration_s: duration_s),
    do: [
      %Metric{
        name: :"External/all",
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      },
      %Metric{
        name: join(["External", name, "all"]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }
    ]

  def transform({:external, name}, type: type, scope: scope, duration_s: duration_s),
    do: %Metric{
      name: join(["External", name]),
      scope: join(["#{type}Transaction", scope]),
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }

  def transform(:external, type: type, duration_s: duration_s),
    do: %Metric{
      name: "External/all#{type}",
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }

  def transform({:function, function_name}, duration_s: duration_s),
    do: %Metric{
      name: join(["Function", function_name]),
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }

  def transform({:function, function_name},
        duration_s: duration_s,
        exclusive_time_s: exclusive_time_s
      ),
      do: %Metric{
        name: join(["Function", function_name]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: exclusive_time_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }

  def transform({:function, function_name},
        type: type,
        scope: scope,
        duration_s: duration_s,
        exclusive_time_s: exclusive_time_s
      ),
      do: %Metric{
        name: join(["Function", function_name]),
        scope: join(["#{type}Transaction", scope]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: exclusive_time_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }

  def transform(:error, type: type, error_count: error_count),
    do: [
      %Metric{
        name: "Errors/all#{type}",
        call_count: error_count
      },
      %Metric{
        name: :"Errors/all",
        call_count: error_count
      }
    ]

  def transform({:error, blame}, type: type, error_count: error_count),
    do: [
      %Metric{
        name: join(["Errors", "#{type}Transaction", blame]),
        call_count: error_count
      },
      %Metric{
        name: "Errors/all#{type}",
        call_count: error_count
      },
      %Metric{
        name: :"Errors/all",
        call_count: error_count
      }
    ]

  def transform(:error, error_count: error_count),
    do: %Metric{
      name: :"Errors/all",
      call_count: error_count
    }

  def transform(:memory, mb: memory_mb),
    do: %Metric{
      name: :"Memory/Physical",
      call_count: 1,
      total_call_time: memory_mb,
      min_call_time: memory_mb,
      max_call_time: memory_mb
    }

  def transform(:cpu, utilization: utilization),
    do: %Metric{
      name: :"CPU/User Time",
      call_count: 1,
      total_call_time: utilization,
      min_call_time: utilization,
      max_call_time: utilization
    }

  def transform(:apdex, apdex: :satisfying, threshold: t),
    do: %Metric{name: :Apdex, call_count: 1, min_call_time: t, max_call_time: t}

  def transform(:apdex, apdex: :tolerating, threshold: t),
    do: %Metric{name: :Apdex, total_call_time: 1, min_call_time: t, max_call_time: t}

  def transform(:apdex, apdex: :frustrating, threshold: t),
    do: %Metric{name: :Apdex, total_exclusive_time: 1, min_call_time: t, max_call_time: t}

  def transform({:supportability, :error_event}, error_count: error_count),
    do: [
      %Metric{
        name: :"Supportability/Events/TransactionError/Sent",
        call_count: error_count
      },
      %Metric{
        name: :"Supportability/Events/TransactionError/Seen",
        call_count: error_count
      }
    ]

  def transform({:supportability, :infinite_tracing}, spans_seen: spans_seen),
    do: [
      %Metric{
        name: :"Supportability/InfiniteTracing/Span/Seen",
        call_count: spans_seen
      }
    ]

  def transform({:supportability, :infinite_tracing}, harvest_size: harvest_size),
    do: [
      %Metric{
        name: :"Supportability/InfiniteTracing/Span/Sent",
        call_count: harvest_size
      },
      %Metric{
        name: :"Supportability/Elixir/TelemetrySdk/Harvest/Span",
        call_count: 1
      },
      %Metric{
        name: :"Supportability/Harvest",
        call_count: 1
      }
    ]

  def transform({:supportability, harvester},
        events_seen: events_seen,
        reservoir_size: reservoir_size
      ),
      do: [
        %Metric{
          name: join(["Supportability/Elixir/Collector/HarvestSeen", harvester]),
          call_count: 1,
          total_call_time: events_seen
        },
        %Metric{
          name: join(["Supportability/EventHarvest", harvester, "HarvestLimit"]),
          call_count: 1,
          total_call_time: reservoir_size
        }
      ]

  def transform({:supportability, harvester}, harvest_size: harvest_size),
    do: [
      %Metric{
        name: join(["Supportability/Elixir/Collector/HarvestSize", harvester]),
        call_count: 1,
        total_call_time: harvest_size
      },
      %Metric{
        name: :"Supportability/Harvest",
        call_count: 1
      }
    ]

  def transform({:supportability, :agent, metric}, value: value),
    do: %Metric{
      name: join(["Supportability/ElixirAgent", metric]),
      call_count: 1,
      total_call_time: value,
      min_call_time: value,
      max_call_time: value
    }

  def transform({:supportability, :collector}, status: status),
    do: %Metric{
      name: join(["Supportability/Agent/Collector/HTTPError", status]),
      call_count: 1
    }

  def transform(:supportability, [:trace_context, :accept, :success]),
    do: %Metric{
      name: :"Supportability/TraceContext/Accept/Success",
      call_count: 1
    }

  def transform(:supportability, [:trace_context, :accept, :exception]),
    do: %Metric{
      name: :"Supportability/TraceContext/Accept/Exception",
      call_count: 1
    }

  def transform(:supportability, [:trace_context, :tracestate, :non_new_relic]),
    do: %Metric{
      name: :"Supportability/TraceContext/TraceState/NoNrEntry",
      call_count: 1
    }

  def transform(:supportability, [:trace_context, :tracestate, :invalid]),
    do: %Metric{
      name: :"Supportability/TraceContext/TraceState/Parse/Exception",
      call_count: 1
    }

  def transform(:supportability, [:trace_context, :traceparent, :invalid]),
    do: %Metric{
      name: :"Supportability/TraceContext/TraceParent/Parse/Exception",
      call_count: 1
    }

  def transform(:supportability, [:dt, :accept, :success]),
    do: %Metric{
      name: :"Supportability/DistributedTrace/AcceptPayload/Success",
      call_count: 1
    }

  def transform(:supportability, [:dt, :accept, :parse_error]),
    do: %Metric{
      name: :"Supportability/DistributedTrace/AcceptPayload/ParseException",
      call_count: 1
    }

  def transform(:queue_time, duration_s: duration_s),
    do: %Metric{
      name: "WebFrontend/QueueTime",
      call_count: 1,
      total_call_time: duration_s,
      total_exclusive_time: duration_s,
      min_call_time: duration_s,
      max_call_time: duration_s
    }

  defp join(segments), do: NewRelic.Util.metric_join(segments)
end
