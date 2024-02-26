defmodule AbsintheExample.Resolvers do
  use NewRelic.Tracer

  def echo(_source, %{this: this}, _res) do
    {:ok, do_echo(this)}
  end

  @trace :do_echo
  defp do_echo(this), do: this

  def one(_source, _args, _res) do
    {:ok, %{two: %{}}}
  end

  def three(_source, _args, _res) do
    Process.sleep(2)
    {:ok, do_three()}
  end

  @trace :do_three
  def do_three() do
    Process.sleep(2)
    3
  end
end
