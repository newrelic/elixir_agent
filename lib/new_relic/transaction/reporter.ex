defmodule NewRelic.Transaction.Reporter do
  use GenServer

  alias NewRelic.Util
  alias NewRelic.Util.AttrStore
  alias NewRelic.Transaction
  alias NewRelic.Harvest.Collector
  alias NewRelic.DistributedTrace

  # This GenServer collects and reports Transaction related data
  #  - Transaction Events
  #  - Transaction Metrics
  #  - Span Events
  #  - Transaction Errors
  #  - Transaction Traces
  #  - Custom Attributes

  @moduledoc false

  # Customer Exposed API

  def add_attributes(attrs) when is_list(attrs) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), NewRelic.Util.deep_flatten(attrs))
    end
  end

  def incr_attributes(attrs) do
    if tracking?(self()) do
      AttrStore.incr(__MODULE__, self(), attrs)
    end
  end

  def set_transaction_name(custom_name) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), custom_name: custom_name)
    end
  end

  # Internal Agent API
  #

  def start() do
    Transaction.Monitor.add(self())
    AttrStore.track(__MODULE__, self())

    add_attributes(
      pid: inspect(self()),
      start_time: System.system_time(),
      start_time_mono: System.monotonic_time()
    )
  end

  def fail(%{kind: kind, reason: reason, stack: stack} = error) do
    if tracking?(self()) do
      if NewRelic.Config.feature?(:error_collector) do
        add_attributes(
          error: true,
          transaction_error: {:error, error},
          error_kind: kind,
          error_reason: inspect(reason),
          error_stack: inspect(stack)
        )
      else
        add_attributes(error: true)
      end
    end
  end

  def stop(%Plug.Conn{} = conn) do
    add_attributes(
      plug_name: Transaction.Plug.plug_name(conn),
      end_time_mono: System.monotonic_time()
    )

    complete()
  end

  def add_trace_segment(segment) do
    if tracking?(self()) do
      AttrStore.add(__MODULE__, self(), trace_function_segments: {:list, segment})
    end
  end

  def set_transaction_error(pid, error) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, transaction_error: {:error, error})
    end
  end

  def complete(pid \\ self()) do
    if tracking?(pid) do
      Task.Supervisor.start_child(NewRelic.Transaction.TaskSupervisor, fn ->
        complete_transaction(pid)
      end)
    end
  end

  # Internal Transaction.Monitor API
  #

  def track_spawn(original, pid, timestamp) do
    if tracking?(original) do
      AttrStore.link(
        __MODULE__,
        original,
        pid,
        trace_process_spawns: {:list, {pid, timestamp, original}},
        trace_process_names: {:list, {pid, NewRelic.Util.process_name(pid)}}
      )
    end
  end

  def track_exit(pid, timestamp) do
    if tracking?(pid) do
      AttrStore.add(__MODULE__, pid, trace_process_exits: {:list, {pid, timestamp}})
    end
  end

  def ensure_purge(pid) do
    Process.send_after(
      __MODULE__,
      {:purge, AttrStore.find_root(__MODULE__, pid)},
      Application.get_env(:new_relic_agent, :tx_pid_expire, 2_000)
    )
  end

  # GenServer
  #

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    NewRelic.sample_process()
    AttrStore.new(__MODULE__)
    {:ok, %{timers: %{}}}
  end

  def handle_info({:purge, pid}, state) do
    AttrStore.purge(__MODULE__, pid)
    {:noreply, %{state | timers: Map.drop(state.timers, [pid])}}
  end

  # Helpers
  #

  def tracking?(pid), do: AttrStore.tracking?(__MODULE__, pid)

  def root(pid), do: AttrStore.find_root(__MODULE__, pid)

  def complete_transaction(pid) do
    AttrStore.untrack(__MODULE__, pid)
    tx_attrs = AttrStore.collect(__MODULE__, pid)

    {tx_segments, tx_attrs, tx_error, span_events} = gather_transaction_info(tx_attrs, pid)
    tx_attrs = Map.merge(tx_attrs, NewRelic.Config.automatic_attributes())

    report_transaction_event(tx_attrs)
    report_transaction_trace(tx_attrs, tx_segments)
    report_transaction_error_event(tx_attrs, tx_error)
    report_transaction_metric(tx_attrs)
    report_aggregate(tx_attrs)
    report_caller_metric(tx_attrs)
    report_span_events(span_events)
  end

  defp gather_transaction_info(tx_attrs, pid) do
    tx_attrs
    |> transform_name_attrs
    |> transform_time_attrs
    |> extract_transaction_info(pid)
  end

  defp transform_time_attrs(
         %{start_time: start_time, end_time_mono: end_time_mono, start_time_mono: start_time_mono} =
           tx
       ),
       do:
         tx
         |> Map.drop([:start_time_mono, :end_time_mono])
         |> Map.merge(%{
           start_time: System.convert_time_unit(start_time, :native, :milliseconds),
           end_time:
             System.convert_time_unit(
               start_time + (end_time_mono - start_time_mono),
               :native,
               :milliseconds
             ),
           duration_us:
             System.convert_time_unit(end_time_mono - start_time_mono, :native, :microseconds),
           duration_ms:
             System.convert_time_unit(end_time_mono - start_time_mono, :native, :milliseconds)
         })

  defp transform_name_attrs(%{custom_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{framework_name: name} = tx), do: Map.put(tx, :name, name)
  defp transform_name_attrs(%{plug_name: name} = tx), do: Map.put(tx, :name, name)

  defp extract_transaction_info(tx_attrs, pid) do
    {function_segments, tx_attrs} = Map.pop(tx_attrs, :trace_function_segments, [])
    {process_spawns, tx_attrs} = Map.pop(tx_attrs, :trace_process_spawns, [])
    {process_names, tx_attrs} = Map.pop(tx_attrs, :trace_process_names, [])
    {process_exits, tx_attrs} = Map.pop(tx_attrs, :trace_process_exits, [])
    {tx_error, tx_attrs} = Map.pop(tx_attrs, :transaction_error, nil)

    span_events =
      spawned_process_events(tx_attrs, process_spawns, process_names, process_exits)
      |> add_cowboy_process_event(tx_attrs, pid)

    function_segments =
      function_segments
      |> Enum.map(&transform_time_attrs/1)
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> Enum.group_by(& &1.pid)
      |> Enum.into(%{}, &generate_process_segment_tree(&1))

    top_segment =
      tx_attrs
      |> Map.take([:name, :pid, :start_time, :end_time])
      |> List.wrap()
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> List.first()
      |> Map.put(:id, pid)

    top_segment =
      process_spawns
      |> collect_process_segments(process_names, process_exits)
      |> Enum.map(&transform_trace_time_attrs(&1, tx_attrs.start_time))
      |> Enum.map(&transform_trace_name_attrs/1)
      |> Enum.map(&struct(Transaction.Trace.Segment, &1))
      |> Enum.map(&Map.put(&1, :children, function_segments[&1.pid] || []))
      |> generate_process_tree(root: top_segment)

    top_children = List.wrap(function_segments[inspect(pid)])
    top_segment = Map.update!(top_segment, :children, &(&1 ++ top_children))

    {[top_segment], tx_attrs, tx_error, span_events}
  end

  defp add_cowboy_process_event(spans, %{sampled: true} = tx_attrs, pid) do
    [
      %NewRelic.Span.Event{
        trace_id: tx_attrs[:traceId],
        transaction_id: tx_attrs[:guid],
        sampled: true,
        priority: tx_attrs[:priority],
        category: "generic",
        name: "Cowboy Process #{inspect(pid)}",
        guid: DistributedTrace.generate_guid(pid: pid),
        parent_id: tx_attrs[:parentSpanId],
        timestamp: tx_attrs[:start_time],
        duration: tx_attrs[:duration_ms] / 1000,
        entry_point: true
      }
      | spans
    ]
  end

  defp add_cowboy_process_event(spans, _tx_attrs, _pid), do: spans

  defp generate_segment_tree({pid, segments}) do
    parent_map = Enum.group_by(segments, & &1.parent_id)
    %{children: children} = generate_segment_tree(%{id: nil}, parent_map)
    {pid, children}
  end

  defp generate_segment_tree(leaf, parent_map) when map_size(parent_map) == 0 do
    leaf
  end

  defp generate_segment_tree(parent, parent_map) do
    {children, parent_map} = Map.pop(parent_map, parent.id, [])
    children = Enum.map(children, &generate_segment_tree(&1, parent_map))
    Map.put(parent, :children, children)
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
      duration_s: tx_attrs[:duration_ms] / 1000
    )
  end

  defp report_caller_metric(tx_attrs) do
    NewRelic.report_metric(
      {:caller, "Unknown", "Unknown", "Unknown", "Unknown"},
      duration_s: tx_attrs[:duration_ms] / 1000
    )
  end

  defp spawned_process_events(tx_attrs, process_spawns, process_names, process_exits) do
    process_spawns
    |> collect_process_segments(process_names, process_exits)
    |> Enum.map(&transform_trace_name_attrs/1)
    |> Enum.map(fn proc ->
      %NewRelic.Span.Event{
        trace_id: tx_attrs[:traceId],
        transaction_id: tx_attrs[:guid],
        sampled: tx_attrs[:sampled],
        priority: tx_attrs[:priority],
        category: "generic",
        name: "Process #{proc.name || proc.pid}",
        guid: DistributedTrace.generate_guid(pid: proc.id),
        parent_id: DistributedTrace.generate_guid(pid: proc.parent_id),
        timestamp: proc[:start_time],
        duration: (proc[:end_time] - proc[:start_time]) / 1000
      }
    end)
  end

  defp collect_process_segments(spawns, names, exits) do
    for {pid, start_time, original} <- spawns,
        {^pid, name} <- names,
        {^pid, end_time} <- exits do
      %{
        pid: inspect(pid),
        id: pid,
        parent_id: original,
        name: name,
        start_time: start_time,
        end_time: end_time
      }
    end
  end

  defp transform_trace_time_attrs(
         %{start_time: start_time, end_time: end_time} = attrs,
         trace_start_time
       ),
       do:
         attrs
         |> Map.merge(%{
           relative_start_time: start_time - trace_start_time,
           relative_end_time: end_time - trace_start_time
         })

  defp transform_trace_name_attrs(
         %{
           module: module,
           function: function,
           arity: arity,
           args: args
         } = attrs
       ),
       do:
         attrs
         |> Map.merge(%{
           class_name: "#{function}/#{arity}",
           method_name: nil,
           metric_name: "#{inspect(module)}.#{function}",
           attributes: %{query: inspect(args, charlists: false)}
         })

  defp transform_trace_name_attrs(%{pid: pid, name: name} = attrs),
    do:
      attrs
      |> Map.merge(%{class_name: name || "Process", method_name: nil, metric_name: pid})

  defp generate_process_tree(processes, root: root) do
    parent_map = Enum.group_by(processes, & &1.parent_id)
    generate_tree(root, parent_map)
  end

  defp generate_process_segment_tree({pid, segments}) do
    parent_map = Enum.group_by(segments, & &1.parent_id)
    %{children: children} = generate_tree(%{id: :root}, parent_map)
    {pid, children}
  end

  defp generate_tree(leaf, parent_map) when map_size(parent_map) == 0 do
    leaf
  end

  defp generate_tree(parent, parent_map) do
    {children, parent_map} = Map.pop(parent_map, parent.id, [])
    children = Enum.map(children, &generate_tree(&1, parent_map))
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
      duration_s: tx_attrs[:duration_ms] / 1000
    )
  end

  defp report_caller_metric(tx_attrs) do
    NewRelic.report_metric(
      {:caller, "Unknown", "Unknown", "Unknown", "Unknown"},
      duration_s: tx_attrs[:duration_ms] / 1000
    )
  end

  defp report_span_events(span_events) do
    Enum.each(span_events, &Collector.SpanEvent.Harvester.report_span_event/1)
  end

  defp report_transaction_event(tx_attrs) do
    Collector.TransactionEvent.Harvester.report_event(%Transaction.Event{
      timestamp: tx_attrs.start_time,
      duration: tx_attrs.duration_ms / 1_000,
      name: "WebTransaction#{tx_attrs.name}",
      user_attributes:
        Map.merge(tx_attrs, %{
          request_url: "#{tx_attrs.host}#{tx_attrs.path}"
        })
    })
  end

  defp report_transaction_trace(tx_attrs, tx_segments) do
    Collector.TransactionTrace.Harvester.report_trace(%Transaction.Trace{
      start_time: tx_attrs.start_time,
      metric_name: "WebTransaction#{tx_attrs.name}",
      request_url: "#{tx_attrs.host}#{tx_attrs.path}",
      attributes: %{agentAttributes: tx_attrs},
      segments: tx_segments,
      duration: tx_attrs.duration_ms
    })
  end

  defp report_transaction_error_event(_tx_attrs, nil), do: :ignore

  defp report_transaction_error_event(tx_attrs, {:error, error}) do
    attributes = Map.drop(tx_attrs, [:error, :error_kind, :error_reason, :error_stack])

    {exception_type, exception_reason, exception_stacktrace} =
      Util.Error.normalize(error.reason, error.stack)

    expected = parse_error_expected(error.reason)

    Collector.ErrorTrace.Harvester.report_error(%NewRelic.Error.Trace{
      timestamp: tx_attrs.start_time / 1_000,
      error_type: inspect(exception_type),
      message: exception_reason,
      expected: expected,
      stack_trace: exception_stacktrace,
      transaction_name: "WebTransaction#{tx_attrs.name}",
      request_uri: "#{tx_attrs.host}#{tx_attrs.path}",
      user_attributes:
        Map.merge(attributes, %{
          process: error[:process]
        })
    })

    Collector.TransactionErrorEvent.Harvester.report_error(%NewRelic.Error.Event{
      timestamp: tx_attrs.start_time / 1_000,
      error_class: inspect(exception_type),
      error_message: exception_reason,
      expected: expected,
      transaction_name: "WebTransaction#{tx_attrs.name}",
      http_response_code: tx_attrs.status,
      request_method: tx_attrs.request_method,
      user_attributes:
        Map.merge(attributes, %{
          process: error[:process],
          stacktrace: Enum.join(exception_stacktrace, "\n")
        })
    })

    unless expected do
      NewRelic.report_metric({:supportability, :error_event}, error_count: 1)
      NewRelic.report_metric(:error, error_count: 1)
    end
  end

  defp report_aggregate(tx) do
    NewRelic.report_aggregate(%{type: :Transaction, name: tx[:name]}, %{
      duration_us: tx.duration_us,
      duration_ms: tx.duration_ms,
      call_count: 1
    })
  end

  def report_transaction_metric(tx) do
    NewRelic.report_metric({:transaction, tx.name}, duration_s: tx.duration_ms / 1_000)
  end

  defp parse_error_expected(%{expected: true}), do: true
  defp parse_error_expected(_), do: false
end
