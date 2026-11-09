defmodule CookingSchedulerWeb.HomeLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Kitchen, Meals}

  test "first visit goes to setup", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/setup"}}} = live(conn, ~p"/")
  end

  describe "with a kitchen" do
    setup do
      {:ok, _} = Kitchen.add_oven(:gas_mark)
      {:ok, _} = Kitchen.adjust_rings(:large, 1)
      :ok
    end

    test "links to kitchen settings", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/")

      {:ok, _lv, setup} =
        lv |> element("#edit-kitchen") |> render_click() |> follow_redirect(conn, ~p"/setup")

      assert setup =~ "Set up your kitchen"
    end

    test "spotlight is present and answers searches", %{conn: conn} do
      {:ok, meal} = Meals.create_meal()
      {:ok, lv, _} = live(conn, ~p"/")

      assert has_element?(lv, "#spotlight[phx-hook]")
      assert has_element?(lv, "#open-search")

      render_hook(lv, "spotlight_search", %{"q" => meal.name})
      assert_reply(lv, %{meals: [%{id: id}]})
      assert id == meal.id

      render_hook(lv, "spotlight_search", %{"q" => "home"})
      assert_reply(lv, %{pages: [%{id: "home", href: "/"}], meals: [], dishes: []})

      render_hook(lv, "spotlight_search", %{"q" => "zzz-no-match"})
      assert_reply(lv, %{pages: [], meals: [], dishes: []})
    end

    test "spotlight is available on other pages", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/dishes/new")
      assert has_element?(lv, "#spotlight[phx-hook]")
    end

    test "create dish goes to the dish form", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/")

      {:ok, _lv, html} =
        lv |> element("#create-dish") |> render_click() |> follow_redirect(conn, ~p"/dishes/new")

      assert html =~ "dish-form"
    end

    test "creating a meal from scratch opens its plan", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/")
      {:error, {:live_redirect, %{to: to}}} = lv |> form("#new-meal-form") |> render_submit()

      [meal] = Meals.list_meals()
      assert to == "/meals/#{meal.id}/plan"
      assert Meals.list_meal_dishes(meal) == []
    end

    test "a meal can be started from any previous one, not just the latest", %{conn: conn} do
      {:ok, old} = Meals.create_meal(%{name: "Christmas 2024", date: ~D[2024-12-25]})
      {:ok, _} = Meals.add_meal_dish(old, :ring, [])
      {:ok, _newer} = Meals.create_meal(%{name: "Easter 2025", date: ~D[2025-04-20]})

      {:ok, lv, _} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> form("#new-meal-form", %{from: old.id}) |> render_submit()

      new = Meals.list_meals() |> Enum.find(&(to == "/meals/#{&1.id}/plan"))
      assert new.id != old.id
      assert new.name == "Christmas 2025"
      assert length(Meals.list_meal_dishes(new)) == 1
    end

    test "lists meals with their stats and plan/cook links for each", %{conn: conn} do
      {:ok, a} = Meals.create_meal(%{name: "Christmas 2024", date: ~D[2024-12-25]})
      {:ok, b} = Meals.create_meal(%{name: "Easter 2025", date: ~D[2025-04-20]})
      {:ok, _} = Meals.add_meal_dish(a, :ring, [])
      {:ok, _} = Meals.add_meal_dish(a, :ring, [])

      {:ok, lv, _} = live(conn, ~p"/")

      assert has_element?(lv, "#meal-#{a.id}", "2 dishes")
      assert has_element?(lv, "#meal-#{b.id}", "0 dishes")

      for m <- [a, b] do
        assert has_element?(lv, ~s|#plan-meal-#{m.id}[href="/meals/#{m.id}/plan"]|)
        assert has_element?(lv, ~s|#cook-meal-#{m.id}[href="/meals/#{m.id}/cook"]|)
      end
    end

    test "a meal that's being cooked can be finished or reset from home", %{conn: conn} do
      {:ok, m} = Meals.create_meal(%{name: "Dinner"})
      {:ok, d} = Meals.create_meal_dish(m, %{name: "Roast", method: :appliance, cook_minutes: 60})
      {:ok, _} = Meals.start_cooking(d, 600)

      {:ok, lv, html} = live(conn, ~p"/")
      assert html =~ "Cooking now"

      confirm_dialog(lv, "finish-meal-#{m.id}")
      refute has_element?(lv, "#finish-meal-#{m.id}")
      assert has_element?(lv, "#meal-#{m.id}", "Complete")

      confirm_dialog(lv, "reset-meal-#{m.id}")
      refute has_element?(lv, "#reset-meal-#{m.id}")
      assert has_element?(lv, "#meal-#{m.id}", "Prepping")
      assert Meals.get_meal_dish!(d.id).cook_started_at == nil
    end

    test "a planning meal can be moved to prepping and back", %{conn: conn} do
      {:ok, m} = Meals.create_meal(%{name: "Dinner"})
      {:ok, lv, _} = live(conn, ~p"/")
      assert has_element?(lv, "#meal-#{m.id}", "Planning")

      lv |> element("#start-prepping-#{m.id}") |> render_click()
      assert_redirect(lv, ~p"/meals/#{m.id}/prep")
      assert Meals.get_meal!(m.id).status == :prepping

      {:ok, lv, _} = live(conn, ~p"/")
      assert has_element?(lv, "#meal-#{m.id}", "Prepping")
      assert has_element?(lv, "#prep-meal-#{m.id}")
      lv |> element("#back-to-planning-#{m.id}") |> render_click()
      assert Meals.get_meal!(m.id).status == :planning
    end

    test "lists dishes and can delete one", %{conn: conn} do
      {:ok, d} = Meals.create_dish(%{name: "Gravy", method: :appliance})
      {:ok, lv, _} = live(conn, ~p"/")

      assert has_element?(lv, "#dish-#{d.id}", "Gravy")
      confirm_dialog(lv, "delete-dish-#{d.id}")
      refute has_element?(lv, "#dish-#{d.id}")
    end

    test "dishes show their tags and can be filtered by tag", %{conn: conn} do
      {:ok, beef} =
        Meals.create_dish(%{name: "Beef", method: :appliance, tags: ["main", "protein"]})

      {:ok, peas} = Meals.create_dish(%{name: "Peas", method: :appliance, tags: ["veg"]})
      {:ok, lv, _} = live(conn, ~p"/")

      assert has_element?(lv, "#dish-tags-#{beef.id}", "protein")
      lv |> element("#tag-filter-veg") |> render_click()
      assert has_element?(lv, "#dish-#{peas.id}")
      refute has_element?(lv, "#dish-#{beef.id}")

      lv |> element("#tag-filter-veg") |> render_click()
      assert has_element?(lv, "#dish-#{beef.id}")
    end

    test "destructive actions only happen when confirmed, via an in-app dialog", %{conn: conn} do
      {:ok, m} = Meals.create_meal(%{name: "Dinner"})
      {:ok, lv, html} = live(conn, ~p"/")

      # the trigger only opens the dialog (client-side); rendering never deletes anything
      assert has_element?(lv, "#delete-meal-#{m.id}")
      assert Meals.get_meal!(m.id)

      assert render(lv) =~ ~s|id="delete-meal-#{m.id}-dialog-cancel"|
      refute html =~ "data-confirm"

      confirm_dialog(lv, "delete-meal-#{m.id}")
      assert Meals.list_meals() == []
    end
  end

  describe "next up and the new meal form" do
    setup do
      {:ok, _} = Kitchen.add_oven(:gas_mark)
      :ok
    end

    test "the soonest unfinished meal is the hero, with the right next step", %{conn: conn} do
      {:ok, past} = Meals.create_meal(%{name: "Easter 2025", date: ~D[2025-04-20]})

      {:ok, soon} =
        Meals.create_meal(%{name: "Christmas 2026", date: Date.add(Date.utc_today(), 3)})

      {:ok, _later} = Meals.create_meal(%{name: "New Year", date: Date.add(Date.utc_today(), 10)})
      {:ok, _} = Meals.set_prep_status(soon, :prepping)

      {:ok, lv, _} = live(conn, ~p"/")
      assert has_element?(lv, "#next-up", "Christmas 2026")
      assert has_element?(lv, "#next-up", "in 3 days")
      assert has_element?(lv, ~s|#next-prep[href="/meals/#{soon.id}/prep"]|)
      _ = past
    end

    test "a new meal takes its name, date and time from the form", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: to}}} =
        lv
        |> form("#new-meal-form",
          meal: %{name: "Boxing Day", date: "2026-12-26", serve_at: "15:00"}
        )
        |> render_submit()

      [meal] = Meals.list_meals()
      assert to == "/meals/#{meal.id}/plan"
      assert %{name: "Boxing Day", date: ~D[2026-12-26], serve_at: ~T[15:00:00]} = meal
    end

    test "starting from a cooked meal can use the real times", %{conn: conn} do
      {:ok, old} = Meals.create_meal(%{name: "Christmas 2025", date: ~D[2025-12-25]})

      {:ok, d} =
        Meals.create_meal_dish(old, %{
          name: "Turkey",
          method: :ring,
          ring_size: :large,
          cook_minutes: 60
        })

      {:ok, _} = Meals.start_cooking(d, 600)
      {:ok, _} = Meals.finish_cooking(Meals.get_meal_dish!(d.id), 690)
      {:ok, _} = Meals.finish_meal(Meals.get_meal!(old.id))

      {:ok, lv, _} = live(conn, ~p"/")
      assert has_element?(lv, "#new-meal-actual")
      # out at 11:30 for a 13:30 dinner
      assert has_element?(lv, "#last-cooked-#{Meals.get_meal_dish!(d.id).dish_id}", "2h early")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> form("#new-meal-form", %{from: old.id, actual_times: "true"}) |> render_submit()

      new = Meals.list_meals() |> Enum.find(&(to == "/meals/#{&1.id}/plan"))
      assert [%{cook_minutes: 90}] = Meals.list_meal_dishes(new)
    end

    test "spotlight finds dishes by ingredient", %{conn: conn} do
      {:ok, dish} = Meals.create_dish(%{name: "Sprouts", method: :ring, ring_size: :small})
      {:ok, _} = Meals.add_ingredient(dish, "Chestnuts", 100, :g)
      {:ok, lv, _} = live(conn, ~p"/")

      render_hook(lv, "spotlight_search", %{"q" => "chest"})
      assert_reply(lv, %{dishes: [%{label: "Sprouts", sub: sub}]})
      assert sub =~ "uses Chestnuts"
    end
  end
end
