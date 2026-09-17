defmodule ObanExample.Worker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"error" => message}}) do
    {:error, message}
  end

  def perform(%Oban.Job{meta: meta}) do
    NewRelic.accept_distributed_trace_headers(meta["dt_headers"])

    Process.sleep(15 + :rand.uniform(50))
    :ok
  end
end
