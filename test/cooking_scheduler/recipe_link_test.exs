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

  test "web addresses and plain text are fine in a link, other schemes are not" do
    for ok <- ["https://x.com/r", "HTTP://x.com", "x.com/recipe", "see mum's recipe book", ""] do
      assert RecipeLink.web?(ok), ok
    end

    for bad <- ["javascript:alert(1)", "JavaScript:x", " java\tscript:x", "data:text/html,hi"] do
      refute RecipeLink.web?(bad), bad
    end

    refute RecipeLink.web?(nil)
  end
end
