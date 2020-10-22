defmodule NewRelic.Metric do
  @moduledoc false

  defstruct name: "",
            scope: "",
            call_count: 0,
            total_call_time: 0,
            total_exclusive_time: 0,
            min_call_time: 0,
            max_call_time: 0,
            sum_of_squares: 0
end
