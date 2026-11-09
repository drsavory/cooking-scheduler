defmodule CookingScheduler.RecipeImport do
  @moduledoc """
  Reads a recipe from a web page (ADR 0023). Most recipe sites publish a schema.org `Recipe`
  as JSON-LD in a `<script type="application/ld+json">` tag; that is all we look at. Returns
  the name, prep and cook times in minutes, and the ingredient lines as written, for the
  caller to turn into dish details and ingredients.

  Fetching goes through `Req`. Tests set `:recipe_import_req` in the app config to a keyword
  list of extra `Req` options (such as `plug:`) so no real request is made.
  """

  @type recipe :: %{
          name: String.t() | nil,
          prep_minutes: non_neg_integer | nil,
          cook_minutes: non_neg_integer | nil,
          ingredients: [String.t()],
          link: String.t()
        }

  @doc "Fetches and reads a recipe page. `{:error, :no_recipe}` if the page has no recipe data."
  @spec fetch(String.t()) :: {:ok, recipe} | {:error, :bad_link | :no_recipe | :unreachable}
  def fetch(link) when is_binary(link) do
    with {:ok, url} <- url(link),
         {:ok, html} <- get(url),
         {:ok, recipe} <- parse(html) do
      {:ok, Map.put(recipe, :link, url)}
    end
  end

  defp url(link) do
    link = String.trim(link)
    link = if link =~ ~r{^https?://}i, do: link, else: "https://" <> link

    case URI.parse(link) do
      %URI{host: host} when is_binary(host) ->
        if host =~ ~r/^[^\s.]+(\.[^\s.]+)+$/, do: {:ok, link}, else: {:error, :bad_link}

      _ ->
        {:error, :bad_link}
    end
  end

  defp get(url) do
    opts =
      [
        url: url,
        headers: [
          {"user-agent", "CookingScheduler/1.0 (+recipe import)"},
          {"accept", "text/html"}
        ],
        max_redirects: 3,
        receive_timeout: 10_000,
        retry: false
      ] ++ Application.get_env(:cooking_scheduler, :recipe_import_req, [])

    case Req.get(opts) do
      {:ok, %Req.Response{status: status, body: body}}
      when status in 200..299 and is_binary(body) ->
        {:ok, body}

      _ ->
        {:error, :unreachable}
    end
  end

  @doc "Reads the first schema.org Recipe out of a page's JSON-LD blocks."
  @spec parse(String.t()) :: {:ok, map} | {:error, :no_recipe}
  def parse(html) when is_binary(html) do
    ~r/<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>(.*?)<\/script>/is
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.flat_map(fn [json] ->
      case Jason.decode(json) do
        {:ok, data} -> nodes(data)
        _ -> []
      end
    end)
    |> Enum.find(&recipe?/1)
    |> case do
      nil -> {:error, :no_recipe}
      node -> {:ok, recipe(node)}
    end
  end

  # JSON-LD may be one object, a list, or an object with a @graph list.
  defp nodes(%{"@graph" => graph}) when is_list(graph), do: Enum.flat_map(graph, &nodes/1)
  defp nodes(list) when is_list(list), do: Enum.flat_map(list, &nodes/1)
  defp nodes(%{} = node), do: [node]
  defp nodes(_), do: []

  defp recipe?(%{"@type" => type}) when is_binary(type), do: String.downcase(type) == "recipe"

  defp recipe?(%{"@type" => types}) when is_list(types),
    do: Enum.any?(types, &recipe?(%{"@type" => &1}))

  defp recipe?(_), do: false

  defp recipe(node) do
    %{
      name: text(node["name"]),
      prep_minutes: duration(node["prepTime"]),
      cook_minutes: duration(node["cookTime"]) || remaining(node),
      ingredients:
        node["recipeIngredient"] |> List.wrap() |> Enum.map(&text/1) |> Enum.reject(&is_nil/1)
    }
  end

  # Some sites only give a total time; treat the part that isn't prep as cooking.
  defp remaining(node) do
    with total when is_integer(total) <- duration(node["totalTime"]),
         prep <- duration(node["prepTime"]) || 0,
         left when left > 0 <- total - prep do
      left
    else
      _ -> nil
    end
  end

  defp text(nil), do: nil
  defp text(s) when is_binary(s), do: s |> decode_entities() |> String.trim() |> blank_to_nil()
  defp text(%{"@value" => v}), do: text(v)
  defp text([first | _]), do: text(first)
  defp text(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp decode_entities(s) do
    s
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&nbsp;", " ")
  end

  @doc ~s|ISO 8601 duration to minutes: "PT1H30M" -> 90, "P0DT0H45M" -> 45. nil if unreadable.|
  def duration(nil), do: nil

  def duration(text) when is_binary(text) do
    case Regex.run(~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/i, String.trim(text)) do
      [_ | parts] ->
        [d, h, m, _s] = parts |> Enum.map(&int/1) |> pad(4)
        minutes = d * 24 * 60 + h * 60 + m
        if minutes > 0, do: minutes, else: nil

      nil ->
        nil
    end
  end

  def duration(_), do: nil

  defp int(""), do: 0
  defp int(nil), do: 0
  defp int(s), do: String.to_integer(s)

  defp pad(list, n), do: list ++ List.duplicate(0, n - length(list))
end
