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
      assert Meals.list_dishes(meal) == []
    end

    test "a meal can be started from any previous one, not just the latest", %{conn: conn} do
      {:ok, old} = Meals.create_meal(%{name: "Christmas 2024", date: ~D[2024-12-25]})
      {:ok, _} = Meals.add_dish(old, :ring, [])
      {:ok, _newer} = Meals.create_meal(%{name: "Easter 2025", date: ~D[2025-04-20]})

      {:ok, lv, _} = live(conn, ~p"/")

      {:error, {:live_redirect, %{to: to}}} =
        lv |> form("#new-meal-form", %{from: old.id}) |> render_submit()

      new = Meals.list_meals() |> Enum.find(&(to == "/meals/#{&1.id}/plan"))
      assert new.id != old.id
      assert new.name == "Christmas 2025"
      assert length(Meals.list_dishes(new)) == 1
    end

    test "lists meals with their stats and plan/cook links for each", %{conn: conn} do
      {:ok, a} = Meals.create_meal(%{name: "Christmas 2024", date: ~D[2024-12-25]})
      {:ok, b} = Meals.create_meal(%{name: "Easter 2025", date: ~D[2025-04-20]})
      {:ok, _} = Meals.add_dish(a, :ring, [])
      {:ok, _} = Meals.add_dish(a, :ring, [])

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
      {:ok, d} = Meals.create_dish(m, %{name: "Roast", method: :appliance, cook_minutes: 60})
      {:ok, _} = Meals.start_cooking(d, 600)

      {:ok, lv, html} = live(conn, ~p"/")
      assert html =~ "Cooking now"

      confirm_dialog(lv, "finish-meal-#{m.id}")
      refute has_element?(lv, "#finish-meal-#{m.id}")
      assert has_element?(lv, "#meal-#{m.id}", "Complete")

      confirm_dialog(lv, "reset-meal-#{m.id}")
      refute has_element?(lv, "#reset-meal-#{m.id}")
      assert has_element?(lv, "#meal-#{m.id}", "Prepping")
      assert Meals.get_dish!(d.id).cook_started_at == nil
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
      {:ok, d} = Meals.create_saved_dish(%{name: "Gravy", method: :appliance})
      {:ok, lv, _} = live(conn, ~p"/")

      assert has_element?(lv, "#dish-#{d.id}", "Gravy")
      confirm_dialog(lv, "delete-dish-#{d.id}")
      refute has_element?(lv, "#dish-#{d.id}")
    end

    test "dishes show their tags and can be filtered by tag", %{conn: conn} do
      {:ok, beef} =
        Meals.create_saved_dish(%{name: "Beef", method: :appliance, tags: ["main", "protein"]})

      {:ok, peas} = Meals.create_saved_dish(%{name: "Peas", method: :appliance, tags: ["veg"]})
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
end
