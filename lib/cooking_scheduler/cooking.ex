defmodule CookingScheduler.Cooking do
  @moduledoc """
  The live view of the plan on the day. Takes the planned entries (from `Planner`) plus
  what has actually happened (started / taken out / extra time) and the current time,
  and works out the tasks to do, what's in progress, and when dinner will really be ready.

  Pure functions; times are minutes after midnight.
  """

  alias CookingScheduler.Planner

  defmodule Task do
    @moduledoc false
    # kind: :prep | :start | :out
    # state: :done | :overdue | :now | :upcoming
    defstruct [:entry, :kind, :at, :state]
  end

  defmodule Live do
    @moduledoc false
    # Where a dish actually is. phase: :waiting | :cooking | :resting | :ready | :unscheduled
    defstruct [:entry, :phase, :cook_at, :out_at, :ready_at, :progress]
  end

  # Anything due within this many minutes counts as "now".
  @now_window 5

  @doc "Live status of one dish."
  def live(%Planner.Entry{dish: d} = e, now) do
    total = Planner.total_minutes(d)

    if total == 0 do
      %Live{entry: e, phase: :unscheduled}
    else
      started = d.cook_started_at
      cook_at = started || (d.cook_done_at && e.cook_at) || max(e.cook_at, now)
      out_at = d.cook_done_at || cook_at + total
      ready_at = out_at + d.rest_minutes

      phase =
        cond do
          d.cook_done_at && now >= ready_at -> :ready
          d.cook_done_at -> :resting
          started -> :cooking
          true -> :waiting
        end

      progress =
        if phase == :cooking,
          do: min(100, max(0, round((now - started) / total * 100))),
          else: nil

      %Live{
        entry: e,
        phase: phase,
        cook_at: cook_at,
        out_at: out_at,
        ready_at: ready_at,
        progress: progress
      }
    end
  end

  @doc "All dishes with their live status."
  def lives(entries, now), do: Enum.map(entries, &live(&1, now))

  @doc """
  When dinner will really be ready: the planned serving time, or later if anything is
  running behind (started late, taking longer, or overdue to start).
  """
  def projected_serve(lives, serve) do
    lives
    |> Enum.reject(&(&1.phase == :unscheduled))
    |> Enum.map(& &1.ready_at)
    |> Enum.max(fn -> serve end)
    |> max(serve)
  end

  @doc "Every task still to do, then those already done, each classified against `now`."
  def tasks(lives, now) do
    lives
    |> Enum.flat_map(&tasks_for(&1, now))
    |> Enum.sort_by(&{&1.at, kind_order(&1.kind), &1.entry.dish.name})
  end

  defp tasks_for(%Live{phase: :unscheduled}, _now), do: []

  defp tasks_for(%Live{entry: e} = l, now) do
    d = e.dish
    started? = d.cook_started_at != nil or d.cook_done_at != nil

    prep =
      if d.prep_minutes > 0,
        do: [task(e, :prep, e.prep_at, d.prepped, now)],
        else: []

    prep ++
      [
        task(e, :start, l.cook_at, started?, now),
        task(e, :out, l.out_at, d.cook_done_at != nil, now)
      ]
  end

  defp task(entry, kind, at, done?, now) do
    state =
      cond do
        done? -> :done
        at < now -> :overdue
        at - now <= @now_window -> :now
        true -> :upcoming
      end

    %Task{entry: entry, kind: kind, at: at, state: state}
  end

  defp kind_order(:prep), do: 0
  defp kind_order(:start), do: 1
  defp kind_order(:out), do: 2
end
