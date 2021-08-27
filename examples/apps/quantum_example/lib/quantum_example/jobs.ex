defmodule QuantumExample.Jobs do
  def do_some_work do
    # fake work
    Process.sleep(250)
    IO.puts("Work done!")
  end
end
