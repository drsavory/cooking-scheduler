defmodule CookingScheduler.Planner do
  @moduledoc """
  Works out when each dish needs prepping and cooking, and which oven, ring or
  appliance it should use.

  Pure functions only (no database); times are minutes after midnight and can be
  negative for anything that has to start the day before.

  Every dish is ready to serve at its course's serving time (the meal's serving time plus the
  dish's offset: a starter is earlier, a pudding later):

      serve  = meal serve + offset
      out    = serve - rest           (comes out of the oven / off the heat)
      cook   = out - cook             (goes in)
      prep   = cook - prep            (start preparing)
  """

  alias CookingScheduler.UnitConversion
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.MealDish

  # Two oven dishes can share an oven if their temperatures are this close (°C).
  @temp_tolerance 15

  defmodule Entry do
    @moduledoc false
    defstruct [
      :dish,
      :prep_at,
      :cook_at,
      :out_at,
      :serve_at,
      :resource,
      # :pinned | :suggested | nil
      :source,
      issues: []
    ]
  end

  @doc """
  Plans every dish. `kitchen` is the list of all appliances (ovens, rings, other).
  Returns entries sorted by when you need to start (prep first).
  """
  def plan(dishes, serve_minutes, kitchen) do
    ovens = Enum.filter(kitchen, &(&1.kind == :oven))
    rings = kitchen |> Enum.filter(&(&1.kind == :ring)) |> Enum.sort_by(&ring_order/1)
    by_id = Map.new(kitchen, &{&1.id, &1})

    entries = Enum.map(dishes, &timeline(&1, serve_minutes))

    # Pinned dishes claim their equipment first so suggestions work around them.
    {pinned, free} = Enum.split_with(entries, &pinned?(&1, by_id))
    ordered = Enum.sort_by(pinned, & &1.cook_at) ++ Enum.sort_by(free, & &1.cook_at)

    {entries, _usage} =
      Enum.map_reduce(ordered, [], fn entry, usage ->
        {entry, usage} = assign(entry, usage, %{ovens: ovens, rings: rings, by_id: by_id})
        {entry, usage}
      end)

    Enum.sort_by(entries, &{&1.prep_at, &1.cook_at, &1.dish.name})
  end

  @doc """
  How busy each appliance is over time, from planned entries.

  Returns one row per appliance: ovens first and then kitchen order, with idle ones (no
  slots) after all the busy ones. Rings of the same size share a row (the first such ring's place), treated like one appliance with a
  slot per ring:
  `%{id, name, kind, appliances, capacity, peak, segments, slots}` where `kind` is `:oven`,
  `:rings` or `:other` and `id` is a DOM-safe key. Segments are consecutive stretches with
  constant load: `%{from, to, used, dishes}`. Slots are one bar per dish,
  `%{entry, units, offset, over?}`: `units` tall (its share of the row) starting `offset`
  units up, so a whole-oven dish fills the full height and a ring dish sits in its ring's slot.
  Ovens are measured in `MealDish.oven_units/1` against `MealDish.oven_capacity/0`; a ring row
  holds one dish per ring and other appliances hold one thing at a time.
  """
  def load(entries, kitchen) do
    placed = Enum.filter(entries, &(&1.resource && uses_equipment?(&1)))

    for group <- load_groups(kitchen),
        ids = MapSet.new(group, & &1.id),
        mine = Enum.filter(placed, &MapSet.member?(ids, &1.resource.id)) do
      [app | _] = group

      kind =
        case app.kind do
          :oven -> :oven
          :ring -> :rings
          _ -> :other
        end

      capacity =
        case kind do
          :oven -> MealDish.oven_capacity()
          :rings -> length(group)
          :other -> 1
        end

      weight = fn e ->
        if kind == :oven, do: MealDish.oven_units(e.dish.oven_share), else: 1
      end

      points = mine |> Enum.flat_map(&[&1.cook_at, &1.out_at]) |> Enum.uniq() |> Enum.sort()

      segments =
        points
        |> Enum.zip(Enum.drop(points, 1))
        |> Enum.map(fn {from, to} ->
          in_use = Enum.filter(mine, &(&1.cook_at <= from and &1.out_at >= to))
          %{from: from, to: to, used: Enum.sum(Enum.map(in_use, weight)), dishes: in_use}
        end)
        |> Enum.reject(&(&1.dishes == []))

      peak = segments |> Enum.map(& &1.used) |> Enum.max(fn -> 0 end)

      # A ring dish's slot is the ring it is on.
      fixed =
        if kind == :rings,
          do: fn e -> Enum.find_index(group, &(&1.id == e.resource.id)) end,
          else: fn _ -> nil end

      %{
        id: if(kind == :rings, do: "rings-#{app.size}", else: "#{app.id}"),
        name: load_name(kind, group),
        kind: kind,
        appliances: group,
        capacity: capacity,
        peak: peak,
        segments: segments,
        slots: slots(mine, segments, capacity, weight, fixed)
      }
    end
    # Unused appliances go to the bottom; the sort is stable, so ovens stay first in each half.
    |> Enum.sort_by(&(&1.slots == []))
  end

  # Ovens, then everything else in kitchen order, with every ring of a size gathered at the first one's place.
  defp load_groups(kitchen) do
    rings = kitchen |> Enum.filter(&(&1.kind == :ring)) |> Enum.group_by(& &1.size)

    kitchen
    |> Enum.flat_map(fn
      %Appliance{kind: :ring, size: size} = app ->
        if hd(rings[size]).id == app.id, do: [rings[size]], else: []

      app ->
        [[app]]
    end)
    # Ovens first: they are what runs out. `sort_by` is stable, so kitchen order holds otherwise.
    |> Enum.sort_by(fn [app | _] -> app.kind != :oven end)
  end

  defp load_name(:rings, [ring]), do: ring.name

  defp load_name(:rings, [ring | _] = group),
    do: "#{length(group)} #{Appliance.ring_name(ring.size)}s"

  defp load_name(_kind, [app]), do: app.name

  @doc """
  The free space in a `load/2` row between `from` and `to`, as boxes in the same units as its
  slots: `%{from, to, offset, units}`. Each box is a gap in the stack that stays open for its
  whole time; boxes of the same gap that run on in time are merged. Rings are separate
  burners, so a ring row gets one box per free ring rather than one across neighbours.
  """
  def free_space(%{capacity: capacity, slots: bars} = row, from, to) do
    step = if row[:kind] == :rings, do: 1, else: nil

    points =
      bars
      |> Enum.flat_map(&[&1.entry.cook_at, &1.entry.out_at])
      |> Enum.concat([from, to])
      |> Enum.filter(&(&1 >= from and &1 <= to))
      |> Enum.uniq()
      |> Enum.sort()

    points
    |> Enum.zip(Enum.drop(points, 1))
    |> Enum.flat_map(fn {a, b} ->
      taken =
        bars
        |> Enum.filter(&(&1.entry.cook_at < b and &1.entry.out_at > a))
        |> Enum.map(&{&1.offset, &1.offset + &1.units})
        |> Enum.sort()

      {gaps, top} =
        Enum.reduce(taken, {[], 0}, fn {lo, hi}, {gaps, at} ->
          gaps = if lo > at, do: [{at, lo} | gaps], else: gaps
          {gaps, max(at, hi)}
        end)

      gaps = if top < capacity, do: [{top, capacity} | gaps], else: gaps

      for {lo, hi} <- gaps,
          hi > lo,
          lo < capacity,
          {lo, hi} <- split(lo, min(hi, capacity), step),
          do: %{from: a, to: b, offset: lo, units: hi - lo}
    end)
    |> Enum.sort_by(&{&1.offset, &1.units, &1.from})
    |> Enum.chunk_while(
      nil,
      fn
        box, nil ->
          {:cont, box}

        box, acc
        when acc.offset == box.offset and acc.units == box.units and acc.to == box.from ->
          {:cont, %{acc | to: box.to}}

        box, acc ->
          {:cont, acc, box}
      end,
      fn
        nil -> {:cont, nil}
        acc -> {:cont, acc, nil}
      end
    )
    |> Enum.sort_by(&{&1.from, &1.offset})
  end

  defp split(lo, hi, nil), do: [{lo, hi}]
  defp split(lo, hi, step), do: for(o <- lo..(hi - 1)//step, do: {o, min(o + step, hi)})

  # Places each dish as a bar in the appliance's space: `units` tall (its oven space, or 1 for
  # one-at-a-time appliances) at the lowest `offset` that is free for its whole time on the
  # heat. A whole-oven dish fills the full height; smaller ones stack. A dish is `over?` when
  # the appliance is over capacity at any point while it is in; such bars can sit above
  # `capacity`.
  defp slots(entries, segments, capacity, weight, fixed) do
    entries
    |> Enum.sort_by(&{&1.cook_at, -weight.(&1), -&1.out_at, &1.dish.name})
    |> Enum.reduce([], fn e, placed ->
      units = weight.(e)
      busy = Enum.filter(placed, &(&1.entry.cook_at < e.out_at and &1.entry.out_at > e.cook_at))

      offset =
        fixed.(e) ||
          [0 | Enum.map(busy, &(&1.offset + &1.units))]
          |> Enum.sort()
          |> Enum.find(fn o ->
            not Enum.any?(busy, &(&1.offset < o + units and &1.offset + &1.units > o))
          end)

      over? =
        Enum.any?(segments, &(&1.used > capacity and &1.from < e.out_at and &1.to > e.cook_at))

      placed ++ [%{entry: e, units: units, offset: offset, over?: over?}]
    end)
  end

  defp timeline(%MealDish{} = d, meal_serve) do
    serve = meal_serve + (d.serve_offset_minutes || 0)
    out = serve - d.rest_minutes
    # Only the planned cook time counts here: extra minutes added on the day extend the cook
    # from when it went in (see `Cooking`), and must not drag the start or prep slot earlier.
    cook = out - d.cook_minutes

    %Entry{dish: d, serve_at: serve, out_at: out, cook_at: cook, prep_at: cook - d.prep_minutes}
  end

  # An oven dish only counts as pinned to an actual oven; anything else is left to be placed.
  defp pinned?(%Entry{dish: %{appliance_id: id, method: m}}, by_id) do
    case {m, by_id[id]} do
      {:oven, %Appliance{kind: :oven}} -> true
      {:appliance, %Appliance{}} -> true
      _ -> false
    end
  end

  defp uses_equipment?(%Entry{dish: d}), do: total_minutes(d) > 0

  @doc "Time on the heat: cooking plus any extra added on the day."
  def total_minutes(%MealDish{} = d), do: d.cook_minutes + d.extra_minutes

  @doc "The latest time anything is served: the meal's serving time or a later course."
  def last_serve(entries, serve_minutes) do
    entries |> Enum.map(& &1.serve_at) |> Enum.max(fn -> serve_minutes end) |> max(serve_minutes)
  end

  # ---- oven events ------------------------------------------------------------

  @doc """
  What to do to each oven and when, from planned entries (ADR 0019): switch it on ahead of the
  first dish (`:preheat`, the oven's `preheat_minutes` before), and change the temperature
  when a dish going in wants a different one from what's already set (`:adjust`).

  Each event is `%{kind, appliance, at, dish, temp_c, temp, temp_unit, id}` where `dish` is the
  meal dish that triggers it, `temp` is in the oven's own scale and `id` is a stable key
  (`"preheat:<oven id>:<dish id>"`) for ticking it off. Sorted by time.
  """
  def oven_events(entries, kitchen) do
    for oven <- kitchen,
        oven.kind == :oven,
        mine =
          entries
          |> Enum.filter(&(&1.resource && &1.resource.id == oven.id && uses_equipment?(&1)))
          |> Enum.sort_by(&{&1.cook_at, &1.dish.name}),
        mine != [],
        event <- events_for(oven, mine) do
      event
    end
    |> Enum.sort_by(&{&1.at, &1.appliance.name})
  end

  defp events_for(oven, [first | rest]) do
    preheat = oven.preheat_minutes || 0
    first_c = dish_celsius(first.dish)

    [event(:preheat, oven, first, first.cook_at - preheat, first_c)] ++
      adjustments(oven, rest, first_c)
  end

  # Walk the put-ins in order; the oven is "set" to the last temperature asked for.
  defp adjustments(oven, entries, setting) do
    {events, _} =
      Enum.map_reduce(entries, setting, fn e, setting ->
        c = dish_celsius(e.dish)

        if abs(c - setting) > 1,
          do: {[event(:adjust, oven, e, e.cook_at, c)], c},
          else: {[], setting}
      end)

    List.flatten(events)
  end

  defp event(kind, oven, entry, at, temp_c) do
    %{
      kind: kind,
      appliance: oven,
      at: at,
      dish: entry.dish,
      temp_c: temp_c,
      temp: oven_temp(temp_c, oven.temp_unit),
      temp_unit: oven.temp_unit,
      id: "#{kind}:#{oven.id}:#{entry.dish.id}"
    }
  end

  defp dish_celsius(%MealDish{temp: t, temp_unit: u}), do: UnitConversion.convert!(t, u, :c)

  # Shown in the oven's own scale; if a gas-mark oven can't express it, fall back to °C.
  defp oven_temp(temp_c, unit) do
    case UnitConversion.convert(temp_c, :c, unit, round: 0) do
      {:ok, t} -> {t, unit}
      {:error, _} -> {Float.round(temp_c * 1.0, 0), :celsius}
    end
  end

  # ---- suggestions ------------------------------------------------------------

  @doc """
  Small changes that would fix a dish's placement problems (ADR 0020): a longer rest, or another
  oven. Re-plans the whole meal with each candidate and keeps those where the dish ends up
  with no issues and nothing else gets worse. Returns `[%{label, attrs}]`, best first, at
  most three.
  """
  def suggest(dishes, serve_minutes, kitchen, dish_id) do
    dish = Enum.find(dishes, &(&1.id == dish_id))
    before = plan(dishes, serve_minutes, kitchen)

    if dish && entry_issues(before, dish_id) != [] do
      others_before = for e <- before, e.dish.id != dish_id, into: %{}, do: {e.dish.id, e.issues}

      candidates(dish, kitchen)
      |> Enum.filter(fn {_label, attrs} ->
        trial = Enum.map(dishes, &if(&1.id == dish_id, do: struct(&1, attrs), else: &1))
        after_ = plan(trial, serve_minutes, kitchen)

        entry_issues(after_, dish_id) == [] and
          Enum.all?(after_, fn e ->
            e.dish.id == dish_id or
              length(e.issues) <= length(Map.get(others_before, e.dish.id, []))
          end)
      end)
      |> Enum.take(3)
      |> Enum.map(fn {label, attrs} -> %{label: label, attrs: attrs} end)
    else
      []
    end
  end

  defp entry_issues(entries, dish_id) do
    case Enum.find(entries, &(&1.dish.id == dish_id)) do
      nil -> []
      e -> e.issues
    end
  end

  # Cheapest changes first: a little more rest, then another oven, then a lot more rest.
  defp candidates(%MealDish{method: :oven} = d, kitchen) do
    ovens = for o <- kitchen, o.kind == :oven, o.id != d.appliance_id, do: o

    rests = fn minutes ->
      for m <- minutes,
          do: {"Rest #{m}m longer", %{rest_minutes: d.rest_minutes + m}}
    end

    rests.([15, 30]) ++
      Enum.map(ovens, &{"Use #{&1.name}", %{appliance_id: &1.id}}) ++
      rests.([45, 60]) ++
      for(
        o <- ovens,
        m <- [15, 30],
        do:
          {"Use #{o.name}, rest #{m}m longer",
           %{appliance_id: o.id, rest_minutes: d.rest_minutes + m}}
      )
  end

  defp candidates(%MealDish{method: :ring} = d, _kitchen) do
    for m <- [15, 30, 45, 60], do: {"Rest #{m}m longer", %{rest_minutes: d.rest_minutes + m}}
  end

  defp candidates(%MealDish{} = d, _kitchen) do
    for m <- [15, 30, 45, 60], do: {"Rest #{m}m longer", %{rest_minutes: d.rest_minutes + m}}
  end

  # ---- assignment -----------------------------------------------------------

  defp assign(%Entry{} = e, usage, ctx) do
    cond do
      not uses_equipment?(e) ->
        {add_issue(e, "Add a cooking time so we can schedule this"), usage}

      true ->
        case e.dish.method do
          :oven -> assign_oven(e, usage, ctx)
          :ring -> assign_ring(e, usage, ctx)
          :appliance -> assign_appliance(e, usage, ctx)
        end
    end
  end

  defp assign_oven(e, usage, %{ovens: ovens, by_id: by_id}) do
    temp_c = UnitConversion.convert!(e.dish.temp, e.dish.temp_unit, :c)
    claim = fn oven -> {:oven, oven.id} end

    cond do
      ovens == [] ->
        {add_issue(e, "Add an oven in your kitchen setup"), usage}

      pinned?(e, by_id) ->
        oven = by_id[e.dish.appliance_id]
        clashes = incompatible(usage, claim.(oven), e, temp_c)

        e =
          e
          |> put_resource(oven, :pinned)
          |> maybe_issue(
            clashes == [] and over_capacity?(usage, claim.(oven), e),
            "Not enough room left in #{oven.name} at that time"
          )
          |> maybe_issue(not reaches?(oven, temp_c), "#{oven.name} can't reach this temperature")
          |> maybe_issue(
            clashes != [],
            "Clashes with #{names(clashes)} in #{oven.name} (different temperature)"
          )

        {e, [use(claim.(oven), e, temp_c) | usage]}

      true ->
        candidates = Enum.filter(ovens, &reaches?(&1, temp_c))

        scored =
          for oven <- candidates,
              incompatible(usage, claim.(oven), e, temp_c) == [],
              not over_capacity?(usage, claim.(oven), e) do
            # Prefer sharing an oven with dishes already at a similar temperature.
            {oven, length(overlapping(usage, claim.(oven), e))}
          end

        case scored |> Enum.sort_by(fn {o, shared} -> {-shared, o.id} end) do
          [{oven, _} | _] ->
            e = put_resource(e, oven, :suggested)
            {e, [use(claim.(oven), e, temp_c) | usage]}

          [] when candidates == [] ->
            {add_issue(e, "None of your ovens go to this temperature"), usage}

          [] ->
            {add_issue(e, "No oven with room at this temperature around this time"), usage}
        end
    end
  end

  defp assign_ring(e, usage, %{rings: rings}) do
    wanted = Enum.find_index(Appliance.ring_sizes(), &(&1 == e.dish.ring_size)) || 1

    free =
      Enum.find(rings, fn ring ->
        ring_index(ring) >= wanted and overlapping(usage, {:ring, ring.id}, e) == []
      end)

    case free do
      nil ->
        msg =
          if rings == [],
            do: "Add some hob rings in your kitchen setup",
            else: "No free #{e.dish.ring_size} (or larger) ring at that time"

        {add_issue(e, msg), usage}

      ring ->
        e = put_resource(e, ring, :suggested)
        {e, [use({:ring, ring.id}, e, nil) | usage]}
    end
  end

  defp assign_appliance(e, usage, %{by_id: by_id}) do
    case by_id[e.dish.appliance_id] do
      nil ->
        {add_issue(e, "Choose which appliance this uses"), usage}

      app ->
        clashes = overlapping(usage, {:appliance, app.id}, e)

        e =
          e
          |> put_resource(app, :pinned)
          |> maybe_issue(
            clashes != [],
            "#{app.name} is also needed for #{names(clashes)} at that time"
          )

        {e, [use({:appliance, app.id}, e, nil) | usage]}
    end
  end

  # ---- helpers --------------------------------------------------------------

  defp put_resource(e, resource, source), do: %{e | resource: resource, source: source}
  defp add_issue(e, msg), do: %{e | issues: e.issues ++ [msg]}
  defp maybe_issue(e, true, msg), do: add_issue(e, msg)
  defp maybe_issue(e, false, _msg), do: e

  defp reaches?(oven, temp_c) do
    {lo, hi} = Appliance.range_celsius(oven)
    temp_c >= lo - 1 and temp_c <= hi + 1
  end

  defp use(key, e, temp_c),
    do: %{
      key: key,
      start: e.cook_at,
      stop: e.out_at,
      temp_c: temp_c,
      name: e.dish.name,
      units: MealDish.oven_units(e.dish.oven_share)
    }

  # Would this dish, alongside everything already in the oven at the same time, not fit?
  defp over_capacity?(usage, key, e) do
    used = usage |> overlapping(key, e) |> Enum.map(& &1.units) |> Enum.sum()
    used + MealDish.oven_units(e.dish.oven_share) > MealDish.oven_capacity()
  end

  defp overlapping(usage, key, e) do
    Enum.filter(usage, &(&1.key == key and &1.start < e.out_at and e.cook_at < &1.stop))
  end

  defp incompatible(usage, key, e, temp_c) do
    usage |> overlapping(key, e) |> Enum.filter(&(abs(&1.temp_c - temp_c) > @temp_tolerance))
  end

  defp names(uses), do: uses |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")

  defp ring_index(ring), do: Enum.find_index(Appliance.ring_sizes(), &(&1 == ring.size))
  defp ring_order(ring), do: {ring_index(ring), ring.id}
end
