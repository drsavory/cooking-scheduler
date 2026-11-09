defmodule CookingSchedulerWeb.DishFormLiveTest do
  use CookingSchedulerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias CookingScheduler.Meals

  test "creates a dish and opens it", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    lv
    |> form("#dish-form",
      dish: %{name: "Nut roast", temp: "6", cook_minutes: "1h 10m", rest_minutes: "0:15"}
    )
    |> render_submit()

    assert [%{id: id, name: "Nut roast", temp: 6.0, cook_minutes: 70, rest_minutes: 15}] =
             Meals.list_dishes()

    assert_redirect(lv, ~p"/dishes/#{id}")
  end

  test "refuses a name that is already a dish, in any case", %{conn: conn} do
    {:ok, _} = Meals.create_dish(%{name: "Gravy", method: :ring, ring_size: :medium})
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    html = lv |> form("#dish-form", dish: %{name: "gravy", temp: "6"}) |> render_submit()

    assert html =~ "is already a dish"
    assert [%{name: "Gravy"}] = Meals.list_dishes()
  end

  test "flags bad input and saves nothing", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    html =
      lv
      |> form("#dish-form", dish: %{name: "", cook_minutes: "soon"})
      |> render_change()

    assert html =~ "try 1:30"
    assert html =~ "can&#39;t be blank"
    assert Meals.list_dishes() == []
  end

  test "hob dishes ask for a ring size instead of a temperature", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")
    lv |> form("#dish-form", dish: %{method: "ring"}) |> render_change()

    assert has_element?(lv, "#dish-form select[name='dish[ring_size]']")
    refute has_element?(lv, "#dish-form input[name='dish[temp]']")
  end

  test "saves picked and typed tags, tidied", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    lv
    |> form("#dish-form",
      dish: %{
        name: "Gravy",
        temp: "6",
        tags: ["sauce", "main"],
        custom_tags: " Festive, sauce ,"
      }
    )
    |> render_submit()

    assert [%{tags: ["sauce", "main", "festive"]}] = Meals.list_dishes()
  end

  test "import fills the form from a recipe link and adds its ingredients on save", %{conn: conn} do
    page =
      ~s(<script type="application/ld+json">{"@type":"Recipe","name":"Nut roast","prepTime":"PT20M","cookTime":"PT1H","recipeIngredient":["200 g mixed nuts","1 onion"]}</script>)

    Application.put_env(:cooking_scheduler, :recipe_import_req,
      plug: fn conn -> Plug.Conn.send_resp(conn, 200, page) end
    )

    on_exit(fn -> Application.delete_env(:cooking_scheduler, :recipe_import_req) end)

    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    lv
    |> form("#dish-form", dish: %{link: "https://example.com/nut-roast", temp: "6"})
    |> render_change()

    lv |> element("#import-recipe") |> render_click()
    html = render_async(lv)

    assert html =~ "Nut roast"
    assert has_element?(lv, "#imported-ingredients", "2 ingredients")

    lv |> form("#dish-form", dish: %{temp: "6"}) |> render_submit()
    [dish] = Meals.list_dishes()
    assert %{name: "Nut roast", prep_minutes: 20, cook_minutes: 60} = dish
    assert length(Meals.list_dish_ingredients(dish)) == 2
  end

  test "course and prep timing can be chosen for a new dish", %{conn: conn} do
    {:ok, lv, _} = live(conn, ~p"/dishes/new")

    lv
    |> form("#dish-form",
      dish: %{name: "Trifle", temp: "4", serve_offset_minutes: "60", prep_day: "day_before"}
    )
    |> render_submit()

    assert [%{serve_offset_minutes: 60, prep_day: :day_before}] = Meals.list_dishes()
  end
end
