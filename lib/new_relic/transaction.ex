defmodule NewRelic.Transaction do
  @moduledoc """
  Transaction Reporting

  To enable Transaction reporting, you must instrument your Plug pipeline with a single line.
  The `NewRelic.Transaction` macro injects the required plugs to wire up automatic
  Transaction reporting.

  Be sure to `use` this as early in your Plug pipeline as possible to ensure the most
  accurate response times.

  ```elixir
  defmodule MyApp do
    use Plug.Router
    use NewRelic.Transaction
    # ...
  end
  ```

  To ignore reporting the current transaction, call:
  ```elixir
  NewRelic.ignore_transaction()
  ```

  Inside a Transaction, the agent will track work across processes that are spawned as
  well as work done inside a Task Supervisor. When using `Task.Supervisor.async_nolink`
  you can signal to the agent not to track the work done inside the Task, which will
  exclude it from the current Transaction. To do this, send in an additional option:

  ```elixir
  Task.Supervisor.async_nolink(
    MyTaskSupervisor,
    fn -> do_work() end,
    new_relic: :no_track
  )
  ```
  """

  defmacro __using__(_) do
    quote do
      plug(NewRelic.Transaction.Plug)
      plug(NewRelic.DistributedTrace.Plug)
      use NewRelic.Transaction.ErrorHandler
    end
  end

  @doc """
  If you send a custom error response in your own `Plug.ErrorHandler`,
  you **MUST** manually alert the agent of the error!

  ```elixir
  defmodule MyPlug do
    # ...
    use Plug.ErrorHandler
    def handle_errors(conn, error) do
      NewRelic.Transaction.handle_errors(conn, error)
      send_resp(conn, 500, "Oops!")
    end
  end
  ```
  """
  def handle_errors(conn, error) do
    NewRelic.DistributedTrace.Tracker.cleanup(self())
    NewRelic.Transaction.Plug.add_stop_attrs(conn)
    NewRelic.Transaction.Reporter.fail(error)
    NewRelic.Transaction.Reporter.complete(self(), :async)
  end

  @doc false
  def start_transaction(category, name) do
    NewRelic.Transaction.Reporter.start_other_transaction(category, name)

    NewRelic.DistributedTrace.generate_new_context()
    |> NewRelic.DistributedTrace.track_transaction(transport_type: "Other")

    :ok
  end

  @doc false
  def stop_transaction() do
    NewRelic.DistributedTrace.Tracker.cleanup(self())
    NewRelic.Transaction.Reporter.complete(self(), :sync)

    :ok
  end

  @doc false
  def ignore_transaction() do
    NewRelic.Transaction.Reporter.ignore_transaction()
    NewRelic.DistributedTrace.Tracker.cleanup(self())
  end
end
