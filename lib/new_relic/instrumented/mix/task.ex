defmodule NewRelic.Instrumented.Mix.Task do
  defmacro __using__(_args) do
    quote do
      case Module.get_attribute(__MODULE__, :behaviour) do
        [Mix.Task] ->
          @before_compile NewRelic.Instrumented.Mix.Task

        _ ->
          require Logger

          Logger.error("[New Relic] Unable to instrument #{inspect(__MODULE__)} since it isn't a Mix.Task")
      end
    end
  end

  defmacro __before_compile__(%{module: module}) do
    Module.make_overridable(module, run: 1)

    quote do
      def run(args) do
        Application.ensure_all_started(:new_relic_agent)
        NewRelic.Harvest.Collector.AgentRun.ensure_initialized()

        "Elixir.Mix.Tasks." <> task_name = Atom.to_string(__MODULE__)
        NewRelic.start_transaction("Mix.Task", task_name)

        super(args)

        NewRelic.stop_transaction()
        Application.stop(:new_relic_agent)
      end
    end
  end
end
