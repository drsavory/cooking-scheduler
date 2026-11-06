defmodule CookingScheduler.Clock do
  @moduledoc "Current time of day in minutes after midnight (local time). Overridable in tests."

  def now_minutes do
    case Application.get_env(:cooking_scheduler, :clock) do
      fun when is_function(fun, 0) ->
        fun.()

      _ ->
        {_date, {h, m, _s}} = :calendar.local_time()
        h * 60 + m
    end
  end
end
