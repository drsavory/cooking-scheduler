defmodule CookingScheduler.MealsTest do
  use CookingScheduler.DataCase

  alias CookingScheduler.Meals

  defp dish_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Roast potatoes",
        method: :oven,
        temp: 4,
        temp_unit: :gas_mark,
        prep_minutes: 5,
        cook_minutes: 90,
        buffer_minutes: 10,
        rest_minutes: 15,
        notes: "parboil first",
        link: "https://example.com/roasties"
      },
      overrides
    )
  end

  defp meal(name, date), do: elem(Meals.create_meal(%{name: name, date: date}), 1)

  describe "meals" do
    test "meals are listed most recent first" do
      _old = meal("Christmas 2024", ~D[2024-12-25])
      _new = meal("Christmas 2025", ~D[2025-12-25])
      _mid = meal("Easter 2025", ~D[2025-04-20])

      assert Enum.map(Meals.list_meals(), & &1.name) == [
               "Christmas 2025",
               "Easter 2025",
               "Christmas 2024"
             ]
    end

    test "dishes belong to their meal" do
      a = meal("A", ~D[2025-12-25])
      b = meal("B", ~D[2026-12-25])
      {:ok, _} = Meals.create_dish(a, dish_attrs())

      assert [%{name: "Roast potatoes"}] = Meals.list_dishes(a)
      assert Meals.list_dishes(b) == []
    end

    test "deleting a meal deletes its dishes but not the saved dishes" do
      a = meal("A", ~D[2025-12-25])
      {:ok, dish} = Meals.create_dish(a, dish_attrs())
      assert dish.meal_id == a.id
      {:ok, _} = Meals.delete_meal(a)

      assert Meals.list_dishes(a) == []
      assert [%{name: "Roast potatoes"}] = Meals.list_saved_dishes()
    end
  end

  describe "meal summaries" do
    test "count dishes and prep, and track status and delay per meal" do
      m = meal("Dinner", ~D[2026-12-25])
      {:ok, _} = Meals.update_meal(m, %{serve_at: ~T[13:00:00]})
      {:ok, a} = Meals.create_dish(m, dish_attrs(%{prep_minutes: 10, rest_minutes: 15}))

      {:ok, b} =
        Meals.create_dish(m, dish_attrs(%{name: "Gravy", prep_minutes: 5, rest_minutes: 0}))

      assert [%{dishes: 2, prep_minutes: 15, status: :planning, delay: nil}] =
               Meals.list_meal_summaries()

      {:ok, a} = Meals.start_cooking(a, 600)
      assert [%{status: :cooking, delay: nil}] = Meals.list_meal_summaries()

      # a is out at 12:30 and rests 15m (ready 12:45); b is out at 13:20, 20m late
      {:ok, _} = Meals.finish_cooking(a, 750)
      {:ok, b} = Meals.start_cooking(b, 700)
      {:ok, _} = Meals.finish_cooking(b, 800)

      assert [%{status: :complete, delay: 20}] = Meals.list_meal_summaries()
    end

    test "finishing early marks the meal cooked, ignoring dishes that were skipped" do
      m = meal("Dinner", ~D[2026-12-25])
      {:ok, _} = Meals.update_meal(m, %{serve_at: ~T[13:00:00]})
      {:ok, a} = Meals.create_dish(m, dish_attrs(%{rest_minutes: 0}))
      {:ok, _skipped} = Meals.create_dish(m, dish_attrs(%{name: "Gravy"}))

      {:ok, a} = Meals.start_cooking(a, 600)
      {:ok, _} = Meals.finish_cooking(a, 790)
      assert [%{status: :cooking}] = Meals.list_meal_summaries()

      {:ok, _} = Meals.finish_meal(Meals.get_meal!(m.id))
      assert [%{status: :complete, delay: 10}] = Meals.list_meal_summaries()
    end

    test "resetting takes a cooked or finished meal back to prepping" do
      m = meal("Dinner", ~D[2026-12-25])
      {:ok, a} = Meals.create_dish(m, dish_attrs())
      {:ok, _} = Meals.start_cooking(a, 600)
      {:ok, _} = Meals.finish_meal(m)

      :ok = Meals.reset_cooking(Meals.get_meal!(m.id))
      assert [%{status: :prepping, delay: nil}] = Meals.list_meal_summaries()
      assert Meals.get_meal!(m.id).finished_at == nil
    end

    test "planning moves to prepping by choice, then cooking once a dish starts" do
      m = meal("Dinner", ~D[2026-12-25])
      {:ok, a} = Meals.create_dish(m, dish_attrs())

      {:ok, _} = Meals.set_prep_status(m, :prepping)
      assert [%{status: :prepping}] = Meals.list_meal_summaries()

      {:ok, a} = Meals.start_cooking(a, 600)
      assert [%{status: :cooking}] = Meals.list_meal_summaries()

      {:ok, _} = Meals.undo_start(a)
      assert [%{status: :prepping}] = Meals.list_meal_summaries()
    end

    test "each meal is independent, even with the same dishes" do
      a = meal("A", ~D[2025-12-25])
      {:ok, _} = Meals.create_dish(a, dish_attrs())
      {:ok, b} = Meals.create_meal_from(a)

      [d] = Meals.list_dishes(a)
      {:ok, _} = Meals.start_cooking(d, 700)

      statuses = Map.new(Meals.list_meal_summaries(), &{&1.meal.id, &1.status})
      assert statuses[a.id] == :cooking
      assert statuses[b.id] == :planning
    end
  end

  describe "copying a meal" do
    setup do
      old = meal("Christmas 2025", ~D[2025-12-25])
      {:ok, _} = Meals.update_meal(old, %{serve_at: ~T[14:00:00]})
      {:ok, d} = Meals.create_dish(old, dish_attrs())
      # progress and ticks from the day itself
      {:ok, d} = Meals.set_prepped(d, true)
      {:ok, d} = Meals.start_cooking(d, 700)
      {:ok, d} = Meals.finish_cooking(d, 800)
      {:ok, _} = Meals.add_extra(d, 15)
      %{old: Meals.get_meal!(old.id)}
    end

    test "copies the dishes with their times, not the day's progress", %{old: old} do
      {:ok, new} = Meals.create_meal_from(old)

      assert new.name == "Christmas 2026"
      assert new.serve_at == ~T[14:00:00]
      assert new.id != old.id

      [copy] = Meals.list_dishes(new)

      assert %{
               name: "Roast potatoes",
               cook_minutes: 90,
               buffer_minutes: 10,
               rest_minutes: 15,
               notes: "parboil first",
               link: "https://example.com/roasties",
               prepped: false,
               ingredients_in: false,
               cook_started_at: nil,
               cook_done_at: nil,
               extra_minutes: 0
             } = copy

      # the original is untouched
      [orig] = Meals.list_dishes(old)
      assert orig.cook_started_at == 700 and orig.prepped and orig.extra_minutes == 15
    end

    test "changing the copy leaves the old meal alone", %{old: old} do
      {:ok, new} = Meals.create_meal_from(old)
      [copy] = Meals.list_dishes(new)
      {:ok, _} = Meals.update_dish(copy, %{"cook_minutes" => "2h"})

      assert [%{cook_minutes: 90}] = Meals.list_dishes(old)
      assert [%{cook_minutes: 120}] = Meals.list_dishes(new)
    end

    test "next_name handles names without a year", %{old: old} do
      {:ok, m} = Meals.update_meal(old, %{name: "Sunday lunch"})
      {:ok, copy} = Meals.create_meal_from(m)
      assert copy.name == "Sunday lunch (copy)"
    end
  end

  describe "saved dishes library" do
    test "dishes in an uncooked meal are saved and linked by name" do
      m = meal("Now", ~D[2026-12-25])
      {:ok, dish} = Meals.create_dish(m, dish_attrs())

      assert dish.saved_dish_id || Meals.get_dish!(dish.id).saved_dish_id
      assert [%{name: "Roast potatoes", cook_minutes: 90}] = Meals.list_saved_dishes()
    end

    test "placeholder names are never saved" do
      m = meal("Now", ~D[2026-12-25])
      {:ok, _} = Meals.add_dish(m, :oven, [])
      assert Meals.list_saved_dishes() == []

      [d] = Meals.list_dishes(m)
      {:ok, _} = Meals.update_dish(d, %{"name" => "Nut roast"})
      assert [%{name: "Nut roast"}] = Meals.list_saved_dishes()
    end

    test "editing a dish in an uncooked meal updates the saved version" do
      m = meal("Now", ~D[2026-12-25])
      {:ok, d} = Meals.create_dish(m, dish_attrs())
      d = Meals.get_dish!(d.id)
      {:ok, _} = Meals.update_dish(d, %{"cook_minutes" => "1h"})

      assert [%{cook_minutes: 60}] = Meals.list_saved_dishes()
      # still just one saved dish, still linked
      assert Meals.get_dish!(d.id).saved_dish_id == hd(Meals.list_saved_dishes()).id
    end

    test "editing a dish in a meal that has been cooked does NOT change the saved version" do
      old = meal("Old", ~D[2024-12-25])
      {:ok, d} = Meals.create_dish(old, dish_attrs())
      assert [%{cook_minutes: 90}] = Meals.list_saved_dishes()

      d = Meals.get_dish!(d.id)
      {:ok, d} = Meals.start_cooking(d, 700)
      {:ok, _} = Meals.update_dish(d, %{"cook_minutes" => "5h"})

      assert Meals.get_dish!(d.id).cook_minutes == 300
      assert [%{cook_minutes: 90}] = Meals.list_saved_dishes()
    end

    test "same name in different case is one saved dish" do
      m = meal("Now", ~D[2026-12-25])
      {:ok, _} = Meals.create_dish(m, dish_attrs(%{name: "Gravy"}))
      {:ok, _} = Meals.create_dish(m, dish_attrs(%{name: "gravy"}))
      assert [_one] = Meals.list_saved_dishes()
    end

    test "adding a saved dish to a meal copies it and links back; it's then no longer offered" do
      m1 = meal("Christmas 2025", ~D[2025-12-25])
      {:ok, _} = Meals.create_dish(m1, dish_attrs())
      m2 = meal("Christmas 2026", ~D[2026-12-25])

      [saved] = Meals.saved_dishes_not_in(m2)
      {:ok, d} = Meals.add_saved_dish(m2, saved)

      assert %{name: "Roast potatoes", cook_minutes: 90, saved_dish_id: id} = d
      assert id == saved.id
      assert Meals.saved_dishes_not_in(m2) == []
      assert [_] = Meals.saved_dishes_not_in(meal("Boxing day", ~D[2026-12-26]))
    end

    test "usage history lists every meal a dish was used in, newest first, with what was used" do
      m1 = meal("Christmas 2024", ~D[2024-12-25])
      {:ok, d1} = Meals.create_dish(m1, dish_attrs())
      [saved] = Meals.list_saved_dishes()
      assert Meals.get_dish!(d1.id).saved_dish_id == saved.id

      # next year: add it from the library, cook it longer
      m2 = meal("Christmas 2025", ~D[2025-12-25])
      {:ok, d2} = Meals.add_saved_dish(m2, saved)
      {:ok, _} = Meals.update_dish(d2, %{"cook_minutes" => "2h"})

      assert [{newer, newer_dish}, {older, older_dish}] = Meals.usage_by_saved_dish()[saved.id]
      assert newer.name == "Christmas 2025" and newer_dish.cook_minutes == 120
      assert older.name == "Christmas 2024" and older_dish.cook_minutes == 90
    end

    test "deleting a saved dish keeps the meal dishes" do
      m = meal("Now", ~D[2026-12-25])
      {:ok, d} = Meals.create_dish(m, dish_attrs())
      [saved] = Meals.list_saved_dishes()
      {:ok, _} = Meals.delete_saved_dish(saved)

      assert Meals.get_dish!(d.id).saved_dish_id == nil
      assert [_] = Meals.list_dishes(m)
    end
  end
end
