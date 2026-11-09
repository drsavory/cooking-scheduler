defmodule CookingScheduler.Dates do
  @moduledoc "Words for dates relative to today."

  @doc ~s|"today", "tomorrow", "in 3 days", "yesterday", "4 days ago", "in 3 weeks".|
  def relative(%Date{} = date, today \\ Date.utc_today()) do
    case Date.diff(date, today) do
      0 -> "today"
      1 -> "tomorrow"
      -1 -> "yesterday"
      n when n > 1 and n < 14 -> "in #{n} days"
      n when n >= 14 and n < 60 -> "in #{div(n, 7)} weeks"
      n when n >= 60 -> "in #{div(n, 30)} months"
      n when n > -14 -> "#{-n} days ago"
      n when n > -60 -> "#{div(-n, 7)} weeks ago"
      n -> "#{div(-n, 30)} months ago"
    end
  end
end
