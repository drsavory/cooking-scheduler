defmodule CookingScheduler.CookingTest do
  use ExUnit.Case, async: true

  alias CookingScheduler.{Cooking, Planner}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.MealDish

  @serve 13 * 60 + 30
  @oven %Appliance{
    id: 1,
    kind: :oven,
    name: "Oven",
    temp_unit: :gas_mark,
    min_temp: 0.25,
    max_temp: 9.0
  }

  defp dish(attrs) do
    struct(
      %MealDish{
        id: 1,
        name: "Turkey",
        method: :oven,
        temp: 4.0,
        temp_unit: :gas_mark,
        prep_minutes: 30,
        cook_minutes: 120,
        rest_minutes: 60,
        extra_minutes: 0
      },
      attrs
    )
  end

  defp lives(dishes, now), do: dishes |> Planner.plan(@serve, [@oven]) |> Cooking.lives(now)

  # serve 13:30, rest 60 -> out 12:30, cook 120 -> in 10:30, prep 30 -> 10:00
  test "waiting dish follows the plan" do
    [l] = lives([dish(%{})], 9 * 60)
    assert %{phase: :waiting, cook_at: 630, out_at: 750, ready_at: 810} = l
    assert Cooking.projected_serve([l], @serve) == @serve
  end

  test "overdue-to-start dish slides later and pushes dinner back" do
    [l] = lives([dish(%{})], 10 * 60 + 45)
    assert l.cook_at == 10 * 60 + 45
    assert l.ready_at == 10 * 60 + 45 + 120 + 60
    assert Cooking.projected_serve([l], @serve) == l.ready_at
  end

  test "started late: out time follows the actual start" do
    [l] = lives([dish(%{cook_started_at: 11 * 60})], 11 * 60 + 30)
    assert %{phase: :cooking, cook_at: 660, out_at: 780, ready_at: 840, progress: 25} = l
  end

  test "extra time extends the cook and the projected dinner" do
    [l] = lives([dish(%{cook_started_at: 630, extra_minutes: 15})], 12 * 60)
    assert l.out_at == 630 + 135
    assert Cooking.projected_serve([l], @serve) == 765 + 60
  end

  test "out of the oven: resting, then ready" do
    d = dish(%{cook_started_at: 630, cook_done_at: 750})
    assert [%{phase: :resting, ready_at: 810}] = lives([d], 12 * 60 + 40)
    assert [%{phase: :ready}] = lives([d], 13 * 60 + 30)
  end

  test "dishes with no cooking time are ignored" do
    [l] = lives([dish(%{cook_minutes: 0})], 9 * 60)
    assert l.phase == :unscheduled
    assert Cooking.tasks([l], 9 * 60) == []
    assert Cooking.projected_serve([l], @serve) == @serve
  end

  test "tasks: prep, start, out in order, classified against the clock" do
    ls = lives([dish(%{})], 10 * 60 + 20)
    tasks = Cooking.tasks(ls, 10 * 60 + 20)

    assert Enum.map(tasks, &{&1.kind, &1.at, &1.state}) == [
             {:prep, 600, :overdue},
             {:start, 630, :upcoming},
             {:out, 750, :upcoming}
           ]

    near = Cooking.tasks(lives([dish(%{})], 10 * 60 + 27), 10 * 60 + 27)
    assert Enum.find(near, &(&1.kind == :start)).state == :now
  end

  test "completed steps are marked done; taking out implies it was started" do
    d = dish(%{prepped: true, cook_done_at: 740})
    states = lives([d], 12 * 60 + 30) |> Cooking.tasks(750) |> Map.new(&{&1.kind, &1.state})
    assert states == %{prep: :done, start: :done, out: :done}
  end

  test "a pudding served later isn't counted as running behind" do
    pudding = dish(%{id: 2, name: "Pudding", serve_offset_minutes: 60, rest_minutes: 0})
    ls = lives([dish(%{}), pudding], 9 * 60)
    assert Cooking.behind(ls) == 0
    assert Cooking.projected_serve(ls, @serve) == @serve
  end

  test "prep done ahead of the day is not a task, unless it was never ticked" do
    ahead = dish(%{prep_day: :day_before, prepped: true})
    refute Enum.any?(Cooking.tasks(lives([ahead], 9 * 60), 9 * 60), &(&1.kind == :prep))

    missed = dish(%{prep_day: :day_before, prepped: false})
    assert Enum.any?(Cooking.tasks(lives([missed], 9 * 60), 9 * 60), &(&1.kind == :prep))
  end

  test "oven events become tasks, done when ticked or once the dish is in" do
    entries = Planner.plan([dish(%{})], @serve, [@oven])
    [preheat] = Planner.oven_events(entries, [@oven])
    assert preheat.at == 630 - 15

    find = fn tasks -> Enum.find(tasks, &(&1.kind == :preheat)) end

    task = find.(Cooking.tasks(Cooking.lives(entries, 600), 600, [preheat], []))
    assert %{kind: :preheat, at: 615, state: :upcoming, event: ^preheat} = task

    ticked = find.(Cooking.tasks(Cooking.lives(entries, 600), 600, [preheat], [preheat.id]))
    assert ticked.state == :done

    started = Planner.plan([dish(%{cook_started_at: 640})], @serve, [@oven])
    assert find.(Cooking.tasks(Cooking.lives(started, 650), 650, [preheat], [])).state == :done
  end

  test "an oven task follows a dish that is overdue to start" do
    entries = Planner.plan([dish(%{})], @serve, [@oven])
    [preheat] = Planner.oven_events(entries, [@oven])
    # 11:00: the dish should have gone in at 10:30, so it now goes in at 11:00
    tasks = Cooking.tasks(Cooking.lives(entries, 660), 660, [preheat], [])
    assert Enum.find(tasks, &(&1.kind == :preheat)).at == 660 - 15
  end
end
