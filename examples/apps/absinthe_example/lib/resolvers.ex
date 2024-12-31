defmodule AbsintheExample.Resolvers do
  use NewRelic.Tracer

  def echo(_source, %{this: this}, _res) do
    {:ok, do_echo(this)}
  end

  @trace :do_echo
  defp do_echo(this), do: this

  def one(_source, _args, _res) do
    Process.sleep(1)
    {:ok, %{two: %{}}}
  end

  def three(_source, %{value: value}, _res) do
    Process.sleep(2)
    {:ok, do_three(value)}
  end

  @trace :do_three
  def do_three(value) do
    Process.sleep(2)
    value
  end
end
