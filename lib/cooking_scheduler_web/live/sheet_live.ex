defmodule CookingSchedulerWeb.SheetLive do
  @moduledoc """
  The run sheet: every step of the day in clock order, to print and stick on the fridge
  (ADR 0019). Planned times only; the cook screen is the live version.
  """
  use CookingSchedulerWeb, :live_view

  alias CookingScheduler.{Cooking, Duration, Kitchen, Meals, Planner}
  alias CookingScheduler.Kitchen.Appliance
  alias CookingScheduler.Meals.{Meal, MealDish}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    meal = Meals.get_meal!(id)
    kitchen = Kitchen.list_appliances()
    serve = Meal.serve_minutes(meal)
    entries = Planner.plan(Meals.list_meal_dishes(meal), serve, kitchen)
    events = Planner.oven_events(entries, kitchen)

    # Classified against a clock before anything starts, so every step is "upcoming".
    first = entries |> Enum.map(& &1.prep_at) |> Enum.min(fn -> serve end)
    lives = Cooking.lives(entries, first - 1)

    steps =
      Cooking.tasks(lives, first - 1, events, [])
      |> Enum.reject(&(&1.state == :done))
      |> Enum.map(&step/1)

    courses =
      entries
      |> Enum.map(& &1.serve_at)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn at ->
        %{
          at: at,
          label:
            if(at == serve,
              do: "Serve",
              else: "Serve " <> String.downcase(MealDish.course(at - serve))
            ),
          kind: :serve
        }
      end)

    rows =
      (steps ++ courses)
      |> Enum.sort_by(& &1.at)
      |> Enum.chunk_by(&day_part(&1.at))
      |> Enum.map(fn [first | _] = rows -> %{label: day_part(first.at), rows: rows} end)

    {:ok,
     socket
     |> assign(:page_title, "Run sheet · #{meal.name}")
     |> assign(:meal, meal)
     |> assign(:sections, rows)
     |> assign(:empty, steps == [])}
  end

  defp step(%{kind: kind, event: ev} = t) when kind in [:preheat, :adjust] do
    %{
      at: t.at,
      kind: kind,
      label:
        if(kind == :preheat,
          do: "Switch on #{ev.appliance.name}",
          else: "Turn #{ev.appliance.name}"
        ) <>
          " to #{temp_text(ev.temp)}",
      detail: "for #{t.entry.dish.name}"
    }
  end

  defp step(%{kind: :prep, entry: e} = t),
    do: %{
      at: t.at,
      kind: :prep,
      label: "Prep #{e.dish.name}",
      detail: "#{Duration.format(e.dish.prep_minutes)}"
    }

  defp step(%{kind: :start, entry: e} = t) do
    where = e.resource && e.resource.name
    temp = temp_label(e.dish)

    %{
      at: t.at,
      kind: :start,
      label:
        "#{start_verb(e.dish.method)} #{e.dish.name}" <> if(where, do: " · #{where}", else: ""),
      detail:
        Enum.join(
          Enum.reject(
            [temp, "#{Duration.format(e.dish.cook_minutes)}", e.dish.notes],
            &(&1 in [nil, ""])
          ),
          " · "
        )
    }
  end

  defp step(%{kind: :out, entry: e} = t) do
    rest = if e.dish.rest_minutes > 0, do: "rest #{Duration.format(e.dish.rest_minutes)}"
    %{at: t.at, kind: :out, label: "#{out_verb(e.dish.method)} #{e.dish.name}", detail: rest}
  end

  defp start_verb(:oven), do: "In:"
  defp start_verb(:ring), do: "On:"
  defp start_verb(_), do: "Start:"

  defp out_verb(:oven), do: "Out:"
  defp out_verb(:ring), do: "Off:"
  defp out_verb(_), do: "Done:"

  defp temp_label(%{temp: nil}), do: nil
  defp temp_label(%{temp: t, temp_unit: u}), do: temp_text({t, u})

  defp temp_text({t, :gas_mark}), do: "gas #{Appliance.fmt_temp(t, :gas_mark)}"

  defp temp_text({t, unit}),
    do: "#{Appliance.fmt_temp(t, unit)} #{Appliance.temp_unit_label(unit)}"

  defp day_part(at) when at < 0, do: "The day before"
  defp day_part(at) when at < 12 * 60, do: "Morning"
  defp day_part(at) when at < 17 * 60, do: "Afternoon"
  defp day_part(_), do: "Evening"

  defp kind_icon(:preheat), do: "hero-power-micro"
  defp kind_icon(:adjust), do: "hero-adjustments-vertical-micro"
  defp kind_icon(:prep), do: "hero-scissors-micro"
  defp kind_icon(:start), do: "hero-arrow-right-end-on-rectangle-micro"
  defp kind_icon(:out), do: "hero-arrow-left-start-on-rectangle-micro"
  defp kind_icon(:serve), do: "hero-bell-alert-micro"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="no-print mb-3 flex items-center justify-between gap-3">
        <.link
          navigate={~p"/meals/#{@meal.id}/cook"}
          class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
        >
          <.icon name="hero-arrow-left-micro" class="size-4" /> Cook
        </.link>
        <button
          id="print-sheet"
          type="button"
          phx-hook=".Print"
          class="btn btn-sm btn-glass rounded-full"
        >
          <.icon name="hero-printer" class="size-4" /> Print
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Print">
          export default {
            mounted() { this.el.addEventListener("click", () => window.print()) }
          }
        </script>
      </div>

      <h1 class="text-3xl font-extrabold tracking-tight">{@meal.name}</h1>
      <p class="mt-1 text-sm text-base-content/60">
        {Calendar.strftime(@meal.date, "%A %-d %B %Y")} · dinner at {Calendar.strftime(
          @meal.serve_at,
          "%H:%M"
        )}
      </p>

      <p :if={@empty} id="sheet-empty" class="mt-6 text-base-content/60">Nothing planned yet.</p>

      <section :for={section <- @sections} class="mt-6 break-inside-avoid">
        <h2 class="mb-2 text-xs font-semibold uppercase tracking-wider text-base-content/50">
          {section.label}
        </h2>
        <table
          id={"sheet-#{String.downcase(String.replace(section.label, " ", "-"))}"}
          class="w-full text-sm"
        >
          <tbody>
            <tr
              :for={row <- section.rows}
              class={[
                "border-t border-base-300 align-top",
                row.kind == :serve && "bg-secondary/10 font-semibold"
              ]}
            >
              <td class="w-20 py-1.5 pr-3 font-bold tabular-nums">
                {Duration.clock(Integer.mod(row.at, 1440))}
              </td>
              <td class="w-6 py-1.5 pr-2 text-base-content/50">
                <.icon name={kind_icon(row.kind)} class="size-4" />
              </td>
              <td class="py-1.5">
                <span class="font-medium">{row.label}</span>
                <span :if={row[:detail]} class="ml-2 text-base-content/60">{row.detail}</span>
              </td>
              <td class="w-8 py-1.5 text-right print:table-cell">
                <span class="inline-block size-4 rounded border border-base-content/30"></span>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end
