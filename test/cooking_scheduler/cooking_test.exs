defmodule CookingScheduler.CookingTest do
  use ExUnit.Case, async: true

  alias CookingScheduler.{Cooking, Planner}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meal.Dish

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
      %Dish{
        id: 1,
        name: "Turkey",
        method: :oven,
        temp: 4.0,
        temp_unit: :gas_mark,
        prep_minutes: 30,
        cook_minutes: 120,
        buffer_minutes: 0,
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
end
