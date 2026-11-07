defmodule CookingScheduler.RecipeLink do
  @moduledoc "Which website a recipe link points at, for showing next to the link."

  @doc """
  The site a link is from, without `www.` ("https://www.bbcgoodfood.com/x" -> "bbcgoodfood.com").
  Links typed without a scheme still work. Returns nil if there's no usable host.
  """
  def host(link) when is_binary(link) do
    link = String.trim(link)
    uri = URI.parse(if link =~ ~r{^[a-z][a-z0-9+.-]*://}i, do: link, else: "https://" <> link)

    case uri.host do
      host when is_binary(host) ->
        if host =~ ~r/^[^\s.]+(\.[^\s.]+)+$/,
          do: String.replace_prefix(host, "www.", ""),
          else: nil

      _ ->
        nil
    end
  end

  def host(_), do: nil
end
