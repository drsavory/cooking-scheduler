defmodule CookingScheduler.RecipeLinkTest do
  use ExUnit.Case, async: true

  alias CookingScheduler.RecipeLink

  test "names the site, without www" do
    assert RecipeLink.host("https://www.bbcgoodfood.com/recipes/roast-potatoes") ==
             "bbcgoodfood.com"

    assert RecipeLink.host("http://cooking.nytimes.com/x?y=1") == "cooking.nytimes.com"
  end

  test "copes with links typed without a scheme" do
    assert RecipeLink.host("jamieoliver.com/recipes/turkey") == "jamieoliver.com"
  end

  test "nothing to show for blank or hostless links" do
    assert RecipeLink.host(nil) == nil
    assert RecipeLink.host("") == nil
    assert RecipeLink.host("see mum's recipe book") == nil
  end
end
