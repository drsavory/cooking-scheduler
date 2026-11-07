defmodule CookingSchedulerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CookingSchedulerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="aurora" aria-hidden="true">
      <div class="aurora-blob aurora-a"></div>
      <div class="aurora-blob aurora-b"></div>
      <div class="aurora-blob aurora-c"></div>
    </div>
    <div class="relative min-h-screen">
      <header class="sticky top-3 z-30 mx-auto max-w-[96rem] px-3 sm:px-6">
        <div class="glass flex items-center justify-between rounded-full py-2 pl-2.5 pr-3">
          <a href="/" class="flex items-center gap-2.5">
            <span class="grid size-9 place-items-center rounded-full bg-gradient-to-br from-primary to-accent text-primary-content shadow-md shadow-primary/30">
              <.icon name="hero-fire-solid" class="size-5" />
            </span>
            <span class="text-base font-semibold tracking-tight">Cooking Scheduler</span>
          </a>
          <div class="flex items-center gap-2 sm:gap-4">
            <nav class="hidden items-center gap-1 text-sm font-medium sm:flex">
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm rounded-full">Home</.link>
            </nav>
            <button
              id="open-search"
              type="button"
              phx-click={JS.dispatch("search:open", to: "#spotlight")}
              aria-label="Search meals and dishes"
              class="btn btn-ghost btn-sm rounded-full"
            >
              <.icon name="hero-magnifying-glass" class="size-4" />
              <kbd class="kbd kbd-xs hidden sm:inline-flex">/</kbd>
            </button>
            <.theme_toggle />
          </div>
        </div>
      </header>

      <main class="relative mx-auto max-w-[96rem] px-4 pb-24 pt-10 sm:px-6">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.spotlight />
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Spotlight-style quick search, opened with "/" or the header button. The hook asks the
  current LiveView (via `CookingSchedulerWeb.SearchHook`) for matches as you type.
  """
  def spotlight(assigns) do
    ~H"""
    <%!-- The hook owns this subtree, so LiveView must not patch it. --%>
    <div
      id="spotlight"
      phx-hook=".Spotlight"
      phx-update="ignore"
      role="dialog"
      aria-modal="true"
      aria-label="Search meals and dishes"
      data-meal-base="/meals"
      data-dish-base="/dishes"
      class="fixed inset-0 z-[90] hidden items-start justify-center p-4 pt-[12vh]"
    >
      <div id="spotlight-backdrop" class="absolute inset-0 bg-base-content/30 backdrop-blur-sm"></div>
      <div class="glass pop-in relative w-full max-w-xl overflow-hidden rounded-[1.75rem] shadow-2xl">
        <div class="flex items-center gap-3 border-b border-base-content/10 px-5">
          <.icon name="hero-magnifying-glass" class="size-5 text-base-content/50" />
          <input
            id="spotlight-input"
            type="text"
            autocomplete="off"
            spellcheck="false"
            placeholder="Search meals and dishes…"
            class="h-14 w-full border-0 bg-transparent text-lg outline-none focus:outline-none focus:ring-0"
          />
          <kbd class="kbd kbd-sm">esc</kbd>
        </div>
        <div id="spotlight-results" class="max-h-[50vh] overflow-y-auto p-2"></div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Spotlight">
        export default {
          mounted() {
            this.isOpen = false
            this.seq = 0
            this.input = this.el.querySelector("#spotlight-input")
            this.results = this.el.querySelector("#spotlight-results")

            this.onKeydown = e => {
              if(!this.isOpen){
                const t = e.target
                const typing = t && (t.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName))
                if(e.key === "/" && !typing && !e.metaKey && !e.ctrlKey && !e.altKey){
                  e.preventDefault()
                  this.open()
                }
                return
              }
              if(e.key === "Escape"){ e.preventDefault(); this.close() }
              else if(e.key === "ArrowDown"){ e.preventDefault(); this.move(1) }
              else if(e.key === "ArrowUp"){ e.preventDefault(); this.move(-1) }
              else if(e.key === "Enter"){
                const active = this.results.querySelector("[data-active]")
                if(active){ e.preventDefault(); this.close(); active.click() }
              }
            }
            window.addEventListener("keydown", this.onKeydown)

            this.el.addEventListener("search:open", () => this.open())
            this.el.querySelector("#spotlight-backdrop").addEventListener("click", () => this.close())
            this.results.addEventListener("click", e => {
              if(e.target.closest("a")) this.close()
            })
            this.input.addEventListener("input", () => this.search())
          },

          destroyed(){ window.removeEventListener("keydown", this.onKeydown) },

          open(){
            this.isOpen = true
            this.el.classList.replace("hidden", "flex")
            this.input.value = ""
            this.input.focus()
            this.search()
          },

          close(){
            this.isOpen = false
            this.el.classList.replace("flex", "hidden")
          },

          search(){
            const seq = ++this.seq
            this.pushEvent("spotlight_search", {q: this.input.value}, reply => {
              if(seq === this.seq && this.isOpen) this.show(reply)
            })
          },

          show({meals = [], dishes = []}){
            this.results.replaceChildren()
            const base = {meal: this.el.dataset.mealBase, dish: this.el.dataset.dishBase}
            const href = i => i.kind === "meal" ? `${base.meal}/${i.id}/plan` : `${base.dish}/${i.id}`
            const group = (title, items) => {
              if(items.length === 0) return
              const h = document.createElement("h3")
              h.className = "px-3 pb-1 pt-2 text-xs font-semibold uppercase tracking-wider text-base-content/50"
              h.textContent = title
              this.results.append(h)
              items.forEach(i => this.results.append(this.row(i, href(i))))
            }
            group("Meals", meals)
            group("Dishes", dishes)
            if(meals.length + dishes.length === 0){
              const p = document.createElement("p")
              p.className = "px-3 py-8 text-center text-base-content/60"
              p.textContent = "Nothing matches."
              this.results.append(p)
            }
            const first = this.results.querySelector("a")
            if(first) first.setAttribute("data-active", "")
          },

          row(item, href){
            // Lets LiveView's own click handler do a live navigation.
            const a = document.createElement("a")
            a.href = href
            a.id = `spotlight-${item.kind}-${item.id}`
            a.setAttribute("data-phx-link", "redirect")
            a.setAttribute("data-phx-link-state", "push")
            a.className = "flex items-center gap-3 rounded-xl px-3 py-2 data-[active]:bg-primary/15"
            const icon = document.createElement("span")
            icon.className = `${item.icon} size-5 shrink-0 text-base-content/60`
            const label = document.createElement("span")
            label.className = "min-w-0 flex-1 truncate font-medium"
            label.textContent = item.label
            const sub = document.createElement("span")
            sub.className = "truncate text-xs capitalize text-base-content/50"
            sub.textContent = item.sub
            a.append(icon, label, sub)
            return a
          },

          move(step){
            const items = Array.from(this.results.querySelectorAll("a"))
            if(items.length === 0) return
            const current = items.findIndex(i => i.hasAttribute("data-active"))
            const next = items[(current + step + items.length) % items.length]
            items.forEach(i => i.removeAttribute("data-active"))
            next.setAttribute("data-active", "")
            next.scrollIntoView({block: "nearest"})
          }
        }
      </script>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=dark]_&]:left-1/2 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
