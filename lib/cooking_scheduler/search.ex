defmodule CookingScheduler.Search do
  @moduledoc "Quick search across meals and dishes, used by the spotlight dialog."

  alias CookingScheduler.Meals

  @limit 8

  @doc """
  Returns `%{meals: [...], dishes: [...]}` of display maps (`id`, `label`, `sub`, `icon`,
  `kind`) matching every whitespace-separated term in `query`. Dishes also match on tags.
  """
  def search(query) do
    terms = query |> to_string() |> String.downcase() |> String.split(~r/\s+/, trim: true)

    meals =
      Meals.list_meals()
      |> Enum.filter(&matches?([&1.name], terms))
      |> Enum.take(@limit)
      |> Enum.map(fn m ->
        %{
          kind: "meal",
          id: m.id,
          label: m.name,
          sub: Calendar.strftime(m.date, "%d %b %Y"),
          icon: "hero-calendar-days"
        }
      end)

    dishes =
      Meals.list_dishes()
      |> Enum.filter(&matches?([&1.name | &1.tags], terms))
      |> Enum.take(@limit)
      |> Enum.map(fn d ->
        %{
          kind: "dish",
          id: d.id,
          label: d.name,
          sub: Enum.join(d.tags, ", "),
          icon: method_icon(d.method)
        }
      end)

    %{meals: meals, dishes: dishes}
  end

  defp matches?(fields, terms) do
    haystack = fields |> Enum.join(" ") |> String.downcase()
    Enum.all?(terms, &String.contains?(haystack, &1))
  end

  defp method_icon(:oven), do: "hero-fire"
  defp method_icon(:ring), do: "hero-stop-circle"
  defp method_icon(:appliance), do: "hero-bolt"
end
