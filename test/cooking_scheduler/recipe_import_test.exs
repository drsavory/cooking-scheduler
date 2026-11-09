defmodule CookingScheduler.RecipeImportTest do
  use ExUnit.Case, async: false

  alias CookingScheduler.RecipeImport

  @page """
  <html><head>
  <script type="application/ld+json">
  {"@context":"https://schema.org","@graph":[
    {"@type":"WebPage","name":"Site"},
    {"@type":["Recipe"],"name":"Best roast potatoes","prepTime":"PT15M","cookTime":"PT1H40M",
     "recipeIngredient":["2.5 kg Maris Piper potatoes","3 tbsp goose fat","1 bulb of garlic","sea salt"]}
  ]}
  </script>
  </head><body>hi</body></html>
  """

  test "reads the recipe out of JSON-LD, including a @graph" do
    assert {:ok, recipe} = RecipeImport.parse(@page)
    assert recipe.name == "Best roast potatoes"
    assert recipe.prep_minutes == 15
    assert recipe.cook_minutes == 100
    assert length(recipe.ingredients) == 4
  end

  test "a page with no recipe says so" do
    assert {:error, :no_recipe} = RecipeImport.parse("<html><body>nothing</body></html>")
  end

  test "ISO durations" do
    assert RecipeImport.duration("PT1H30M") == 90
    assert RecipeImport.duration("P0DT0H45M") == 45
    assert RecipeImport.duration("PT2H") == 120
    assert RecipeImport.duration("PT0M") == nil
    assert RecipeImport.duration("soon") == nil
  end

  test "uses the total time when there's no cook time" do
    page =
      ~s(<script type="application/ld+json">{"@type":"Recipe","name":"X","prepTime":"PT10M","totalTime":"PT1H"}</script>)

    assert {:ok, %{cook_minutes: 50}} = RecipeImport.parse(page)
  end

  test "fetches a page through Req" do
    page = @page

    Application.put_env(:cooking_scheduler, :recipe_import_req,
      plug: fn conn -> Plug.Conn.send_resp(conn, 200, page) end
    )

    on_exit(fn -> Application.delete_env(:cooking_scheduler, :recipe_import_req) end)

    assert {:ok, %{name: "Best roast potatoes", link: "https://example.com/roasties"}} =
             RecipeImport.fetch("example.com/roasties")

    assert {:error, :bad_link} = RecipeImport.fetch("not a link")
  end

  test "an unreachable page is an error, not a crash" do
    Application.put_env(:cooking_scheduler, :recipe_import_req,
      plug: fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end
    )

    on_exit(fn -> Application.delete_env(:cooking_scheduler, :recipe_import_req) end)
    assert {:error, :unreachable} = RecipeImport.fetch("https://example.com/x")
  end
end
