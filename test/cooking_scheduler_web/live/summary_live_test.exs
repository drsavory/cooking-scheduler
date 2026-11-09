defmodule CookingSchedulerWeb.SummaryLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Meals, Photos}

  @png <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 13>>

  setup do
    {:ok, _} = CookingScheduler.Kitchen.add_oven(:celsius)
    {:ok, meal} = Meals.create_meal(%{name: "Christmas"})

    {:ok, done} =
      Meals.create_meal_dish(meal, %{
        name: "Turkey",
        method: :ring,
        ring_size: :large,
        cook_minutes: 60
      })

    {:ok, skipped} =
      Meals.create_meal_dish(meal, %{
        name: "Sprouts",
        method: :ring,
        ring_size: :small,
        cook_minutes: 10
      })

    {:ok, _} = Meals.start_cooking(done, 600)
    {:ok, _} = Meals.finish_cooking(Meals.get_meal_dish!(done.id), 660)
    {:ok, _} = Meals.finish_meal(Meals.get_meal!(meal.id))

    %{meal: Meals.get_meal!(meal.id), done: done, skipped: skipped}
  end

  defp upload(lv, id, name, content) do
    file_input(lv, "##{id}-form", :photo, [%{name: name, content: content, type: "image/png"}])
    |> render_upload(name)
  end

  test "a meal that isn't finished sends you back to cooking", %{conn: conn} do
    {:ok, open} = Meals.create_meal(%{name: "Sunday"})

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/meals/#{open.id}/summary")
    assert to == "/meals/#{open.id}/cook"
  end

  test "offers photos for the meal and only the dishes that were finished", ctx do
    {:ok, lv, _} = live(ctx.conn, ~p"/meals/#{ctx.meal.id}/summary")

    assert has_element?(lv, "#meal-photos-add")
    assert has_element?(lv, "#dish-photos-#{ctx.done.id}-add")
    refute has_element?(lv, "#dish-photos-#{ctx.skipped.id}-add")
  end

  test "uploads and deletes a photo of the meal", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")

    upload(lv, "meal-photos", "table.png", @png)

    assert [photo] = Photos.list_photos(meal)
    assert has_element?(lv, "#meal-photos-photo-#{photo.id} img")
    assert has_element?(lv, "#meal-photos-delete-#{photo.id}")

    lv |> with_target("#meal-photos") |> render_hook("delete", %{id: photo.id})

    assert Photos.list_photos(meal) == []
    refute has_element?(lv, "#meal-photos-photo-#{photo.id}")
  end

  test "uploads a photo of a dish", %{conn: conn, meal: meal, done: done} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")

    upload(lv, "dish-photos-#{done.id}", "turkey.png", @png)

    assert [photo] = Photos.list_photos(done)
    assert has_element?(lv, "#dish-photos-#{done.id}-photo-#{photo.id} img")
    assert Photos.list_photos(meal) == []
  end

  test "says so when the file isn't a picture", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")

    upload(lv, "meal-photos", "fake.png", "not an image")

    assert Photos.list_photos(meal) == []
    assert has_element?(lv, "#meal-photos-error")
  end

  test "home links a finished meal to its photos", %{conn: conn, meal: meal} do
    {:ok, lv, _} = live(conn, ~p"/")
    assert has_element?(lv, ~s|#summary-meal-#{meal.id}[href="/meals/#{meal.id}/summary"]|)
    refute has_element?(lv, "#cook-meal-#{meal.id}")
  end

  test "shows planned against actual times for every timed dish", %{
    conn: conn,
    meal: meal,
    done: done,
    skipped: skipped
  } do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")
    # planned in 12:30 (serve 13:30 - 60), went in 10:00, out 11:00: 2h 30m early
    assert has_element?(lv, "#actuals-#{done.id}", "12:30")
    assert has_element?(lv, "#actuals-#{done.id}", "10:00")
    assert has_element?(lv, "#actuals-#{done.id}", "11:00")
    assert has_element?(lv, "#actuals-#{done.id}", "2h 30m early")
    assert has_element?(lv, "#actuals-#{skipped.id}", "not cooked")
  end

  test "notes for next time are saved as you type", %{conn: conn, meal: meal, done: done} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")

    lv |> form("#meal-notes-form", meal: %{next_time: "Start an hour earlier"}) |> render_change()
    assert Meals.get_meal!(meal.id).next_time == "Start an hour earlier"

    lv |> form("#dish-notes-#{done.id}", dish: %{next_time: "Brine it"}) |> render_change()
    assert Meals.get_meal_dish!(done.id).next_time == "Brine it"
  end

  test "planning it again uses the times that actually happened", %{
    conn: conn,
    meal: meal,
    done: done
  } do
    {:ok, _} = Meals.add_extra(done, 15)
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/summary")
    {:error, {:live_redirect, %{to: to}}} = lv |> element("#plan-again") |> render_click()

    new = Meals.list_meals() |> Enum.find(&(to == "/meals/#{&1.id}/plan"))
    [turkey, sprouts] = Meals.list_meal_dishes(new) |> Enum.sort_by(& &1.name, :desc)
    # cooked 10:00 to 11:00, so the real time wins over planned + extra
    assert turkey.cook_minutes == 60
    assert turkey.cook_started_at == nil
    # never cooked: the plan stays
    assert sprouts.cook_minutes == 10
  end
end
