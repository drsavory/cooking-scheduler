defmodule CookingScheduler.Planner do
  @moduledoc """
  Works out when each dish needs prepping and cooking, and which oven, ring or
  appliance it should use.

  Pure functions only (no database); times are minutes after midnight and can be
  negative for anything that has to start the day before.

  Every dish is ready to serve at the serving time:

      serve  = finish
      out    = serve - rest           (comes out of the oven / off the heat)
      cook   = out - (cook + buffer)  (goes in)
      prep   = cook - prep            (start preparing)
  """

  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meal.Dish

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

  defp timeline(%Dish{} = d, serve) do
    out = serve - d.rest_minutes
    cook = out - (d.cook_minutes + d.buffer_minutes)

    %Entry{dish: d, serve_at: serve, out_at: out, cook_at: cook, prep_at: cook - d.prep_minutes}
  end

  defp pinned?(%Entry{dish: %{appliance_id: id, method: m}}, by_id) do
    m in [:oven, :appliance] and id != nil and Map.has_key?(by_id, id)
  end

  defp uses_equipment?(%Entry{dish: d}), do: d.cook_minutes + d.buffer_minutes > 0

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
    temp_c = Appliance.to_celsius(e.dish.temp, e.dish.temp_unit)
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
              incompatible(usage, claim.(oven), e, temp_c) == [] do
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
            {add_issue(e, "No oven free at this temperature around this time"), usage}
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
    do: %{key: key, start: e.cook_at, stop: e.out_at, temp_c: temp_c, name: e.dish.name}

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
