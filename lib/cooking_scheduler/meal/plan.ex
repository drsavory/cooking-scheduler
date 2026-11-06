defmodule CookingScheduler.Meal.Plan do
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :serve_at, :time
    timestamps(type: :utc_datetime)
  end

  def changeset(plan, attrs) do
    plan |> cast(attrs, [:serve_at]) |> validate_required([:serve_at])
  end

  @doc "Serving time as minutes after midnight."
  def serve_minutes(%__MODULE__{serve_at: %Time{hour: h, minute: m}}), do: h * 60 + m
end
