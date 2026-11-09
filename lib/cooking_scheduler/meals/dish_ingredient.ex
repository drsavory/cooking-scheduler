defmodule CookingScheduler.Meals.DishIngredient do
  @moduledoc """
  An ingredient in a dish, with how much of it: a number and a unit from `units/0`.
  No unit means a count (2 onions). Owned by a meal dish or a library dish.
  """
  use Ecto.Schema

  alias CookingScheduler.UnitConversion

  @units ~w(g kg ml l tsp tbsp cup pinch)a
  # Units that add up with each other: grams with kilograms, millilitres with litres. Spoons
  # and cups are left alone, as "1 tbsp + 2 tsp" is more useful than "25 ml".
  @metric %{g: {:g, :kg}, kg: {:g, :kg}, ml: {:ml, :l}, l: {:ml, :l}}

  schema "dish_ingredients" do
    field :amount, :float
    field :unit, Ecto.Enum, values: @units
    belongs_to :ingredient, CookingScheduler.Meals.Ingredient
    belongs_to :meal_dish, CookingScheduler.Meals.MealDish
    belongs_to :dish, CookingScheduler.Meals.Dish
    timestamps(type: :utc_datetime)
  end

  def units, do: @units

  @doc """
  Reads an amount typed by a cook: "50", "1.5", "1/2" or "1 1/2" (or a number). Blank is
  `{:ok, nil}`; anything unreadable or not above zero is `:error`.
  """
  def parse_amount(nil), do: {:ok, nil}
  def parse_amount(n) when is_number(n) and n > 0, do: {:ok, n * 1.0}
  def parse_amount(n) when is_number(n), do: :error

  def parse_amount(text) when is_binary(text) do
    text = text |> String.trim() |> String.replace(",", ".")

    result =
      cond do
        text == "" -> {:ok, nil}
        m = Regex.run(~r{^(\d+)\s+(\d+)/(\d+)$}, text) -> mixed(m)
        m = Regex.run(~r{^(\d+)/(\d+)$}, text) -> fraction(m)
        text =~ ~r/^\d*\.?\d+$/ -> {:ok, ("0" <> text) |> Float.parse() |> elem(0)}
        true -> :error
      end

    case result do
      {:ok, n} when is_number(n) and n <= 0 -> :error
      other -> other
    end
  end

  def parse_amount(_), do: :error

  defp mixed([_, whole, num, den]) do
    with {:ok, f} <- fraction([nil, num, den]), do: {:ok, String.to_integer(whole) + f}
  end

  defp fraction([_, num, den]) do
    case String.to_integer(den) do
      0 -> :error
      d -> {:ok, String.to_integer(num) / d}
    end
  end

  @doc "Reads a unit from a form value; blank (or unknown) means a count."
  def parse_unit(unit) when is_atom(unit) and unit in @units, do: unit

  def parse_unit(unit) when is_binary(unit) do
    Enum.find(@units, &(Atom.to_string(&1) == unit))
  end

  def parse_unit(_), do: nil

  @doc """
  Totals a list of `{amount, unit}` pairs into one entry per unit, combining metric weights
  and volumes through `UnitConversion` (500 g + 1 kg -> 1.5 kg; 1.5 l + 200 ml -> 1.7 l).
  A metric total shows in the big unit from 1 kg / 1 l up, otherwise the small one.
  """
  def combine_amounts(pairs) do
    pairs
    |> Enum.group_by(fn {_, unit} -> Map.get(@metric, unit, unit) end)
    |> Enum.map(fn
      {{small, big}, group} ->
        total =
          group |> Enum.map(fn {a, u} -> UnitConversion.convert!(a, u, small) end) |> Enum.sum()

        in_big = UnitConversion.convert!(total, small, big)

        if in_big >= 1,
          do: {Float.round(in_big, 2), big},
          else: {Float.round(total * 1.0, 2), small}

      {unit, group} ->
        {group |> Enum.map(&elem(&1, 0)) |> Enum.sum(), unit}
    end)
    |> Enum.sort_by(fn {_, unit} -> to_string(unit) end)
  end

  @doc """
  Reads one line of an ingredient list: `"200 g butter"` -> `{:ok, "butter", "200", :g}`,
  `"2 onions, chopped"` -> `{:ok, "onions", "2", nil}`, `"salt"` -> `{:ok, "salt", nil, nil}`.
  Units the app doesn't store (oz, lb, fl oz, pints) are converted to grams or millilitres.
  """
  def parse_line(line) when is_binary(line) do
    line =
      line
      |> String.trim()
      # bullets and list numbers: "- ", "• ", "1. ", "2) "
      |> String.replace(~r/^(?:[-*•]+|\d+[.)])\s+/u, "")
      |> unicode_fractions()
      # "a pinch", "an onion", "pinch of salt"
      |> String.replace(~r/^an?\s+/i, "1 ")
      |> String.replace(~r/^pinch/i, "1 pinch")
      # "2 x 400g tins" -> "800g tins"
      |> multiply_packs()

    case Regex.run(~r/^((?:\d+\s+\d+\/\d+)|(?:\d+\/\d+)|(?:\d*[.,]?\d+))\s*(.*)$/u, line) do
      [_, amount, rest] ->
        {unit, name} = split_unit(rest)
        with {:ok, name} <- clean_name(name), do: convert_line(name, amount, unit)

      nil ->
        with {:ok, name} <- clean_name(line), do: {:ok, name, nil, nil}
    end
  end

  @fractions %{"¼" => "1/4", "½" => "1/2", "¾" => "3/4", "⅓" => "1/3", "⅔" => "2/3"}

  defp unicode_fractions(line) do
    Enum.reduce(@fractions, line, fn {glyph, text}, acc ->
      acc
      |> String.replace(~r/(\d)#{glyph}/u, "\\1 #{text}")
      |> String.replace(glyph, text)
    end)
  end

  defp multiply_packs(line) do
    case Regex.run(~r/^(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(.*)$/iu, line) do
      [_, n, each, rest] ->
        {each, _} = each |> String.replace(",", ".") |> Float.parse()
        total = String.to_integer(n) * each
        "#{format_number(total)} #{rest}"

      nil ->
        line
    end
  end

  # "g butter" -> {:g, "butter"}; "onions" -> {nil, "onions"}. Two-word units ("fl oz") too.
  defp split_unit(rest) do
    words = String.split(rest, ~r/\s+/, parts: 3)

    try_unit = fn n ->
      {unit_words, name_words} = Enum.split(words, n)
      candidate = Enum.join(unit_words, " ")

      with true <- unit_words != [],
           {:ok, unit} <- UnitConversion.parse_unit(candidate),
           true <-
             UnitConversion.category(unit) in [:weight, :volume] or
               candidate in ["pinch", "pinches"] do
        {unit, Enum.join(name_words, " ")}
      else
        _ -> nil
      end
    end

    cond do
      String.starts_with?(String.downcase(rest), "pinch") ->
        {:pinch,
         rest
         |> String.split(~r/\s+/, parts: 2)
         |> Enum.at(1, "")
         |> String.replace(~r/^of\s+/i, "")}

      u = try_unit.(2) ->
        u

      u = try_unit.(1) ->
        u

      true ->
        {nil, rest}
    end
  end

  defp clean_name(name) do
    name =
      name
      |> String.replace(~r/^of\s+/i, "")
      |> String.split(~r/[,(]/, parts: 2)
      |> hd()
      |> String.trim()
      |> String.trim_trailing(".")

    if name == "", do: :error, else: {:ok, name}
  end

  # Store in the app's own units; convert the imperial ones through UnitConversion.
  defp convert_line(name, amount, unit) when unit in @units or is_nil(unit),
    do: {:ok, name, amount, unit}

  defp convert_line(name, amount, unit) do
    with {:ok, n} <- parse_amount(amount),
         category when category in [:weight, :volume] <- UnitConversion.category(unit) do
      to = if category == :weight, do: :g, else: :ml
      {:ok, converted} = UnitConversion.convert(n, unit, to, round: 0)
      {:ok, name, converted, to}
    else
      _ -> {:ok, name, amount, nil}
    end
  end

  @doc ~s|Formats a total like `{1.5, :kg}` as "1.5 kg", or `{2.0, nil}` as "2".|
  def format_amount({amount, nil}), do: count(amount)
  def format_amount({amount, unit}), do: "#{format_number(amount)} #{unit}"

  @doc ~s|"50 g", "1.5 l", "2 items" (a count) or nil when there is no amount.|
  def format(%__MODULE__{amount: nil}), do: nil
  def format(%__MODULE__{amount: a, unit: nil}), do: count(a)
  def format(%__MODULE__{amount: a, unit: u}), do: "#{format_number(a)} #{u}"

  # No unit means whole items: "3 items", "1 item".
  defp count(1.0), do: "1 item"
  defp count(a), do: "#{format_number(a)} items"

  defp format_number(a) when a == trunc(a), do: Integer.to_string(trunc(a))
  defp format_number(a), do: a |> Float.round(2) |> Float.to_string()
end
