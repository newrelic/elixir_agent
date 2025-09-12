defmodule NewRelic.Transaction.Complete do
  @moduledoc false

  alias NewRelic.Util
  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace
  alias NewRelic.Transaction

  def run(tx_attrs, pid) do
    {tx_segments, tx_attrs, tx_error_info, span_events, apdex, tx_metrics} =
      tx_attrs
      |> transform_name_attrs
      |> transform_time_attrs
      |> identify_transaction_type
      |> transform_queue_duration
      |> add_host_display_name(NewRelic.Config.host_display_name())
      |> extract_transaction_info(pid)

    report_transaction_event(tx_attrs)
    report_transaction_trace(tx_attrs, tx_segments)
    report_transaction_error_event(tx_attrs, tx_error_info)
    report_http_dispatcher_metric(tx_attrs)
    report_transaction_metric(tx_attrs)
    report_queue_time_metric(tx_attrs)
    report_transaction_metrics(tx_attrs, tx_metrics)
    report_caller_metric(tx_attrs)
    report_apdex_metric(apdex)
    report_span_events(span_events)
  end

  defp transform_name_attrs(%{custom_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{framework_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{phoenix_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{plug_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{other_transaction_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(tx), do: Map.put(tx, :name, "Unknown/Unknown")

  defp identify_transaction_type(%{other_transaction_name: _} = tx),
    do: Map.put(tx, :transactionType, :Other)

  defp identify_transaction_type(tx),
    do: Map.put(tx, :transactionType, :Web)

  # instrumentation reports time via start_time :: native and duration :: native
  defp transform_time_attrs(%{start_time: start_time, duration: duration} = tx) do
    start_time_ms = System.convert_time_unit(start_time, :native, :millisecond)
    duration_us = System.convert_time_unit(duration, :native, :microsecond)
    duration_ms = duration_us / 1000
    duration_s = duration_ms / 1000

    tx
    |> Map.drop([:system_time, :duration, :start_time_mono, :end_time_mono])
    |> Map.merge(%{
      start_time: start_time_ms,
      end_time: start_time_ms + duration_ms,
      duration_us: duration_us,
      duration_ms: duration_ms,
      duration_s: duration_s
    })
  end

  # sidecar reports time via system_time :: native, start_time_mono :: native, end_time_mono :: native
  defp transform_time_attrs(
         %{system_time: system_time, end_time_mono: end_time_mono, start_time_mono: start_time_mono} = tx
       ) do
    start_time_ms = System.convert_time_unit(system_time, :native, :millisecond)
    duration_us = System.convert_time_unit(end_time_mono - start_time_mono, :native, :microsecond)
    duration_ms = duration_us / 1000
    duration_s = duration_ms / 1000

    tx
    |> Map.drop([:system_time, :duration, :start_time_mono, :end_time_mono])
    |> Map.merge(%{
      start_time: start_time_ms,
      end_time: start_time_ms + duration_ms,
      duration_us: duration_us,
      duration_ms: duration_ms,
      duration_s: duration_s
    })
  end

  defp transform_time_attrs(%{start_time: _, end_time: _} = tx) do
    tx
  end

  defp transform_queue_duration(%{request_start_s: request_start_s, start_time: start_time} = tx) do
    start_time_s = start_time / 1000.0
    queue_duration = max(0, start_time_s - request_start_s)

    tx
    |> Map.drop([:request_start_s])
    |> Map.put(:queueDuration, queue_duration)
  end

  defp transform_queue_duration(tx), do: tx

  defp add_host_display_name(tx, nil), do: tx

  defp add_host_display_name(tx, host_display_name),
    do: Map.put(tx, :"host.displayName", host_display_name)

  defp extract_transaction_info(tx_attrs, pid) do
    {function_segments, tx_attrs} = Map.pop(tx_attrs, :function_segments, [])
    {process_spawns, tx_attrs} = Map.pop(tx_attrs, :process_spawns, [])
    {process_exits, tx_attrs} = Map.pop(tx_attrs, :process_exits, [])
    {tx_error, tx_attrs} = Map.pop(tx_attrs, :transaction_error, nil)
    {tx_metrics, tx_attrs} = Map.pop(tx_attrs, :transaction_metrics, [])

    function_segments =
      function_segments
      |> Enum.map(&transform_time_attrs/1)
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> Enum.group_by(& &1.pid)
      |> Map.new(&generate_segment_tree(&1))

    root_process_segment =
      tx_attrs
      |> Map.take([:name, :pid, :start_time, :end_time])
      |> List.wrap()
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> List.first()
      |> Map.put(:id, pid)

    process_segments =
      process_spawns
      |> collect_process_segments(process_exits)
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> Enum.reject(&(&1.relative_start_time == &1.relative_end_time))
      |> Enum.sort_by(& &1.relative_start_time)

    {merged_process_function_segments, remaining_function_segments} =
      merge_process_function_segments([root_process_segment | process_segments], function_segments)

    segment_tree = generate_process_tree(merged_process_function_segments, root: root_process_segment)

    top_children = List.wrap(function_segments[inspect(pid)])
    stray_children = Map.values(remaining_function_segments) |> List.flatten()

    segment_tree = Map.update!(segment_tree, :children, &(&1 ++ top_children ++ stray_children))

    tx_error_info =
      case tx_error do
        nil ->
          nil

        {:error, error} ->
          expected = parse_error_expected(error.reason)
          {type, reason, stacktrace} = Util.Error.normalize(error.kind, error.reason, error.stack)

          {:error, error, type, reason, stacktrace, expected}
      end

    span_events =
      extract_span_events(
        NewRelic.Config.feature(:infinite_tracing),
        tx_attrs,
        pid,
        process_spawns,
        process_exits,
        tx_error_info
      )

    apdex = calculate_apdex(tx_attrs, tx_error)

    concurrent_process_time_ms =
      process_segments
      |> Enum.map(&(&1.relative_end_time - &1.relative_start_time))
      |> Enum.sum()

    tx_attrs =
      tx_attrs
      |> Map.merge(NewRelic.Config.automatic_attributes())
      |> Map.put(:"nr.apdexPerfZone", Util.Apdex.label(apdex))
      |> Map.put(:total_time_s, total_time_s(tx_attrs, concurrent_process_time_ms))
      |> Map.put(:process_spawns, length(process_spawns))

    {[segment_tree], tx_attrs, tx_error_info, span_events, apdex, tx_metrics}
  end

  defp total_time_s(%{transactionType: :Web, "http.server": "cowboy"}, concurrent_process_time_ms) do
    # Cowboy request process duration is already included in concurrent time
    concurrent_process_time_ms / 1000
  end

  defp total_time_s(tx_attrs, concurrent_process_time_ms) do
    (tx_attrs.duration_ms + concurrent_process_time_ms) / 1000
  end

  defp extract_span_events(:infinite, tx_attrs, pid, spawns, exits, tx_error_info) do
    spawned_process_span_events(tx_attrs, spawns, exits)
    |> add_spansactions(tx_attrs, pid, tx_error_info)
  end

  defp extract_span_events(:sampling, %{sampled: true} = tx_attrs, pid, spawns, exits, tx_error_info) do
    spawned_process_span_events(tx_attrs, spawns, exits)
    |> add_spansactions(tx_attrs, pid, tx_error_info)
  end

  defp extract_span_events(_trace_mode, _tx_attrs, _pid, _spawns, _exits, _tx_error_info) do
    []
  end

  defp calculate_apdex(%{transactionType: :Other}, _error) do
    :ignore
  end

  defp calculate_apdex(_tx_attrs, {:error, _error}) do
    :frustrating
  end

  defp calculate_apdex(%{duration_s: duration_s}, nil) do
    Util.Apdex.calculate(duration_s, apdex_t())
  end

  @spansaction_exclude_attrs [
    :guid,
    :traceId,
    :start_time,
    :end_time,
    :parentId,
    :parentSpanId,
    :sampled,
    :priority,
    :tracingVendors,
    :trustedParentId,
    :error
  ]
  defp add_spansactions(spans, tx_attrs, pid, tx_error_info) do
    error_attrs =
      case tx_error_info do
        {:error, _error, type, reason, _stack, false = _expected} ->
          %{"error.class": type, "error.message": reason}

        {:error, _error, type, reason, _stack, true = _expected} ->
          %{"error.class": type, "error.message": reason, "error.expected": true}

        _ ->
          %{}
      end

    [
      %NewRelic.Span.Event{
        guid: tx_attrs[:guid],
        transaction_id: tx_attrs[:guid],
        trace_id: tx_attrs[:traceId],
        parent_id: tx_attrs[:parentSpanId],
        name: tx_attrs[:name],
        sampled: tx_attrs[:sampled],
        priority: tx_attrs[:priority],
        category: "generic",
        entry_point: true,
        timestamp: tx_attrs[:start_time],
        duration: tx_attrs[:duration_s],
        category_attributes:
          tx_attrs
          |> Map.drop(@spansaction_exclude_attrs)
          |> Map.merge(error_attrs)
          |> Map.merge(NewRelic.Config.automatic_attributes())
          |> Map.merge(%{
            "transaction.name": Util.metric_join(["#{tx_attrs[:transactionType]}Transaction", tx_attrs.name]),
            tracingVendors: tx_attrs[:tracingVendors],
            trustedParentId: tx_attrs[:trustedParentId]
          })
      },
      %NewRelic.Span.Event{
        guid: DistributedTrace.generate_guid(pid: pid),
        transaction_id: tx_attrs[:guid],
        trace_id: tx_attrs[:traceId],
        category: "generic",
        name: "Transaction Root Process",
        sampled: tx_attrs[:sampled],
        priority: tx_attrs[:priority],
        parent_id: tx_attrs[:guid],
        timestamp: tx_attrs[:start_time],
        duration: tx_attrs[:duration_s],
        category_attributes: %{pid: inspect(pid)}
      }
      | spans
    ]
  end

  defp spawned_process_span_events(tx_attrs, process_spawns, process_exits) do
    process_spawns
    |> collect_process_segments(process_exits)
    |> Enum.map(&transform_trace_name_attrs/1)
    |> Enum.map(fn proc ->
      %NewRelic.Span.Event{
        trace_id: tx_attrs[:traceId],
        transaction_id: tx_attrs[:guid],
        sampled: tx_attrs[:sampled],
        priority: tx_attrs[:priority],
        category: "generic",
        name: proc.name || "Process",
        guid: DistributedTrace.generate_guid(pid: proc.id),
        parent_id:
          case proc.parent_id do
            {pid, label, ref} -> DistributedTrace.generate_guid(pid: pid, label: label, ref: ref)
            pid -> DistributedTrace.generate_guid(pid: pid)
          end,
        timestamp: proc[:start_time],
        duration: (proc[:end_time] - proc[:start_time]) / 1000,
        category_attributes: %{
          pid: proc.pid
        }
      }
    end)
  end

  defp collect_process_segments(spawns, exits) do
    for {pid, start_time, original, name} <- spawns,
        {^pid, end_time} <- exits do
      %{
        pid: inspect(pid),
        id: pid,
        parent_id: original,
        name: name,
        start_time: start_time,
        attributes: %{
          exclusive_duration_millis: 0,
          async_wait: true
        },
        end_time: end_time
      }
    end
  end

  defp transform_trace_time_attrs(
         %{start_time: start_time, end_time: end_time} = attrs,
         trace_start_time
       ) do
    attrs
    |> Map.merge(%{
      relative_start_time: start_time - trace_start_time,
      relative_end_time: end_time - trace_start_time
    })
  end

  defp transform_trace_name_attrs(
         %{
           primary_name: metric_name,
           secondary_name: class_name,
           attributes: attributes
         } = attrs
       ) do
    attrs
    |> Map.merge(%{
      class_name: class_name,
      method_name: nil,
      metric_name: metric_name,
      attributes: attributes
    })
  end

  defp transform_trace_name_attrs(
         %{
           module: module,
           function: function,
           arity: arity,
           args: args
         } = attrs
       ) do
    attrs
    |> Map.merge(%{
      class_name: "#{function}/#{arity}",
      method_name: nil,
      metric_name: "#{inspect(module)}.#{function}",
      attributes: %{query: args}
    })
  end

  defp transform_trace_name_attrs(%{pid: pid, name: name} = attrs) do
    attrs
    |> Map.merge(%{class_name: name || "Process", method_name: nil, metric_name: pid})
  end

  defp merge_process_function_segments(process_segments, function_segments) do
    Enum.reduce(
      process_segments,
      {[], function_segments},
      &reduce_process_function_segments/2
    )
  end

  defp reduce_process_function_segments(
         process_segment,
         {merged_segments, remaining_function_segments}
       ) do
    {process_function_segments, remaining_function_segments} =
      Map.pop(remaining_function_segments, process_segment.pid, [])

    merged_process_segment = Map.put(process_segment, :children, process_function_segments)

    {[merged_process_segment | merged_segments], remaining_function_segments}
  end

  defp generate_process_tree(processes, root: root) do
    parent_map =
      Enum.group_by(processes, fn
        %{parent_id: {pid, _label, _ref}} -> pid
        %{parent_id: pid} -> pid
      end)

    generate_tree(root, parent_map)
  end

  defp generate_segment_tree({pid, segments}) do
    parent_map = Enum.group_by(segments, & &1.parent_id)
    %{children: children} = generate_tree(%{id: :root}, parent_map)
    {pid, children}
  end

  defp generate_tree(leaf, parent_map) when map_size(parent_map) == 0 do
    leaf
  end

  defp generate_tree(parent, parent_map) do
    {children, parent_map} = Map.pop(parent_map, parent.id, [])

    children =
      children
      |> Enum.sort_by(& &1.relative_start_time)
      |> Enum.map(&generate_tree(&1, parent_map))

    Map.update(parent, :children, children, &(&1 ++ children))
  end

  defp report_caller_metric(
         %{
           "parent.type": parent_type,
           "parent.account": parent_account_id,
           "parent.app": parent_app_id,
           "parent.transportType": transport_type
         } = tx_attrs
       ) do
    NewRelic.report_metric(
      {:caller, parent_type, parent_account_id, parent_app_id, transport_type},
      duration_s: tx_attrs.duration_s
    )
  end

  defp report_caller_metric(tx_attrs) do
    NewRelic.report_metric(
      {:caller, "Unknown", "Unknown", "Unknown", "Unknown"},
      duration_s: tx_attrs.duration_s
    )
  end

  defp report_span_events(span_events) do
    Enum.each(span_events, &NewRelic.report_span/1)
  end

  defp report_transaction_event(%{transactionType: :Other} = tx_attrs) do
    Collector.TransactionEvent.Harvester.report_event(%Transaction.Event{
      timestamp: tx_attrs.start_time,
      duration: tx_attrs.duration_s,
      total_time: tx_attrs.total_time_s,
      name: Util.metric_join(["OtherTransaction", tx_attrs.name]),
      user_attributes: tx_attrs
    })
  end

  defp report_transaction_event(tx_attrs) do
    Collector.TransactionEvent.Harvester.report_event(%Transaction.Event{
      timestamp: tx_attrs.start_time,
      duration: tx_attrs.duration_s,
      total_time: tx_attrs.total_time_s,
      name: Util.metric_join(["WebTransaction", tx_attrs.name]),
      user_attributes:
        Map.merge(tx_attrs, %{
          request_url: "#{tx_attrs.host}#{tx_attrs.path}"
        })
    })
  end

  defp report_transaction_trace(%{transactionType: :Other} = tx_attrs, tx_segments) do
    Collector.TransactionTrace.Harvester.report_trace(%Transaction.Trace{
      start_time: tx_attrs.start_time,
      metric_name: Util.metric_join(["OtherTransaction", tx_attrs.name]),
      request_url: "/Unknown",
      attributes: %{agentAttributes: tx_attrs},
      segments: tx_segments,
      duration: tx_attrs.duration_ms
    })
  end

  defp report_transaction_trace(tx_attrs, tx_segments) do
    Collector.TransactionTrace.Harvester.report_trace(%Transaction.Trace{
      start_time: tx_attrs.start_time,
      metric_name: Util.metric_join(["WebTransaction", tx_attrs.name]),
      request_url: "#{tx_attrs.host}#{tx_attrs.path}",
      attributes: %{agentAttributes: tx_attrs},
      segments: tx_segments,
      duration: tx_attrs.duration_ms
    })
  end

  defp report_transaction_error_event(_tx_attrs, nil), do: :ignore

  defp report_transaction_error_event(
         %{name: tx_name, transactionType: type} = tx_attrs,
         {:error, error, exception_type, exception_reason, exception_stacktrace, expected}
       ) do
    attributes = Map.drop(tx_attrs, [:error, :"error.kind", :"error.reason", :"error.stack"])

    report_error_trace(
      tx_attrs,
      exception_type,
      exception_reason,
      expected,
      exception_stacktrace,
      attributes,
      error
    )

    report_error_event(
      tx_attrs,
      exception_type,
      exception_reason,
      expected,
      exception_stacktrace,
      attributes,
      error
    )

    unless expected do
      NewRelic.report_metric({:supportability, :error_event}, error_count: 1)
      NewRelic.report_metric({:error, tx_name}, type: type, error_count: 1)
    end
  end

  defp report_error_trace(
         %{transactionType: :Other} = tx_attrs,
         exception_type,
         exception_reason,
         expected,
         exception_stacktrace,
         attributes,
         error
       ) do
    Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
      timestamp: tx_attrs.start_time / 1_000,
      error_type: exception_type,
      message: exception_reason,
      expected: expected,
      stack_trace: exception_stacktrace,
      transaction_name: Util.metric_join(["OtherTransaction", tx_attrs.name]),
      agent_attributes: %{},
      user_attributes: Map.merge(attributes, %{process: error[:process]})
    })
  end

  defp report_error_trace(
         tx_attrs,
         exception_type,
         exception_reason,
         expected,
         exception_stacktrace,
         attributes,
         error
       ) do
    Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
      timestamp: tx_attrs.start_time / 1_000,
      error_type: exception_type,
      message: exception_reason,
      expected: expected,
      stack_trace: exception_stacktrace,
      transaction_name: Util.metric_join(["WebTransaction", tx_attrs.name]),
      agent_attributes: %{
        request_uri: "#{tx_attrs.host}#{tx_attrs.path}"
      },
      user_attributes: Map.merge(attributes, %{process: error[:process]})
    })
  end

  defp report_error_event(
         %{transactionType: :Other} = tx_attrs,
         exception_type,
         exception_reason,
         expected,
         exception_stacktrace,
         attributes,
         error
       ) do
    Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
      timestamp: tx_attrs.start_time / 1_000,
      error_class: exception_type,
      error_message: exception_reason,
      expected: expected,
      transaction_name: Util.metric_join(["OtherTransaction", tx_attrs.name]),
      agent_attributes: %{},
      user_attributes:
        Map.merge(attributes, %{
          process: error[:process],
          stacktrace: Enum.join(exception_stacktrace, "\n")
        })
    })
  end

  defp report_error_event(
         tx_attrs,
         exception_type,
         exception_reason,
         expected,
         exception_stacktrace,
         attributes,
         error
       ) do
    Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
      timestamp: tx_attrs.start_time / 1_000,
      error_class: exception_type,
      error_message: exception_reason,
      expected: expected,
      transaction_name: Util.metric_join(["WebTransaction", tx_attrs.name]),
      agent_attributes: %{
        http_response_code: tx_attrs[:status],
        request_method: tx_attrs[:request_method]
      },
      user_attributes:
        Map.merge(attributes, %{
          process: error[:process],
          stacktrace: Enum.join(exception_stacktrace, "\n")
        })
    })
  end

  def report_transaction_metric(tx) do
    NewRelic.report_metric({:transaction, tx.name},
      type: tx.transactionType,
      duration_s: tx.duration_s,
      total_time_s: tx.total_time_s
    )
  end

  def report_queue_time_metric(%{queueDuration: duration_s}) do
    NewRelic.report_metric(:queue_time, duration_s: duration_s)
  end

  def report_queue_time_metric(_), do: :ignore

  def report_http_dispatcher_metric(%{transactionType: :Web} = tx) do
    NewRelic.report_metric(:http_dispatcher, duration_s: tx.duration_s)
  end

  def report_http_dispatcher_metric(_), do: :ignore

  def report_transaction_metrics(tx, tx_metrics) when is_list(tx_metrics) do
    Enum.each(tx_metrics, &report_transaction_metrics(tx, &1))
  end

  def report_transaction_metrics(%{transactionType: type}, {:external, duration_s}) do
    NewRelic.report_metric(:external, type: type, duration_s: duration_s)
  end

  def report_transaction_metrics(
        %{name: tx_name, transactionType: type},
        {{:external, url, component, method}, duration_s: duration_s}
      ) do
    NewRelic.report_metric(
      {:external, url, component, method},
      type: type,
      scope: tx_name,
      duration_s: duration_s
    )
  end

  def report_transaction_metrics(
        %{name: tx_name, transactionType: type},
        {{:external, function_name}, duration_s: duration_s}
      ) do
    NewRelic.report_metric(
      {:external, function_name},
      type: type,
      scope: tx_name,
      duration_s: duration_s
    )
  end

  def report_transaction_metrics(
        %{name: tx_name, transactionType: type},
        {{:function, function_name}, duration_s: duration_s, exclusive_time_s: exclusive_time_s}
      ) do
    NewRelic.report_metric({:function, function_name},
      type: type,
      scope: tx_name,
      duration_s: duration_s,
      exclusive_time_s: exclusive_time_s
    )
  end

  def report_transaction_metrics(
        %{name: tx_name, transactionType: type},
        {{:datastore, datastore, table, operation}, duration_s: duration_s}
      ) do
    NewRelic.report_metric(
      {:datastore, datastore, table, operation},
      type: type,
      scope: tx_name,
      duration_s: duration_s
    )
  end

  def report_transaction_metrics(
        %{name: tx_name, transactionType: type},
        {{:datastore, datastore, operation}, duration_s: duration_s}
      ) do
    NewRelic.report_metric(
      {:datastore, datastore, operation},
      type: type,
      scope: tx_name,
      duration_s: duration_s
    )
  end

  def report_apdex_metric(:ignore), do: :ignore

  def report_apdex_metric(apdex) do
    NewRelic.report_metric(:apdex, apdex: apdex, threshold: apdex_t())
  end

  @default_apdex_t 2.0
  def apdex_t, do: Collector.AgentRun.apdex_t() || @default_apdex_t

  defp parse_error_expected(%{expected: true}), do: true
  defp parse_error_expected(_), do: false
end
