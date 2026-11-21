defmodule CookingSchedulerWeb.PhotoViewer do
  @moduledoc """
  A full-screen viewer for one meal's photos, one at a time (ADR 0032): previous/next, the
  keyboard (← → Esc), swiping, and a strip of thumbnails. It wraps round at either end.

  The LiveView holds `viewer: nil | %{index: i}` (plus anything it needs to find the photos)
  and forwards the viewer's events to `handle/3`:

      def handle_event("viewer_" <> _ = event, params, socket),
        do: {:noreply, update(socket, :viewer, &PhotoViewer.handle(event, params, {&1, count}))}

  `photos` are `%{photo: photo, caption: caption}` maps, as `Photos.by_meal/1` returns.
  """
  use CookingSchedulerWeb, :html

  @doc """
  The viewer state after one of its events, given `{viewer, photo_count}`; nil closes it.
  Events: `viewer_step` (`by`), `viewer_go` (`index`), `viewer_key` (`key`), `viewer_close`.
  """
  def handle(_event, _params, {nil, _count}), do: nil
  def handle(_event, _params, {_viewer, 0}), do: nil
  def handle("viewer_close", _params, _state), do: nil
  def handle("viewer_key", %{"key" => "Escape"}, _state), do: nil
  def handle("viewer_key", %{"key" => "ArrowRight"}, state), do: move(state, 1)
  def handle("viewer_key", %{"key" => "ArrowLeft"}, state), do: move(state, -1)
  def handle("viewer_key", _params, {viewer, _count}), do: viewer
  def handle("viewer_step", %{"by" => by}, state), do: move(state, to_int(by))

  def handle("viewer_go", %{"index" => index}, {viewer, count}),
    do: %{viewer | index: Integer.mod(to_int(index), count)}

  def handle(_event, _params, {viewer, _count}), do: viewer

  defp move({viewer, count}, by), do: %{viewer | index: Integer.mod(viewer.index + by, count)}

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n), do: String.to_integer(n)

  attr :index, :integer, required: true
  attr :photos, :list, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :link, :string, default: nil, doc: "a 'How it went' link, when shown away from the meal"

  def viewer(assigns) do
    count = length(assigns.photos)
    index = assigns.index

    assigns =
      assign(assigns,
        count: count,
        current: Enum.at(assigns.photos, index),
        neighbours: Enum.uniq([Integer.mod(index + 1, count), Integer.mod(index - 1, count)])
      )

    ~H"""
    <div
      id="photo-viewer"
      role="dialog"
      aria-modal="true"
      aria-label={"Photos of #{@title}"}
      phx-window-keydown="viewer_key"
      phx-hook=".PhotoSwipe"
      class="fixed inset-0 z-[100] flex flex-col bg-black/95 text-white backdrop-blur"
    >
      <div class="flex items-center gap-3 px-4 py-3 sm:px-6">
        <div class="min-w-0 flex-1">
          <p class="truncate font-bold">{@title}</p>
          <p :if={@subtitle} class="text-xs text-white/60">{@subtitle}</p>
        </div>
        <span id="photo-viewer-count" class="text-sm tabular-nums text-white/70">
          {@index + 1} / {@count}
        </span>
        <.link
          :if={@link}
          navigate={@link}
          class="btn btn-sm btn-ghost rounded-full text-white hover:bg-white/10"
        >
          How it went
        </.link>
        <button
          type="button"
          id="photo-viewer-close"
          phx-click="viewer_close"
          aria-label="Close"
          class="btn btn-sm btn-circle btn-ghost text-white hover:bg-white/10"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>

      <div class="relative flex min-h-0 flex-1 items-center justify-center px-2 sm:px-16">
        <figure class="flex max-h-full max-w-full flex-col items-center gap-3">
          <img
            id={"photo-viewer-photo-#{@current.photo.id}"}
            src={~p"/photos/#{@current.photo.id}"}
            alt={@current.caption || @title}
            class="photo-in max-h-[calc(100vh-13rem)] max-w-full rounded-2xl object-contain shadow-2xl"
          />
          <figcaption id="photo-viewer-caption" class="text-sm text-white/80">
            {@current.caption || "The table"}
          </figcaption>
        </figure>
        <button
          :if={@count > 1}
          type="button"
          id="photo-viewer-prev"
          phx-click={JS.push("viewer_step", value: %{by: -1})}
          aria-label="Previous photo"
          class="btn btn-circle absolute left-2 top-1/2 -translate-y-1/2 border-0 bg-white/10 text-white backdrop-blur hover:bg-white/20 sm:left-4"
        >
          <.icon name="hero-chevron-left" class="size-6" />
        </button>
        <button
          :if={@count > 1}
          type="button"
          id="photo-viewer-next"
          phx-click={JS.push("viewer_step", value: %{by: 1})}
          aria-label="Next photo"
          class="btn btn-circle absolute right-2 top-1/2 -translate-y-1/2 border-0 bg-white/10 text-white backdrop-blur hover:bg-white/20 sm:right-4"
        >
          <.icon name="hero-chevron-right" class="size-6" />
        </button>
      </div>

      <div
        :if={@count > 1}
        id="photo-viewer-strip"
        class="flex justify-center gap-1.5 overflow-x-auto px-4 pb-4 pt-3"
      >
        <button
          :for={{%{photo: photo, caption: caption}, i} <- Enum.with_index(@photos)}
          type="button"
          id={"photo-viewer-thumb-#{i}"}
          phx-click={JS.push("viewer_go", value: %{index: i})}
          aria-label={"Photo #{i + 1}: #{caption || "the table"}"}
          aria-current={to_string(i == @index)}
          class={[
            "size-14 shrink-0 overflow-hidden rounded-lg transition",
            i == @index && "ring-2 ring-white",
            i != @index && "opacity-50 hover:opacity-90"
          ]}
        >
          <img src={~p"/photos/#{photo.id}"} alt="" loading="lazy" class="size-full object-cover" />
        </button>
      </div>

      <%!-- Warm the browser cache so stepping feels instant. --%>
      <img
        :for={i <- @neighbours}
        src={~p"/photos/#{Enum.at(@photos, i).photo.id}"}
        alt=""
        aria-hidden="true"
        class="hidden"
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoSwipe">
        export default {
          mounted() {
            this.el.addEventListener("touchstart", e => {
              this.startX = e.changedTouches[0].clientX
            }, {passive: true})
            this.el.addEventListener("touchend", e => {
              const dx = e.changedTouches[0].clientX - this.startX
              if (Math.abs(dx) > 40) this.pushEvent("viewer_step", {by: dx < 0 ? 1 : -1})
            })
          }
        }
      </script>
    </div>
    """
  end

  attr :photos, :list, required: true
  attr :id, :string, required: true
  attr :open, :any, required: true, doc: "fn index -> JS command that opens the viewer there"
  attr :alt, :string, required: true
  attr :big, :integer, default: 3, doc: "how many photos the mosaic shows at most (3 or 5)"
  attr :class, :string, default: nil

  @doc """
  A meal's photos as a mosaic: the first large, up to two (or four) beside it, "+N" on the
  last when there are more. Each opens the viewer at that photo.
  """
  def mosaic(assigns) do
    count = length(assigns.photos)
    shown = min(count, if(count >= assigns.big, do: assigns.big, else: 1))
    assigns = assign(assigns, count: count, shown: shown)

    ~H"""
    <div
      id={@id}
      class={[
        "grid gap-1 overflow-hidden",
        @shown == 3 && "grid-cols-3 grid-rows-2",
        @shown == 5 && "grid-cols-4 grid-rows-2",
        @class
      ]}
    >
      <button
        :for={{%{photo: photo, caption: caption}, i} <- Enum.with_index(Enum.take(@photos, @shown))}
        type="button"
        id={"#{@id}-#{i}"}
        phx-click={@open.(i)}
        aria-label={"View #{caption || @alt} photo #{i + 1} of #{@count}"}
        class={[
          "group/photo relative overflow-hidden bg-base-content/5",
          @shown > 1 && i == 0 && "col-span-2 row-span-2"
        ]}
      >
        <img
          src={~p"/photos/#{photo.id}"}
          alt={caption || @alt}
          loading="lazy"
          class="size-full object-cover transition duration-500 group-hover/photo:scale-105"
        />
        <span
          :if={i == @shown - 1 and @count > @shown}
          class="absolute inset-0 grid place-items-center bg-black/45 text-lg font-bold text-white backdrop-blur-[1px]"
        >
          +{@count - @shown}
        </span>
      </button>
    </div>
    """
  end
end
