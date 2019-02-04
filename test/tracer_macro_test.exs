defmodule NewRelic.Tracer.MacroTest do
  use ExUnit.Case

  @doc """
  We re-inject the function args into the call to the Tracer reporter
  without generating a bunch of unused variable warnings.
  """
  describe "build_call_args/1" do
    test "do nothing to simple argument lists" do
      ast =
        quote do
          [a, b, 100, [h | t]]
        end

      assert ast == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "substitute ignored variables with an atom" do
      ast =
        quote do
          [a, _ignored_val, b]
        end

      expected =
        quote do
          [a, :__ignored__, b]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "strip default values" do
      ast =
        quote do
          [a \\ 100]
        end

      expected =
        quote do
          [a]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "Drop the de-structuring in favor of the variable" do
      ast =
        quote do
          [
            %{v1: v1, v2: v2, v3: %{foo: bar} = v3} = data,
            x = y,
            [[hh, hhh] = h | tail] = lst
          ]
        end

      expected =
        quote do
          [
            data,
            y,
            lst
          ]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "Find variable on the left of a pattern match" do
      ast =
        quote do
          [data = %{foo: %{baz: "qux"}}]
        end

      expected =
        quote do
          [data]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "Handle a strange double-sided pattern match" do
      ast =
        quote do
          [data = %{foo: %{baz: "qux"}} = map]
        end

      expected =
        quote do
          [map]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end
  end
end
