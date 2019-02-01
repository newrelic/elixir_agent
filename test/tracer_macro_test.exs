defmodule NewRelic.Tracer.MacroTest do
  use ExUnit.Case

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

    test "ignore variables in function argument pattern match" do
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
            %{v1: _v1, v2: _v2, v3: %{foo: _bar} = _v3} = data,
            _x = y,
            [[_hh, _hhh] = _h | _tail] = lst
          ]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end

    test "ignore variables on the left side of a pattern match" do
      ast =
        quote do
          [data = %{foo: :bar}]
        end

      expected =
        quote do
          [_data = %{foo: :bar}]
        end

      assert expected == NewRelic.Tracer.Macro.build_call_args(ast)
    end
  end
end
