defmodule ObanExample.Worker do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Process.sleep(:rand.uniform(50))
    :ok
  end
end
