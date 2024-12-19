defmodule ObanExample.Worker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"error" => message}}) do
    {:error, message}
  end

  def perform(%Oban.Job{args: args}) do
    Process.sleep(:rand.uniform(50))
    :ok
  end
end
