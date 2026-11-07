defmodule CookingScheduler.Meals.DishIngredient do
  @moduledoc """
  An ingredient in a dish, with how much of it: a number and a unit from `units/0`.
  No unit means a count (2 onions). Owned by a meal dish or a saved dish.
  """
  use Ecto.Schema

  @units ~w(g kg ml l tsp tbsp cup pinch)a

  schema "dish_ingredients" do
    field :amount, :float
    field :unit, Ecto.Enum, values: @units
    belongs_to :ingredient, CookingScheduler.Meals.Ingredient
    belongs_to :dish, CookingScheduler.Meals.Dish
    belongs_to :saved_dish, CookingScheduler.Meals.SavedDish
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
