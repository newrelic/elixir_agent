defmodule NewRelic.Instrumented.Task.Wrappers do
  @moduledoc false

  def instrument(fun) when is_function(fun, 0) do
    tx = NewRelic.get_transaction()

    fn ->
      NewRelic.connect_to_transaction(tx)
      fun.()
    end
  end

  def instrument(fun) when is_function(fun, 1) do
    tx = NewRelic.get_transaction()

    fn val ->
      NewRelic.connect_to_transaction(tx)
      fun.(val)
    end
  end

  def instrument({module, fun, args}) do
    {__MODULE__, :instrument_mfa, [NewRelic.get_transaction(), {module, fun, args}]}
  end

  def instrument_mfa(tx, {module, fun, args}) do
    Process.put(:"$initial_call", {module, fun, args})
    NewRelic.connect_to_transaction(tx)
    apply(module, fun, args)
  end

  def instrument_mfa(val, tx, {module, fun, args}) do
    instrument_mfa(tx, {module, fun, [val | args]})
  end
end
