defmodule CookingScheduler.PlannerTest do
  use ExUnit.Case, async: true

  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.MealDish
  alias CookingScheduler.Planner

  @serve 13 * 60 + 30

  defp oven(id, name, unit \\ :gas_mark, min \\ 0.25, max \\ 9.0),
    do: %Appliance{id: id, kind: :oven, name: name, temp_unit: unit, min_temp: min, max_temp: max}

  defp ring(id, size), do: %Appliance{id: id, kind: :ring, name: "#{size} #{id}", size: size}

  defp dish(id, attrs) do
    struct(
      %MealDish{
        id: id,
        name: "MealDish #{id}",
        method: :oven,
        temp: 4.0,
        temp_unit: :gas_mark,
        prep_minutes: 0,
        cook_minutes: 60,
        buffer_minutes: 0,
        rest_minutes: 0
      },
      attrs
    )
  end

  defp entry(entries, id), do: Enum.find(entries, &(&1.dish.id == id))

  test "times count back from serving, including buffer and rest" do
    d = dish(1, prep_minutes: 60, cook_minutes: 250, buffer_minutes: 20, rest_minutes: 120)
    [e] = Planner.plan([d], @serve, [oven(1, "Oven")])

    assert e.out_at == @serve - 120
    assert e.cook_at == e.out_at - 270
    assert e.prep_at == e.cook_at - 60
    assert e.serve_at == @serve
  end

  test "dishes at similar temperatures share an oven; a different one goes elsewhere" do
    ovens = [oven(1, "Left"), oven(2, "Right")]
    dishes = [dish(1, temp: 4.0), dish(2, temp: 4.0), dish(3, temp: 8.0, cook_minutes: 60)]
    entries = Planner.plan(dishes, @serve, ovens)

    assert entry(entries, 1).resource.id == entry(entries, 2).resource.id
    assert entry(entries, 3).resource.id != entry(entries, 1).resource.id
    assert Enum.all?(entries, &(&1.issues == []))
  end

  test "dishes only share an oven while their space adds up to one oven" do
    ovens = [oven(1, "Left"), oven(2, "Right")]

    fits =
      Planner.plan([dish(1, oven_share: :half), dish(2, oven_share: :third)], @serve, ovens)

    assert entry(fits, 1).resource.id == entry(fits, 2).resource.id

    full =
      Planner.plan([dish(1, oven_share: :full), dish(2, oven_share: :quarter)], @serve, ovens)

    assert entry(full, 1).resource.id != entry(full, 2).resource.id
    assert Enum.all?(full, &(&1.issues == []))

    [_, no_room] =
      Planner.plan([dish(1, oven_share: :full), dish(2, oven_share: :quarter)], @serve, [
        oven(1, "Only")
      ])

    assert no_room.issues == ["No oven with room at this temperature around this time"]
  end

  test "clashing temperatures with only one oven are flagged, not double-booked" do
    entries = Planner.plan([dish(1, temp: 4.0), dish(2, temp: 8.0)], @serve, [oven(1, "Only")])
    flagged = Enum.filter(entries, &(&1.issues != []))

    assert [%{resource: nil, issues: ["No oven with room at this temperature around this time"]}] =
             flagged
  end

  test "dishes that don't overlap in time can use the same oven at different temperatures" do
    a = dish(1, temp: 4.0, cook_minutes: 60, rest_minutes: 60)
    b = dish(2, temp: 8.0, cook_minutes: 15, rest_minutes: 0)
    entries = Planner.plan([a, b], @serve, [oven(1, "Only")])
    assert Enum.all?(entries, &(&1.issues == []))
  end

  test "an oven that can't reach the temperature is skipped" do
    low = oven(1, "Small", :celsius, 50.0, 180.0)
    hot = oven(2, "Big", :celsius, 50.0, 250.0)
    [e] = Planner.plan([dish(1, temp: 8.0)], @serve, [low, hot])
    assert e.resource.id == 2
  end

  test "pinning forces the oven" do
    entries = Planner.plan([dish(1, appliance_id: 2)], @serve, [oven(1, "A"), oven(2, "B")])
    assert [%{resource: %{id: 2}, source: :pinned}] = entries
  end

  test "rings are used up: each dish gets its own, and we run out" do
    rings = [ring(1, :small), ring(2, :medium)]
    dishes = for id <- 1..3, do: dish(id, method: :ring, ring_size: :small, cook_minutes: 30)
    entries = Planner.plan(dishes, @serve, rings)

    assigned = entries |> Enum.map(& &1.resource) |> Enum.reject(&is_nil/1) |> Enum.map(& &1.id)
    assert Enum.sort(assigned) == [1, 2]
    assert [%{issues: [msg]}] = Enum.filter(entries, &(&1.resource == nil))
    assert msg =~ "No free small"
  end

  test "a ring is free again once the dish before it is done" do
    rings = [ring(1, :medium)]
    early = dish(1, method: :ring, ring_size: :medium, cook_minutes: 30, rest_minutes: 60)
    late = dish(2, method: :ring, ring_size: :medium, cook_minutes: 30)
    entries = Planner.plan([early, late], @serve, rings)
    assert Enum.all?(entries, &(&1.issues == []))
  end

  test "a small request can use a bigger ring but not vice versa" do
    entries = Planner.plan([dish(1, method: :ring, ring_size: :large)], @serve, [ring(1, :small)])
    assert [%{resource: nil}] = entries
    entries = Planner.plan([dish(1, method: :ring, ring_size: :small)], @serve, [ring(1, :large)])
    assert [%{resource: %{id: 1}}] = entries
  end

  test "appliance clash is flagged" do
    cooker = %Appliance{id: 9, kind: :other, name: "Slow cooker"}
    a = dish(1, method: :appliance, appliance_id: 9, cook_minutes: 360)
    b = dish(2, method: :appliance, appliance_id: 9, cook_minutes: 60)
    entries = Planner.plan([a, b], @serve, [cooker])

    assert Enum.any?(
             entries,
             &Enum.any?(&1.issues, fn i -> i =~ "Slow cooker is also needed" end)
           )
  end

  test "dishes with no cooking time are called out" do
    [e] = Planner.plan([dish(1, cook_minutes: 0)], @serve, [oven(1, "Oven")])
    assert e.issues == ["Add a cooking time so we can schedule this"]
  end

  test "sorted by when you need to start" do
    entries =
      Planner.plan([dish(1, cook_minutes: 30), dish(2, cook_minutes: 120, temp: 8.0)], @serve, [
        oven(1, "A"),
        oven(2, "B")
      ])

    assert Enum.map(entries, & &1.dish.id) == [2, 1]
  end

  test "gas mark / celsius conversion" do
    assert Appliance.to_celsius(4, :gas_mark) == 180.0
    assert Appliance.to_celsius(7, :gas_mark) == 220.0
    assert_in_delta Appliance.to_celsius(4.5, :gas_mark), 185.0, 0.001
    assert_in_delta Appliance.to_celsius(350, :fahrenheit), 176.67, 0.01
  end

  describe "load/2" do
    test "adds up oven space where dishes overlap" do
      kitchen = [oven(1, "Oven")]
      a = dish(1, cook_minutes: 120, oven_share: :half)
      b = dish(2, cook_minutes: 60, oven_share: :third)

      [row] = kitchen |> then(&Planner.plan([a, b], @serve, &1)) |> Planner.load(kitchen)

      assert row.capacity == 12
      assert row.peak == 10
      assert Enum.map(row.segments, & &1.used) == [6, 10]
    end

    test "a longer rest frees the oven sooner" do
      kitchen = [oven(1, "Oven")]
      long = dish(1, cook_minutes: 60, oven_share: :full)

      [tight] = Planner.load(Planner.plan([long], @serve, kitchen), kitchen)

      [rested] =
        Planner.load(Planner.plan([%{long | rest_minutes: 30}], @serve, kitchen), kitchen)

      assert List.last(tight.segments).to == @serve
      assert List.last(rested.segments).to == @serve - 30
    end

    test "rings and appliances hold one thing at a time; idle appliances are left out" do
      kitchen = [oven(1, "Oven"), ring(2, :large)]
      hob = dish(1, method: :ring, ring_size: :large)

      assert [row] = Planner.load(Planner.plan([hob], @serve, kitchen), kitchen)
      assert row.appliance.id == 2
      assert row.capacity == 1
      assert row.peak == 1
    end
  end
end
