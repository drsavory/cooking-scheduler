defmodule CookingScheduler.Meals.Meal do
  @moduledoc "One occasion being cooked for (e.g. Christmas 2025): a date, a serving time and its dishes."
  use Ecto.Schema
  import Ecto.Changeset

  schema "meals" do
    field :name, :string
    field :date, :date
    field :serve_at, :time

    has_many :dishes, CookingScheduler.Meals.Dish

    timestamps(type: :utc_datetime)
  end

  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:name, :date, :serve_at])
    |> validate_required([:name, :date, :serve_at])
    |> validate_length(:name, max: 80)
  end

  @doc "Serving time as minutes after midnight."
  def serve_minutes(%__MODULE__{serve_at: %Time{hour: h, minute: m}}), do: h * 60 + m
end
