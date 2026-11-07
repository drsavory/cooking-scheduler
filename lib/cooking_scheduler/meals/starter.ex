defmodule CookingScheduler.Meals.Starter do
  @moduledoc """
  Last year's menu, taken from the "Christmas Food Cooking Times" spreadsheet (2025 tab).
  Each entry is `{attrs, appliance_hint}`; the hint (e.g. "Grill") is matched against the
  user's own appliances when loading. Cooking times are the spreadsheet's *suggested* time
  plus its adjustment as `buffer_minutes`. Rest times are what the sheet used.
  """

  def dishes do
    [
      oven("Turkey (6.1 kg)", 7, 250, 20, 120, 60,
        oven_share: :full,
        link: "https://www.jamieoliver.com/inspiration/how-to-cook-a-turkey-crown/",
        notes:
          "7 then 4 immediately.\nPrep time = take out of the fridge to warm up.\nBacon on turkey for last 30 mins.\n70 °C internal temp.\nBACON LATTICE",
        ingredients_in: true,
        prepped: true
      ),
      oven("Roast potatoes", 4, 90, 10, 15, 0,
        link: "https://www.jamieoliver.com/recipes/potato-recipes/best-roast-potatoes/",
        ingredients_in: true,
        prepped: true
      ),
      oven("Pigs in blankets", 5, 30, 10, 15, 0,
        notes: "Will do 4 for longer.",
        ingredients_in: true,
        prepped: true
      ),
      oven("Fig and almond stuffing", 4, 30, 10, 15, 5,
        link: "https://www.aldi.co.uk/fig-and-almond-stuffing-/p/000000561281500",
        ingredients_in: true,
        prepped: true
      ),
      oven("Chestnut and bacon cake", 7, 70, 10, 15, 20,
        oven_share: :half,
        link: "https://www.bbcgoodfood.com/recipes/chestnut-bacon-cake",
        ingredients_in: true,
        prepped: true
      ),
      oven("Roast veg", 7, 60, 10, 15, 20,
        link: "https://www.bbcgoodfood.com/recipes/roasted-carrots",
        ingredients_in: true,
        prepped: true
      ),
      oven("Salmon", 6, 50, 1, 15, 0, notes: "Will do 7 for shorter."),
      oven("Yorkshire puddings", 8, 15, 10, 0, 0, ingredients_in: true, prepped: true),
      {%{
         name: "Umami sprouts (after hob)",
         method: :appliance,
         prep_minutes: 20,
         cook_minutes: 60,
         buffer_minutes: 10,
         rest_minutes: 15,
         link: "https://umamigirl.com/miso-roasted-brussels-sprouts/",
         notes: "Prep on the 24th."
       }, "grill"},
      hob("Red cabbage and apple", 5, 20,
        link: "https://www.bbc.co.uk/food/recipes/make-ahead_red_cabbage_13106",
        ingredients_in: true,
        prepped: true
      ),
      hob("Steamed veg", 10, 25, ingredients_in: true, notes: "Prep on the 24th."),
      hob("Umami sweet spicy sprouts", 0, 0,
        link: "https://umamigirl.com/miso-roasted-brussels-sprouts/",
        notes: "Use chilli flakes as well. Prep on the 24th.",
        ingredients_in: true
      ),
      hob("Gravy", 0, 60, notes: "Slow cooker", ingredients_in: true),
      {%{
         name: "Grilled potato",
         method: :appliance,
         notes: "Microwave then grill. Prep on the 24th.",
         ingredients_in: true
       }, "grill"}
    ]
  end

  defp oven(name, gas_mark, cook, buffer, rest, prep, extra) do
    {Map.merge(
       %{
         name: name,
         method: :oven,
         temp: gas_mark,
         temp_unit: :gas_mark,
         prep_minutes: prep,
         cook_minutes: cook,
         buffer_minutes: buffer,
         rest_minutes: rest
       },
       Map.new(extra)
     ), nil}
  end

  defp hob(name, prep, cook, extra) do
    {Map.merge(
       %{name: name, method: :ring, ring_size: :medium, prep_minutes: prep, cook_minutes: cook},
       Map.new(extra)
     ), nil}
  end
end
