defmodule CookingScheduler.Meals.Meal do
  @moduledoc "One occasion being cooked for (e.g. Christmas 2025): a date, a serving time and its dishes."
  use Ecto.Schema
  import Ecto.Changeset

  schema "meals" do
    field :name, :string
    field :date, :date
    field :serve_at, :time
    # planning -> prepping is chosen by the cook; cooking/complete follow cooking progress.
    field :status, Ecto.Enum,
      values: [:planning, :prepping, :cooking, :complete],
      default: :planning

    # Set (not cast) when the cook ends the meal early.
    field :finished_at, :utc_datetime
    # Oven tasks done on the day ("preheat:<oven id>:<dish id>"); cleared with the progress.
    field :oven_marks, {:array, :string}, default: []
    # Written after the meal: what to change next time.
    field :next_time, :string

    has_many :meal_dishes, CookingScheduler.Meals.MealDish

    timestamps(type: :utc_datetime)
  end

  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:name, :date, :serve_at, :next_time])
    |> validate_required([:name, :date, :serve_at])
    |> validate_length(:name, max: 80)
    |> validate_length(:next_time, max: 2000)
  end

  @doc "Serving time as minutes after midnight."
  def serve_minutes(%__MODULE__{serve_at: %Time{hour: h, minute: m}}), do: h * 60 + m
end
