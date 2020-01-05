unless System.get_env("NR_INT_TEST") do
  {:ok, _} = NewRelic.EnabledSupervisor.start_link(enabled: true)
end

ExUnit.start()

System.at_exit(fn _ ->
  IO.puts(GenServer.call(NewRelic.Logger, :flush))
end)
