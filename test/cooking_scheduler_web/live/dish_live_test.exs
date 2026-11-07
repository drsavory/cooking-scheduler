defmodule CookingSchedulerWeb.DishLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.{Kitchen, Meals}
  alias CookingScheduler.Meals.DishIngredient

  defp attrs(extra),
    do:
      Map.merge(
        %{
          name: "Roast potatoes",
          method: :oven,
          temp: 200.0,
          temp_unit: :celsius,
          cook_minutes: 60
        },
        extra
      )

  setup do
    {:ok, _} = Kitchen.add_oven(:celsius)
    {:ok, meal} = Meals.create_meal(%{name: "Christmas"})

    {:ok, dish} =
      Meals.create_meal_dish(meal, attrs(%{notes: "Par-boil first", rest_minutes: 10}))

    %{meal: meal, dish: dish}
  end

  test "shows a meal dish's cooking details", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")

    assert has_element?(lv, ~s|#dish-form input[name="dish[name]"][value="Roast potatoes"]|)
    assert has_element?(lv, ~s|#dish-form input[name="dish[temp]"][value="200.0"]|)
    assert has_element?(lv, "#dish-form textarea", "Par-boil first")
    assert has_element?(lv, ~s|#dish-back[href="/meals/#{meal.id}/plan"]|)
  end

  test "shows which site a recipe link is from", %{conn: conn, meal: meal} do
    {:ok, dish} =
      Meals.create_meal_dish(
        meal,
        attrs(%{name: "Turkey", link: "https://www.bbcgoodfood.com/turkey"})
      )

    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")
    assert has_element?(lv, "#dish-link-host", "bbcgoodfood.com")
  end

  test "boxes are locked until Edit is pressed", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")

    assert has_element?(lv, "#edit-dish")
    refute has_element?(lv, "#save-dish")
    assert has_element?(lv, ~s|#dish-form input[name="dish[temp]"][readonly]|)

    # a stray change or submit while locked saves nothing
    render_submit(lv, "save", %{"dish" => %{"name" => "Sneaky"}})
    assert Meals.get_meal_dish!(dish.id).name == "Roast potatoes"

    lv |> element("#edit-dish") |> render_click()
    assert has_element?(lv, "#save-dish")
    refute has_element?(lv, "#edit-dish")
    refute has_element?(lv, ~s|#dish-form input[name="dish[temp]"][readonly]|)
  end

  test "changes only save when Save is pressed", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")
    lv |> element("#edit-dish") |> render_click()

    change = [
      dish: %{name: "Crispy potatoes", temp: "210", cook_minutes: "1h 15m", notes: "Hot fat"}
    ]

    lv |> form("#dish-form", change) |> render_change()
    assert Meals.get_meal_dish!(dish.id).name == "Roast potatoes"

    lv |> form("#dish-form", change) |> render_submit()

    assert %{name: "Crispy potatoes", temp: 210.0, cook_minutes: 75, notes: "Hot fat"} =
             Meals.get_meal_dish!(dish.id)

    assert has_element?(lv, "#edit-dish")
    refute has_element?(lv, "#save-dish")
  end

  test "cancel throws changes away", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")
    lv |> element("#edit-dish") |> render_click()
    lv |> form("#dish-form", dish: %{name: "Changed"}) |> render_change()

    lv |> element("#cancel-edit") |> render_click()

    assert has_element?(lv, ~s|#dish-form input[name="dish[name]"][value="Roast potatoes"]|)
    assert Meals.get_meal_dish!(dish.id).name == "Roast potatoes"
  end

  test "a bad value shows an error and won't save", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")
    lv |> element("#edit-dish") |> render_click()

    html = lv |> form("#dish-form", dish: %{cook_minutes: "soon"}) |> render_submit()

    assert html =~ "text-error"
    assert has_element?(lv, "#save-dish")
    assert Meals.get_meal_dish!(dish.id).cook_minutes == 60
  end

  test "edits a library dish in place", %{conn: conn} do
    {:ok, saved} = Meals.create_dish(attrs(%{name: "Gravy"}))
    {:ok, lv, _} = live(conn, ~p"/dishes/#{saved.id}")

    lv |> element("#edit-dish") |> render_click()
    lv |> form("#dish-form", dish: %{rest_minutes: "5"}) |> render_submit()
    assert Meals.get_dish!(saved.id).rest_minutes == 5
  end

  test "comes back to the cook screen when opened from it", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}?from=cook")
    assert has_element?(lv, ~s|#dish-back[href="/meals/#{meal.id}/cook"]|)
  end

  test "a dish from another meal isn't found", %{conn: conn, dish: dish} do
    {:ok, other} = Meals.create_meal(%{name: "Other"})

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/meals/#{other.id}/dishes/#{dish.id}")
    end
  end

  test "adds and removes ingredients", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")
    assert has_element?(lv, "#no-ingredients")

    lv
    |> form("#ingredient-form", ingredient: %{name: "Potatoes", amount: "2", unit: "kg"})
    |> render_submit()

    assert_push_event(lv, "focus", %{id: "ingredient_name"})
    assert has_element?(lv, "#ingredient_name")
    [di] = Meals.list_dish_ingredients(dish)
    assert has_element?(lv, "#ingredient-#{di.id}", "Potatoes")
    assert has_element?(lv, "#ingredient-#{di.id}", "2 kg")

    lv |> element("#remove-ingredient-#{di.id}") |> render_click()
    refute has_element?(lv, "#ingredient-#{di.id}")
    assert Meals.list_dish_ingredients(dish) == []
    # the ingredient itself stays available for other dishes
    assert [%{name: "Potatoes"}] = Meals.list_ingredients()
  end

  test "a blank ingredient name is refused", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")

    lv |> form("#ingredient-form", ingredient: %{name: "  ", amount: "1"}) |> render_submit()

    assert has_element?(lv, "#ingredient-error")
    assert Meals.list_dish_ingredients(dish) == []
  end

  test "views and edits ingredients of a library dish", %{conn: conn} do
    {:ok, saved} = Meals.create_dish(attrs(%{name: "Gravy"}))
    {:ok, lv, _} = live(conn, ~p"/dishes/#{saved.id}")

    assert has_element?(lv, ~s|#dish-form input[name="dish[name]"][value="Gravy"]|)
    refute has_element?(lv, "#dish-edit")

    lv |> form("#ingredient-form", ingredient: %{name: "Stock"}) |> render_submit()
    assert [%{ingredient: %{name: "Stock"}}] = Meals.list_dish_ingredients(saved)
  end

  test "dishes link here from home, plan and cook", %{conn: conn, meal: meal, dish: dish} do
    {:ok, saved} = Meals.create_dish(attrs(%{name: "Gravy"}))

    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, ~s|#view-dish-#{saved.id}[href="/dishes/#{saved.id}"]|)

    {:ok, plan, _} = live(conn, ~p"/meals/#{meal.id}/plan")

    assert has_element?(
             plan,
             ~s|#view-dish-#{dish.id}[href="/meals/#{meal.id}/dishes/#{dish.id}"]|
           )

    {:ok, cook, _} = live(conn, ~p"/meals/#{meal.id}/cook")
    assert has_element?(cook, "#details-#{dish.id}-start")
  end

  test "a bad amount is refused and nothing is saved", %{conn: conn, meal: meal, dish: dish} do
    {:ok, lv, _} = live(conn, ~p"/meals/#{meal.id}/dishes/#{dish.id}")

    lv
    |> form("#ingredient-form", ingredient: %{name: "Flour", amount: "lots", unit: "g"})
    |> render_submit()

    assert has_element?(lv, "#ingredient-error")
    assert Meals.list_dish_ingredients(dish) == []
  end

  test "a count has no unit, and a unit without an amount is dropped", %{dish: dish} do
    {:ok, onions} = Meals.add_ingredient(dish, "Onions", "2")
    assert %{amount: 2.0, unit: nil} = onions
    assert DishIngredient.format(onions) == "2 items"

    {:ok, salt} = Meals.add_ingredient(dish, "Salt", "", "tsp")
    assert %{amount: nil, unit: nil} = salt
    assert DishIngredient.format(salt) == nil
  end

  describe "reading amounts" do
    test "decimals, fractions and mixed numbers" do
      assert DishIngredient.parse_amount("50") == {:ok, 50.0}
      assert DishIngredient.parse_amount("1,5") == {:ok, 1.5}
      assert DishIngredient.parse_amount(".5") == {:ok, 0.5}
      assert DishIngredient.parse_amount("1/2") == {:ok, 0.5}
      assert DishIngredient.parse_amount("1 1/2") == {:ok, 1.5}
      assert DishIngredient.parse_amount("  ") == {:ok, nil}
    end

    test "rejects words, zero, negatives and divide-by-zero" do
      for bad <- ["lots", "0", "-1", "1/0", "2kg"] do
        assert DishIngredient.parse_amount(bad) == :error, bad
      end
    end
  end

  describe "ingredients are shared and carried between dishes" do
    test "the same ingredient (any case) is one record used by many dishes", %{
      meal: meal,
      dish: dish
    } do
      {:ok, other} = Meals.create_meal_dish(meal, attrs(%{name: "Parsnips"}))
      {:ok, _} = Meals.add_ingredient(dish, "Butter", "50", "g")
      {:ok, _} = Meals.add_ingredient(other, " butter ", "20", "g")

      assert [%{name: "Butter"}] = Meals.list_ingredients()
      assert [%{amount: 50.0, unit: :g}] = Meals.list_dish_ingredients(dish)
      assert [%{amount: 20.0, unit: :g}] = Meals.list_dish_ingredients(other)
    end

    test "re-adding an ingredient updates its amount", %{dish: dish} do
      {:ok, _} = Meals.add_ingredient(dish, "Salt", "1", "tsp")
      {:ok, _} = Meals.add_ingredient(dish, "salt", "1/2", "tbsp")
      assert [%{amount: 0.5, unit: :tbsp}] = Meals.list_dish_ingredients(dish)
    end

    test "ingredients are copied with the dish into a new meal and from the library", %{
      meal: meal,
      dish: dish
    } do
      {:ok, _} = Meals.add_ingredient(dish, "Potatoes", "2", "kg")

      {:ok, next} = Meals.create_meal_from(meal)
      [copy] = Meals.list_meal_dishes(next)
      assert [%{amount: 2.0, unit: :kg}] = Meals.list_dish_ingredients(copy)

      # editing the copy leaves the original meal alone
      {:ok, _} = Meals.add_ingredient(copy, "Goose fat")
      assert length(Meals.list_dish_ingredients(dish)) == 1

      # ...and the library dish picked up the ingredients, so a fresh meal gets them too
      saved =
        Meals.get_dish!(dish |> then(&Meals.get_meal_dish!(&1.id)) |> Map.fetch!(:dish_id))

      {:ok, fresh} = Meals.create_meal(%{name: "Fresh"})
      {:ok, added} = Meals.add_dish_to_meal(fresh, saved)
      assert length(Meals.list_dish_ingredients(added)) >= 1
    end

    test "ingredients added to a library dish reach unstarted meals only", %{
      meal: meal,
      dish: dish
    } do
      saved = Meals.get_dish!(Meals.get_meal_dish!(dish.id).dish_id)
      {:ok, cooking} = Meals.create_meal_from(meal)
      [cooked] = Meals.list_meal_dishes(cooking)
      {:ok, _} = Meals.start_cooking(cooked, 600)

      {:ok, _} = Meals.add_ingredient(saved, "Goose fat", "2", "tbsp")

      assert [%{ingredient: %{name: "Goose fat"}, amount: 2.0}] =
               Meals.list_dish_ingredients(Meals.get_meal_dish!(dish.id))

      assert Meals.list_dish_ingredients(Meals.get_meal_dish!(cooked.id)) == []

      [di] = Meals.list_dish_ingredients(saved)
      {:ok, _} = Meals.remove_ingredient(saved, di)
      assert Meals.list_dish_ingredients(Meals.get_meal_dish!(dish.id)) == []
    end
  end

  test "tags on a saved dish can be edited", %{conn: conn} do
    {:ok, saved} = Meals.create_dish(%{name: "Sprouts", method: :appliance, tags: ["veg"]})
    {:ok, lv, _} = live(conn, ~p"/dishes/#{saved.id}")

    assert has_element?(lv, "#tag-option-veg")
    refute has_element?(lv, "#tag-option-main")

    lv |> element("#edit-dish") |> render_click()
    lv |> form("#dish-form", dish: %{tags: ["veg", "side"]}) |> render_submit()

    assert Meals.get_dish!(saved.id).tags == ["veg", "side"]
  end

  describe "photos" do
    @png <<0x89, "PNG\r\n", 0x1A, "\n", 0, 0, 0, 13>>

    defp photo_for(owner) do
      path = Path.join(System.tmp_dir!(), "dl-#{System.unique_integer([:positive])}")
      File.write!(path, @png)
      {:ok, photo} = CookingScheduler.Photos.add_photo(owner, path, "x.png")
      photo
    end

    test "a library dish shows photos from every meal it was cooked in", %{conn: conn, dish: dish} do
      library = Meals.get_dish!(Meals.get_meal_dish!(dish.id).dish_id)
      {:ok, other} = Meals.create_meal(%{name: "Easter"})
      {:ok, other_dish} = Meals.add_dish_to_meal(other, library)
      a = photo_for(dish)
      b = photo_for(other_dish)

      {:ok, lv, _} = live(conn, ~p"/dishes/#{library.id}")

      assert has_element?(lv, "#dish-photo-#{a.id} img")
      assert has_element?(lv, "#dish-photo-#{b.id} img")
      assert has_element?(lv, ~s|#dish-photo-meal-#{b.id}[href="/meals/#{other.id}/summary"]|)
    end

    test "a meal dish shows its own photos, and a hint when there are none", ctx do
      {:ok, lv, _} = live(ctx.conn, ~p"/meals/#{ctx.meal.id}/dishes/#{ctx.dish.id}")
      assert has_element?(lv, "#no-photos")

      photo = photo_for(ctx.dish)
      {:ok, lv, _} = live(ctx.conn, ~p"/meals/#{ctx.meal.id}/dishes/#{ctx.dish.id}")
      assert has_element?(lv, "#dish-photo-#{photo.id} img")
    end
  end
end
