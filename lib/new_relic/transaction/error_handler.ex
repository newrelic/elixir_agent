defmodule NewRelic.Transaction.ErrorHandler do
  # This macro injects a Plug.ErrorHandler that will ensure that
  # requests that end in an error still get reported

  @moduledoc false

  defmacro __using__(_) do
    quote do
      use Plug.ErrorHandler

      def handle_errors(conn, error) do
        NewRelic.Transaction.handle_errors(conn, error)
      end
    end
  end
end
