defmodule NewRelic.Harvest.Collector.MetricData do
  # Heper functions for generating Metrics with the correct timeslice values

  @moduledoc false

  alias NewRelic.Metric

  def transform({:transaction, name}, duration_s: duration_s, total_time_s: total_time_s),
    do: [
      %Metric{
        name: :HttpDispatcher,
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      },
      %Metric{
        name: :WebTransaction,
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
        name: :WebTransactionTotalTime,
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

  def transform({:other_transaction, name}, duration_s: duration_s, total_time_s: total_time_s),
    do: [
      %Metric{
        name: :"OtherTransaction/all",
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
        name: :OtherTransactionTotalTime,
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
        {:caller, parent_type, parent_account_id, parent_app_id, transport_type},
        duration_s: duration_s
      ),
      do: [
        %Metric{
          name:
            join([
              "DurationByCaller",
              parent_type,
              parent_account_id,
              parent_app_id,
              transport_type,
              "all"
            ]),
          call_count: 1,
          total_call_time: duration_s,
          total_exclusive_time: duration_s,
          min_call_time: duration_s,
          max_call_time: duration_s
        }
      ]

  def transform({:datastore, datastore, table, operation}, duration_s: duration_s),
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
      }
    ]

  def transform({:external, name}, duration_s: duration_s),
    do: [
      %Metric{
        name: join(["External", name, "all"]),
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }
    ]

  def transform(:external_web, duration_s: duration_s),
    do: [
      %Metric{
        name: :"External/allWeb",
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
      }
    ]

  def transform(:external_other, duration_s: duration_s),
    do: [
      %Metric{
        name: :"External/allOther",
        call_count: 1,
        total_call_time: duration_s,
        total_exclusive_time: duration_s,
        min_call_time: duration_s,
        max_call_time: duration_s
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
      total_call_time: memory_mb
    }

  def transform(:cpu, utilization: utilization),
    do: %Metric{
      name: :"CPU/User Time",
      call_count: 1,
      total_call_time: utilization
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

  def transform({:supportability, harvester}, harvest_size: harvest_size),
    do: [
      %Metric{
        name: join(["Supportability/Elixir/Collector/HarvestSize", inspect(harvester)]),
        call_count: harvest_size
      },
      %Metric{
        name: :"Supportability/Elixir/Harvest",
        call_count: 1
      },
      %Metric{
        name: :"Supportability/Harvest",
        call_count: 1
      }
    ]

  def transform(:supportability, [:dt, :accept, :success]),
    do: [
      %Metric{
        name: :"Supportability/DistributedTrace/AcceptPayload/Success",
        call_count: 1
      }
    ]

  def transform(:supportability, [:dt, :accept, :parse_error]),
    do: [
      %Metric{
        name: :"Supportability/DistributedTrace/AcceptPayload/ParseException",
        call_count: 1
      }
    ]

  def transform(:supportability, [:transaction, :missing_attributes]),
    do: [
      %Metric{
        name: :"Supportability/Transaction/MissingAttributes",
        call_count: 1
      }
    ]

  defp join(segments), do: NewRelic.Util.metric_join(segments)
end
