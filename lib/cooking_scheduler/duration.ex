defmodule CookingScheduler.Duration do
  @moduledoc """
  A length of time stored as whole minutes, typed the way people write it:
  `"1:50"`, `"1h50"`, `"1h 50m"`, `"2h"`, `"45m"` or just `"90"` (minutes).
  """
  use Ecto.Type

  @hint "try 1:30, 1h30m, 45m or 90"

  @impl true
  def type, do: :integer

  @impl true
  def cast(minutes) when is_integer(minutes) and minutes >= 0, do: {:ok, minutes}
  def cast(nil), do: {:ok, nil}

  def cast(text) when is_binary(text) do
    case parse(text) do
      {:ok, minutes} -> {:ok, minutes}
      :error -> {:error, message: @hint}
    end
  end

  def cast(_), do: {:error, message: @hint}

  @impl true
  def load(minutes), do: {:ok, minutes}
  @impl true
  def dump(minutes) when is_integer(minutes), do: {:ok, minutes}
  def dump(_), do: :error

  @doc "Parses text into minutes."
  def parse(text) do
    text = text |> String.trim() |> String.downcase()

    cond do
      m = Regex.run(~r/^(\d+):(\d{1,2})$/, text) ->
        hm(m)

      m = Regex.run(~r/^(\d+)\s*h(?:ours?|rs?)?\s*(\d+)?\s*(?:m|mins?|minutes?)?$/, text) ->
        hm(m)

      m = Regex.run(~r/^(\d+)\s*(?:m|mins?|minutes?)?$/, text) ->
        {:ok, String.to_integer(Enum.at(m, 1))}

      true ->
        :error
    end
  end

  defp hm([_, h]), do: {:ok, String.to_integer(h) * 60}

  defp hm([_, h, m]) do
    m = if m == "", do: 0, else: String.to_integer(m)
    {:ok, String.to_integer(h) * 60 + m}
  end

  @doc ~s|Formats minutes for display: `110` -> "1h 50m".|
  def format(nil), do: ""
  def format(minutes) when minutes < 60, do: "#{minutes}m"
  def format(minutes) when rem(minutes, 60) == 0, do: "#{div(minutes, 60)}h"
  def format(minutes), do: "#{div(minutes, 60)}h #{rem(minutes, 60)}m"

  @doc ~s|Clock time from minutes after midnight: `810` -> "13:30". Negative = the day before.|
  def clock(minutes) when minutes < 0, do: clock(minutes + 1440) <> " (day before)"

  def clock(minutes) do
    minutes = rem(minutes, 1440)
    :io_lib.format("~2..0B:~2..0B", [div(minutes, 60), rem(minutes, 60)]) |> IO.iodata_to_binary()
  end
end
