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

  # Take no action if there is a top-level rescue clause
  def __on_definition__(env, _access, name, _args, _guards, do: _, rescue: _) do
    Logger.warn(
      "Unable to trace `#{inspect(env.module)}.#{name}` due to top-level rescue clause -- please remove @trace"
    )
  end

  def __on_definition__(%{module: module}, access, name, args, guards, do: body) do
    if trace_info = trace_function?(module, name, length(args)) do
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
      start_time = System.system_time()
      start_time_mono = System.monotonic_time()

      {span, previous_span} =
        NewRelic.DistributedTrace.set_current_span(
          label: {unquote(module), unquote(function), unquote(length(args))},
          ref: make_ref()
        )

      try do
        unquote(body)
      after
        end_time_mono = System.monotonic_time()
        NewRelic.DistributedTrace.reset_span(previous: previous_span)

        Tracer.Report.call(
          {unquote(module), unquote(function), unquote(build_call_args(args))},
          unquote(trace_info),
          inspect(self()),
          {span, previous_span || :root},
          {start_time, start_time_mono, end_time_mono}
        )
      end
    end
  end

  def build_function_args(args) when is_list(args), do: Enum.map(args, &build_function_args/1)

  def build_function_args({:\\, _, [arg, _default]}),
    # Don't try to re-declare the default argument
    do: arg

  def build_function_args(arg), do: arg

  def build_call_args(args) do
    Macro.postwalk(args, &rewrite_call_term/1)
  end

  # Strip default arguments
  def rewrite_call_term({:\\, _, [arg, _default]}), do: arg

  # Search for variables on the left side of a pattern match
  # and prefix them with an underscore so they don't end up as
  # unused variables
  def rewrite_call_term({:=, metadata, [pattern, {name, _, context} = value]})
      when is_variable(name, context) do
    ignored_pattern = Macro.postwalk(pattern, &rewrite_match_pattern/1)
    {:=, metadata, [ignored_pattern, value]}
  end

  # Replace ignored variables with an atom
  def rewrite_call_term({name, _, context} = term) when is_variable(name, context) do
    case Atom.to_string(name) do
      "_" <> _rest -> :__ignored__
      _ -> term
    end
  end

  def rewrite_call_term(term), do: term

  def rewrite_match_pattern({name, metadata, context} = term)
      when is_variable(name, context) do
    case Atom.to_string(name) do
      "_" <> _rest -> term
      name_str -> {:"_#{name_str}", metadata, context}
    end
  end

  def rewrite_match_pattern(term), do: term
end
