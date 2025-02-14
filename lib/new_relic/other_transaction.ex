defmodule NewRelic.OtherTransaction do
  @moduledoc false

  def start_transaction(category, name, headers \\ %{}) do
    NewRelic.Transaction.Reporter.start_transaction(:other)
    NewRelic.DistributedTrace.start(:other, headers)

    NewRelic.add_attributes(
      pid: inspect(self()),
      other_transaction_name: "#{category}/#{name}"
    )

    :ok
  end

  def stop_transaction() do
    NewRelic.Transaction.Reporter.stop_transaction(:other)
    :ok
  end
end
