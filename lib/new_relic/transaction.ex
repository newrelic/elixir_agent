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
    NewRelic.Transaction.Reporter.stop(error)
  end
end
