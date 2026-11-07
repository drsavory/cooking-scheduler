defmodule CookingSchedulerWeb.SummaryLive do
  @moduledoc """
  How a finished meal went: the result, a place for pictures of the meal, and a place for
  a picture of each dish that was cooked. Only reachable once the meal is complete (ADR 0013).
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Duration, Meals}
  alias CookingSchedulerWeb.PhotoGallery

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)

    if meal.status == :complete do
      dishes = Meals.list_meal_dishes(meal)
      summary = Meals.summarize(meal, dishes)

      {:ok,
       socket
       |> assign(:page_title, meal.name)
       |> assign(:meal, meal)
       |> assign(:delay, summary.delay)
       |> assign(:dishes, Enum.filter(dishes, & &1.cook_done_at))}
    else
      {:ok,
       socket
       |> put_flash(:info, "Photos can be added once the meal is finished.")
       |> push_navigate(to: ~p"/meals/#{meal.id}/cook")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.link
        id="summary-back"
        navigate={~p"/"}
        class="mb-3 inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> All meals
      </.link>

      <header>
        <h1 class="text-3xl font-extrabold tracking-tight sm:text-4xl">{@meal.name}</h1>
        <p class="mt-1 flex flex-wrap items-center gap-x-3 text-base-content/60">
          <span>{Calendar.strftime(@meal.date, "%A %-d %B %Y")}</span>
          <span id="summary-delay" class={@delay > 0 && "font-semibold text-warning"}>
            {if @delay > 0, do: "#{Duration.format(@delay)} late", else: "On time"}
          </span>
        </p>
      </header>

      <section id="meal-photos-section" class="mt-8">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          The meal
        </h2>
        <.live_component module={PhotoGallery} id="meal-photos" owner={@meal} />
      </section>

      <section id="dish-photos-section" class="mt-10">
        <h2 class="mb-3 text-sm font-semibold uppercase tracking-wider text-base-content/60">
          The dishes
        </h2>
        <p :if={@dishes == []} id="no-cooked-dishes" class="text-sm text-base-content/60">
          No dishes were finished, so there's nothing to photograph.
        </p>
        <div class="grid gap-8">
          <div :for={dish <- @dishes} id={"dish-#{dish.id}"}>
            <h3 class="mb-2 font-bold">{dish.name}</h3>
            <.live_component module={PhotoGallery} id={"dish-photos-#{dish.id}"} owner={dish} />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
