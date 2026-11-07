defmodule CookingScheduler.UnitConversion do
  @moduledoc """
  Pure kitchen unit conversion for temperature, weight and volume.

  Units may be given as atoms (`:tbsp`) or as the ways people write them
  (`"Tbsp"`, `"tablespoons"`, `"°F"`, `"fl oz"`). Volumes are US customary
  (1 cup = 236.588 ml). Conversions only work within a category.

      iex> CookingScheduler.UnitConversion.convert(350, :f, :c, round: 0)
      {:ok, 177.0}

      iex> CookingScheduler.UnitConversion.convert(2, "tbsp", "tsp")
      {:ok, 6.0}

      iex> CookingScheduler.UnitConversion.convert(1, :cup, :g)
      {:error, :incompatible_units}
  """

  @type unit ::
          :c
          | :f
          | :gas_mark
          | :mg
          | :g
          | :kg
          | :oz
          | :lb
          | :ml
          | :l
          | :tsp
          | :tbsp
          | :fl_oz
          | :cup
          | :pint
          | :quart
          | :gallon
  @type category :: :temperature | :weight | :volume
  @type error ::
          :unknown_unit
          | :incompatible_units
          | :invalid_value
          | :out_of_range
          | :unknown_ingredient

  # Factors to the base unit of each category (grams / millilitres).
  @weights %{mg: 0.001, g: 1.0, kg: 1000.0, oz: 28.349523125, lb: 453.59237}

  @volumes %{
    ml: 1.0,
    l: 1000.0,
    tsp: 4.92892159375,
    tbsp: 14.78676478125,
    fl_oz: 29.5735295625,
    cup: 236.5882365,
    pint: 473.176473,
    quart: 946.352946,
    gallon: 3785.411784
  }

  @temperatures [:c, :f, :gas_mark]

  # UK gas marks and their usual Celsius equivalents. Gas mark is a stepped
  # scale, so converting *to* it picks the nearest mark.
  @gas_marks [
    {0.25, 110},
    {0.5, 130},
    {1, 140},
    {2, 150},
    {3, 170},
    {4, 180},
    {5, 190},
    {6, 200},
    {7, 220},
    {8, 230},
    {9, 240},
    {10, 260}
  ]
  @gas_tolerance 15

  @aliases %{
    "c" => :c,
    "°c" => :c,
    "celsius" => :c,
    "centigrade" => :c,
    "f" => :f,
    "°f" => :f,
    "fahrenheit" => :f,
    "gas mark" => :gas_mark,
    "gas" => :gas_mark,
    "gm" => :gas_mark,
    "gasmark" => :gas_mark,
    "gas_mark" => :gas_mark,
    "mg" => :mg,
    "milligram" => :mg,
    "milligrams" => :mg,
    "g" => :g,
    "gram" => :g,
    "grams" => :g,
    "gr" => :g,
    "kg" => :kg,
    "kgs" => :kg,
    "kilo" => :kg,
    "kilos" => :kg,
    "kilogram" => :kg,
    "kilograms" => :kg,
    "oz" => :oz,
    "ounce" => :oz,
    "ounces" => :oz,
    "lb" => :lb,
    "lbs" => :lb,
    "pound" => :lb,
    "pounds" => :lb,
    "ml" => :ml,
    "millilitre" => :ml,
    "millilitres" => :ml,
    "milliliter" => :ml,
    "milliliters" => :ml,
    "l" => :l,
    "litre" => :l,
    "litres" => :l,
    "liter" => :l,
    "liters" => :l,
    "tsp" => :tsp,
    "teaspoon" => :tsp,
    "teaspoons" => :tsp,
    "t" => :tsp,
    "tbsp" => :tbsp,
    "tbs" => :tbsp,
    "tablespoon" => :tbsp,
    "tablespoons" => :tbsp,
    "tbl" => :tbsp,
    "fl oz" => :fl_oz,
    "floz" => :fl_oz,
    "fl_oz" => :fl_oz,
    "fluid ounce" => :fl_oz,
    "fluid ounces" => :fl_oz,
    "cup" => :cup,
    "cups" => :cup,
    "pint" => :pint,
    "pints" => :pint,
    "pt" => :pint,
    "quart" => :quart,
    "quarts" => :quart,
    "qt" => :quart,
    "gallon" => :gallon,
    "gallons" => :gallon,
    "gal" => :gallon
  }

  # Approximate grams per US cup, in line with common baking charts (e.g. King
  # Arthur). Real values vary with packing and sifting.
  @cup_grams %{
    generic: 237,
    water: 237,
    milk: 245,
    cream: 232,
    yogurt: 245,
    oil: 216,
    honey: 336,
    maple_syrup: 322,
    butter: 227,
    flour: 120,
    bread_flour: 120,
    whole_wheat_flour: 113,
    cake_flour: 114,
    sugar: 200,
    brown_sugar: 213,
    icing_sugar: 113,
    cocoa: 85,
    oats: 90,
    rice: 185,
    salt: 288
  }

  @ingredient_aliases Map.merge(
                        Map.new(Map.keys(@cup_grams), &{Atom.to_string(&1), &1}),
                        %{
                          "all_purpose_flour" => :flour,
                          "plain_flour" => :flour,
                          "ap_flour" => :flour,
                          "strong_flour" => :bread_flour,
                          "wholemeal_flour" => :whole_wheat_flour,
                          "granulated_sugar" => :sugar,
                          "caster_sugar" => :sugar,
                          "white_sugar" => :sugar,
                          "powdered_sugar" => :icing_sugar,
                          "confectioners_sugar" => :icing_sugar,
                          "cocoa_powder" => :cocoa,
                          "rolled_oats" => :oats,
                          "olive_oil" => :oil,
                          "vegetable_oil" => :oil,
                          "double_cream" => :cream,
                          "heavy_cream" => :cream,
                          "table_salt" => :salt
                        }
                      )

  @doc """
  Converts `value` from one unit to another.

  Options:

    * `:round` - number of decimal places to round the result to
    * `:ingredient` - needed to convert between volume and weight (cups to
      grams and back). Uses a rough per-ingredient density, see `ingredients/0`.
      Use `:generic` for a water-like 1 ml = 1 g estimate.

  Cup weights vary with how an ingredient is packed and sifted, so treat
  volume/weight results as approximate.
  """
  @spec convert(number, unit | String.t(), unit | String.t(), keyword) ::
          {:ok, float} | {:error, error}
  def convert(value, from, to, opts \\ [])

  def convert(value, from, to, opts) when is_number(value) do
    with {:ok, from} <- parse_unit(from),
         {:ok, to} <- parse_unit(to),
         {:ok, result} <- do_convert(value, from, to, opts[:ingredient]) do
      {:ok, round_result(result, opts[:round])}
    end
  end

  def convert(_value, _from, _to, _opts), do: {:error, :invalid_value}

  @doc "Like `convert/4` but returns the number or raises `ArgumentError`."
  @spec convert!(number, unit | String.t(), unit | String.t(), keyword) :: float
  def convert!(value, from, to, opts \\ []) do
    case convert(value, from, to, opts) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise ArgumentError, "cannot convert #{inspect(from)} to #{inspect(to)}: #{reason}"
    end
  end

  @doc "Normalises a unit atom or free-text name to its canonical atom."
  @spec parse_unit(unit | String.t()) :: {:ok, unit} | {:error, :unknown_unit}
  def parse_unit(unit) when is_atom(unit) and not is_nil(unit) do
    if category(unit), do: {:ok, unit}, else: {:error, :unknown_unit}
  end

  def parse_unit(text) when is_binary(text) do
    key = text |> String.trim() |> String.trim_trailing(".") |> String.downcase()

    case Map.fetch(@aliases, key) do
      {:ok, unit} -> {:ok, unit}
      :error -> {:error, :unknown_unit}
    end
  end

  def parse_unit(_), do: {:error, :unknown_unit}

  @doc "The category (`:temperature`, `:weight` or `:volume`) of a canonical unit atom."
  @spec category(atom) :: category | nil
  def category(unit) when unit in @temperatures, do: :temperature
  def category(unit) when is_map_key(@weights, unit), do: :weight
  def category(unit) when is_map_key(@volumes, unit), do: :volume
  def category(_), do: nil

  @doc "Ingredients with a known density for volume/weight conversion."
  @spec ingredients() :: [atom]
  def ingredients, do: Map.keys(@cup_grams)

  @doc "Canonical units for a category."
  @spec units(category) :: [unit]
  def units(:temperature), do: @temperatures
  def units(:weight), do: Map.keys(@weights)
  def units(:volume), do: Map.keys(@volumes)

  defp do_convert(value, from, to, ingredient) do
    case {category(from), category(to)} do
      {:temperature, :temperature} ->
        with {:ok, celsius} <- to_celsius(value, from), do: from_celsius(celsius, to)

      {:weight, :weight} ->
        {:ok, value * @weights[from] / @weights[to]}

      {:volume, :volume} ->
        {:ok, value * @volumes[from] / @volumes[to]}

      {:volume, :weight} ->
        with {:ok, density} <- density(ingredient),
             do: {:ok, value * @volumes[from] * density / @weights[to]}

      {:weight, :volume} ->
        with {:ok, density} <- density(ingredient),
             do: {:ok, value * @weights[from] / density / @volumes[to]}

      _ ->
        {:error, :incompatible_units}
    end
  end

  defp density(nil), do: {:error, :incompatible_units}

  defp density(ingredient) do
    key =
      if is_atom(ingredient),
        do: Atom.to_string(ingredient),
        else: ingredient |> to_string() |> String.trim() |> String.downcase()

    key = String.replace(key, ~r/[\s-]+/, "_")

    case Map.fetch(@ingredient_aliases, key) do
      {:ok, canonical} -> {:ok, Map.fetch!(@cup_grams, canonical) / @volumes.cup}
      :error -> {:error, :unknown_ingredient}
    end
  end

  defp to_celsius(v, :c), do: {:ok, v * 1.0}
  defp to_celsius(v, :f), do: {:ok, (v - 32) * 5 / 9}

  defp to_celsius(v, :gas_mark) do
    case List.keyfind(@gas_marks, v, 0) do
      {_, celsius} -> {:ok, celsius * 1.0}
      nil -> {:error, :invalid_value}
    end
  end

  defp from_celsius(c, :c), do: {:ok, c}
  defp from_celsius(c, :f), do: {:ok, c * 9 / 5 + 32}

  defp from_celsius(c, :gas_mark) do
    {mark, celsius} = Enum.min_by(@gas_marks, fn {_, t} -> abs(t - c) end)
    if abs(celsius - c) <= @gas_tolerance, do: {:ok, mark * 1.0}, else: {:error, :out_of_range}
  end

  defp round_result(value, nil), do: value
  defp round_result(value, places), do: Float.round(value, places)
end
