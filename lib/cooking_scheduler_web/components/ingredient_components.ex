defmodule CookingSchedulerWeb.IngredientComponents do
  @moduledoc "Bits of UI for ingredients shared by the shopping list and the dish page."
  use Phoenix.Component

  import CookingSchedulerWeb.CoreComponents, only: [icon: 1]

  alias CookingScheduler.Meals.Ingredient
  alias Phoenix.LiveView.JS

  attr :ingredient, Ingredient, required: true
  attr :id, :string, required: true

  @doc """
  A tiny button that reveals the aisle and staple settings for an ingredient (ADR 0021). The
  form sends `file_ingredient` with `%{"ingredient_id" => id, "ingredient" => %{"category", "staple"}}`.
  """
  def ingredient_filing(assigns) do
    ~H"""
    <button
      type="button"
      id={"#{@id}-toggle"}
      class="btn btn-xs btn-circle btn-ghost text-base-content/50 hover:text-primary"
      phx-click={JS.toggle(to: "##{@id}", display: "flex")}
      aria-label={"Where to find #{@ingredient.name}"}
      title="Aisle & cupboard"
    >
      <.icon name="hero-tag-micro" class="size-3.5" />
    </button>
    """
  end

  attr :ingredient, Ingredient, required: true
  attr :id, :string, required: true
  attr :open, :boolean, default: false

  @doc "The form the toggle above reveals."
  def ingredient_filing_form(assigns) do
    ~H"""
    <form
      id={@id}
      phx-change="file_ingredient"
      style={if(@open, do: nil, else: "display: none")}
      class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs"
    >
      <input type="hidden" name="ingredient_id" value={@ingredient.id} />
      <label class="flex items-center gap-1.5">
        <span class="text-base-content/60">Aisle</span>
        <select name="ingredient[category]" class="select select-xs" aria-label="Aisle">
          <option value="" selected={is_nil(@ingredient.category)}>Not filed</option>
          <option
            :for={{label, value} <- Ingredient.category_options()}
            value={value}
            selected={@ingredient.category == value}
          >
            {label}
          </option>
        </select>
      </label>
      <label class="flex cursor-pointer items-center gap-1.5">
        <input type="hidden" name="ingredient[staple]" value="false" />
        <input
          type="checkbox"
          name="ingredient[staple]"
          value="true"
          checked={@ingredient.staple}
          class="checkbox checkbox-xs"
        />
        <span>Always in the cupboard</span>
      </label>
    </form>
    """
  end
end
