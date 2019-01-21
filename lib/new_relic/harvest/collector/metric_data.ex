defmodule NewRelic.Harvest.Collector.MetricData do
  # Heper functions for generating Metrics with the correct timeslice values

  @moduledoc false

  alias NewRelic.Metric

  def transform({:transaction, name}, duration_s: duration_s),
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
      }
    ]

  def transform({:other_transaction, name}, duration_s: duration_s),
    do: [
      %Metric{
        name: :OtherTransaction,
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
      },
      %Metric{
        name: :"External/allWeb",
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

  defp join(segments), do: NewRelic.Util.metric_join(segments)
end
