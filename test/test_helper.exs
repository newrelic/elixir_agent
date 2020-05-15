Application.ensure_all_started(:plug)

unless System.get_env("NR_INT_TEST") do
  {:ok, _} = NewRelic.EnabledSupervisor.start_link(:ok)
end

ExUnit.start()

System.at_exit(fn _ ->
  IO.puts(GenServer.call(NewRelic.Logger, :flush))
end)
