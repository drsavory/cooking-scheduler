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

  @doc """
  Whether a link is safe to put in an `href`: a web address, or plain text such as "see mum's
  recipe book". Anything with another scheme (`javascript:`, `data:`, ...) is not.
  """
  def web?(link) when is_binary(link) do
    # Browsers ignore whitespace and control characters inside a URL, so strip them before
    # looking for a scheme ("java\tscript:" is still JavaScript).
    case Regex.run(~r/^([a-z][a-z0-9+.-]*):/i, String.replace(link, ~r/[\s\x00-\x1F]/, "")) do
      [_, scheme] -> String.downcase(scheme) in ["http", "https"]
      nil -> true
    end
  end

  def web?(_), do: false

  @doc "Changeset validation: `field` must satisfy `web?/1`."
  def validate(changeset, field) do
    Ecto.Changeset.validate_change(changeset, field, fn ^field, link ->
      if web?(link), do: [], else: [{field, "should be a web address (http:// or https://)"}]
    end)
  end
end
