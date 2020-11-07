defmodule NewRelic.OtherTransaction do
  @moduledoc false

  def start_transaction(category, name) do
    NewRelic.Transaction.Reporter.start_transaction(:other)

    NewRelic.DistributedTrace.generate_new_context()
    |> NewRelic.DistributedTrace.track_transaction(transport_type: "Other")

    NewRelic.add_attributes(
      pid: inspect(self()),
      start_time: System.system_time(),
      start_time_mono: System.monotonic_time(),
      other_transaction_name: "#{category}/#{name}"
    )

    :ok
  end

  def stop_transaction() do
    NewRelic.Transaction.Reporter.stop_transaction(:other)
    :ok
  end
end
