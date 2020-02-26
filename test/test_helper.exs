ExUnit.start()

System.at_exit(fn _ ->
  IO.puts(GenServer.call(NewRelic.Logger, :flush))
end)
