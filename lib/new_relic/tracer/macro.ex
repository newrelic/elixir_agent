defmodule NewRelic.Tracer.Macro do
  require Logger

  # Function Tracer Macros
  #   1) __on_definition__: When a function is defined & it's been marked to @trace, we
  #        store information about the function in module attributes
  #   2) __before_compile__: We take the list of functions that are marked to @trace and:
  #        a) Make them overridable
  #        b) Re-define them with our tracing code wrapped around the original logic

  @moduledoc false

  alias NewRelic.Tracer

  defguardp is_variable(name, context)
            when is_atom(name) and (is_atom(context) or is_nil(context))

  # Take no action on the definition of a function head
  def __on_definition__(_env, _access, _name, _args, _guards, nil), do: nil
  def __on_definition__(_env, _access, _name, _args, _guards, []), do: nil

  def __on_definition__(%{module: module}, access, name, args, guards, do: body) do
    if trace_info =
         trace_function?(module, name, length(args))
         |> trace_deprecated?(module, name) do
      Module.put_attribute(module, :nr_tracers, %{
        module: module,
        access: access,
        function: name,
        args: args,
        guards: guards,
        body: body,
        trace_info: trace_info
      })

      Module.put_attribute(module, :nr_last_tracer, {name, length(args), trace_info})
      Module.delete_attribute(module, :trace)
    end
  end

  # Take no action if there are other function-level clauses
  def __on_definition__(%{module: module}, _access, name, args, _guards, clauses) do
    if trace_function?(module, name, length(args)) do
      found =
        clauses
        |> Keyword.drop([:do])
        |> Keyword.keys()
        |> Enum.map(&"`#{&1}`")
        |> Enum.join(", ")

      Logger.warning(
        "[New Relic] Unable to trace `#{inspect(module)}.#{name}/#{length(args)}` " <>
          "due to additional function-level clauses: #{found} -- please remove @trace"
      )

      Module.delete_attribute(module, :trace)
    end
  end

  defmacro __before_compile__(%{module: module}) do
    Module.delete_attribute(module, :nr_last_tracer)
    Module.make_overridable(module, function_specs(module))

    quote do
      (unquote_splicing(function_definitions(module)))
    end
  end

  def trace_function?(module, name, arity),
    do:
      trace_function?(:via_annotation, module) ||
        trace_function?(:via_multiple_heads, module, name, arity)

  def trace_function?(:via_annotation, module), do: Module.get_attribute(module, :trace)

  def trace_function?(:via_multiple_heads, module, name, arity) do
    case Module.get_attribute(module, :nr_last_tracer) do
      {^name, ^arity, trace_info} -> trace_info
      _ -> false
    end
  end

  def trace_deprecated?({_, category: :datastore}, module, name) do
    Logger.warning(
      "[New Relic] Trace `:datastore` deprecated in favor of automatic ecto instrumentation. " <>
        "Please remove @trace from #{inspect(module)}.#{name}"
    )

    false
  end

  def trace_deprecated?(trace_info, _, _) do
    trace_info
  end

  def function_specs(module),
    do:
      module
      |> Module.get_attribute(:nr_tracers)
      |> Enum.map(&traced_function_spec/1)
      |> Enum.uniq()

  def function_definitions(module),
    do:
      module
      |> Module.get_attribute(:nr_tracers)
      |> Enum.map(&traced_function_definition/1)
      |> Enum.reverse()

  def traced_function_spec(%{function: function, args: args}), do: {function, length(args)}

  def traced_function_definition(%{
        module: module,
        access: :def,
        function: function,
        args: args,
        body: body,
        guards: [],
        trace_info: trace_info
      }) do
    quote do
      def unquote(function)(unquote_splicing(build_function_args(args))) do
        unquote(traced_function_body(body, module, function, args, trace_info))
      end
    end
  end

  def traced_function_definition(%{
        module: module,
        access: :def,
        function: function,
        args: args,
        body: body,
        guards: guards,
        trace_info: trace_info
      }) do
    quote do
      def unquote(function)(unquote_splicing(build_function_args(args)))
          when unquote_splicing(guards) do
        unquote(traced_function_body(body, module, function, args, trace_info))
      end
    end
  end

  def traced_function_definition(%{
        module: module,
        access: :defp,
        function: function,
        args: args,
        body: body,
        guards: [],
        trace_info: trace_info
      }) do
    quote do
      defp unquote(function)(unquote_splicing(build_function_args(args))) do
        unquote(traced_function_body(body, module, function, args, trace_info))
      end
    end
  end

  def traced_function_definition(%{
        module: module,
        access: :defp,
        function: function,
        args: args,
        body: body,
        guards: guards,
        trace_info: trace_info
      }) do
    quote do
      defp unquote(function)(unquote_splicing(build_function_args(args)))
           when unquote_splicing(guards) do
        unquote(traced_function_body(body, module, function, args, trace_info))
      end
    end
  end

  def traced_function_body(body, module, function, args, trace_info) do
    quote do
      current_ref = make_ref()

      {span, previous_span, previous_span_attrs} =
        NewRelic.DistributedTrace.set_current_span(
          label: {unquote(module), unquote(function), unquote(length(args))},
          ref: current_ref
        )

      start_time = System.system_time()
      start_time_mono = System.monotonic_time()
      [reductions: start_reductions] = Process.info(self(), [:reductions])

      try do
        unquote(body)
      rescue
        exception ->
          message = NewRelic.Util.Error.format_reason(:error, exception)
          NewRelic.DistributedTrace.set_span(:error, message: message)

          reraise exception, __STACKTRACE__
      catch
        :exit, value ->
          message = NewRelic.Util.Error.format_reason(:exit, value)
          NewRelic.DistributedTrace.set_span(:error, message: "(EXIT) #{message}")

          exit(value)
      after
        end_time_mono = System.monotonic_time()
        [reductions: end_reductions] = Process.info(self(), [:reductions])

        parent_ref =
          case previous_span do
            {_, ref} -> ref
            nil -> :root
          end

        duration_ms =
          System.convert_time_unit(end_time_mono - start_time_mono, :native, :microsecond) / 1000

        duration_acc = Process.get({:nr_duration_acc, parent_ref}, 0)
        Process.put({:nr_duration_acc, parent_ref}, duration_acc + duration_ms)

        child_duration_ms = Process.delete({:nr_duration_acc, current_ref}) || 0
        if parent_ref == :root, do: Process.delete({:nr_duration_acc, parent_ref})

        reductions = end_reductions - start_reductions

        Tracer.Report.call(
          {unquote(module), unquote(function), unquote(build_call_args(args))},
          unquote(trace_info),
          inspect(self()),
          {span, previous_span || :root},
          {start_time, start_time_mono, end_time_mono, child_duration_ms, reductions}
        )

        NewRelic.DistributedTrace.reset_span(
          previous_span: previous_span,
          previous_span_attrs: previous_span_attrs
        )
      end
    end
  end

  def build_function_args(args) when is_list(args), do: Enum.map(args, &build_function_args/1)

  # Don't try to re-declare the default argument
  def build_function_args({:\\, _, [arg, _default]}),
    do: arg

  def build_function_args(arg), do: arg

  def build_call_args(args) do
    Macro.postwalk(args, &rewrite_call_term/1)
  end

  # Unwrap Struct literals into a Map, they can't be re-referenced directly due to enforced_keys
  @struct_keys [:__aliases__, :__MODULE__]
  def rewrite_call_term({:%, line, [{key, _, _} = struct, {:%{}, _, members}]})
      when key in @struct_keys do
    {:%{}, line, [{:__struct__, struct}] ++ members}
  end

  # Strip default arguments
  def rewrite_call_term({:\\, _, [arg, _default]}), do: arg

  # Drop the de-structuring side of a pattern match
  def rewrite_call_term({:=, _, [left, right]}) do
    cond do
      :__ignored__ == left -> right
      :__ignored__ == right -> left
      is_variable?(right) -> right
      is_variable?(left) -> left
    end
  end

  # Replace ignored variables with an atom
  def rewrite_call_term({name, _, context} = term) when is_variable(name, context) do
    case Atom.to_string(name) do
      "__" <> _special_form -> term
      "_" <> _ignored_var -> :__ignored__
      _ -> term
    end
  end

  def rewrite_call_term(term), do: term

  def is_variable?({name, _, context}) when is_variable(name, context), do: true
  def is_variable?(_term), do: false
end
