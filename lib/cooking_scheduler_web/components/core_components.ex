defmodule CookingSchedulerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: CookingSchedulerWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Tag chips for a dish. Editable: one-tap checkboxes for the suggested tags (plus any tag the
  dish already has) and a box for new ones. Locked: just the chosen tags.
  """
  attr :field, Phoenix.HTML.FormField, required: true, doc: "the `:tags` field"
  attr :custom, Phoenix.HTML.FormField, required: true, doc: "the `:custom_tags` field"
  attr :suggested, :list, default: []
  attr :locked, :boolean, default: false

  def tag_picker(assigns) do
    chosen = assigns.field.value || []
    assigns = assign(assigns, chosen: chosen, options: Enum.uniq(assigns.suggested ++ chosen))

    ~H"""
    <div id={@field.id <> "-picker"}>
      <div class="flex flex-wrap gap-2">
        <input :if={not @locked} type="hidden" name={@field.name <> "[]"} value="" />
        <%= for tag <- @options do %>
          <label
            :if={not @locked or tag in @chosen}
            id={"tag-option-#{tag}"}
            class={[
              "rounded-full border px-3 py-1 text-sm capitalize transition has-[:checked]:border-primary has-[:checked]:bg-primary/15 has-[:checked]:font-semibold has-[:checked]:text-primary",
              (@locked && "pointer-events-none border-transparent bg-base-content/10") ||
                "cursor-pointer border-base-300 hover:border-primary/50 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-primary/40"
            ]}
          >
            <input
              type="checkbox"
              name={@field.name <> "[]"}
              value={tag}
              checked={tag in @chosen}
              disabled={@locked}
              class="sr-only"
            />
            {tag}
          </label>
        <% end %>
        <span :if={@locked and @chosen == []} id="no-tags" class="text-sm text-base-content/60">
          No tags yet.
        </span>
      </div>
      <input
        :if={not @locked}
        type="text"
        id={@custom.id}
        name={@custom.name}
        value={@custom.value}
        placeholder="Add your own, comma separated"
        autocomplete="off"
        aria-label="Add tags"
        class="input input-bordered mt-3 w-full"
      />
      <p :for={{msg, opts} <- @field.errors} class="mt-1 text-sm text-error">
        {translate_error({msg, opts})}
      </p>
    </div>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete autofocus capture cols disabled form list max maxlength min
                minlength multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  A button that asks for confirmation in an in-app glass dialog before doing anything.

  **Always use this instead of `data-confirm`**; never use browser/system confirmation
  dialogs. The trigger is the button; `on_confirm` runs only if the user confirms.

  ## Examples

      <.confirm_button
        id={"delete-meal-\#{meal.id}"}
        title="Delete Christmas?"
        message="This can't be undone."
        confirm_label="Delete"
        on_confirm={JS.push("delete_meal", value: %{id: meal.id})}
        class="btn btn-ghost"
      >
        <.icon name="hero-trash" /> Delete
      </.confirm_button>
  """
  attr :id, :string, required: true, doc: "unique id; the dialog is `\#{id}-dialog`"
  attr :title, :string, required: true
  attr :message, :string, default: nil
  attr :confirm_label, :string, default: "Confirm"
  attr :cancel_label, :string, default: "Cancel"
  attr :tone, :atom, values: [:danger, :primary], default: :primary
  attr :on_confirm, JS, required: true
  attr :class, :any, default: nil
  attr :rest, :global, doc: "extra attributes for the trigger button, e.g. aria-label"
  slot :inner_block, required: true, doc: "the trigger button's content"

  def confirm_button(assigns) do
    assigns = assign(assigns, :dialog, "#{assigns.id}-dialog")

    ~H"""
    <button
      type="button"
      id={@id}
      class={@class}
      phx-click={
        JS.show(
          to: "#" <> @dialog,
          display: "flex",
          transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
        )
        |> JS.focus_first(to: "#" <> @dialog <> "-panel")
      }
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>

    <%!-- Teleported to <body>: glass cards create their own containing block, which would
         otherwise trap this fixed overlay inside the card. --%>
    <.portal id={@id <> "-portal"} target="body">
      <div
        id={@dialog}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby={@dialog <> "-title"}
        class="fixed inset-0 z-[100] hidden items-center justify-center p-4"
        phx-window-keydown={JS.hide(to: "#" <> @dialog)}
        phx-key="escape"
      >
        <div
          class="absolute inset-0 bg-base-content/30 backdrop-blur-sm"
          phx-click={JS.hide(to: "#" <> @dialog)}
        >
        </div>
        <div
          id={@dialog <> "-panel"}
          class="glass pop-in relative w-full max-w-sm rounded-[1.75rem] p-6 shadow-2xl"
        >
          <h2 id={@dialog <> "-title"} class="text-lg font-bold tracking-tight">{@title}</h2>
          <p :if={@message} class="mt-2 text-sm text-base-content/70">{@message}</p>
          <div class="mt-6 flex justify-end gap-2">
            <button
              id={@dialog <> "-cancel"}
              type="button"
              class="btn btn-glass rounded-full"
              phx-click={JS.hide(to: "#" <> @dialog)}
            >
              {@cancel_label}
            </button>
            <button
              id={@dialog <> "-confirm"}
              type="button"
              class={[
                "btn rounded-full",
                @tone == :primary && "btn-glow",
                @tone == :danger && "btn-error"
              ]}
              phx-click={JS.hide(@on_confirm, to: "#" <> @dialog)}
            >
              {@confirm_label}
            </button>
          </div>
        </div>
      </div>
    </.portal>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(CookingSchedulerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(CookingSchedulerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
