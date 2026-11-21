defmodule CookingSchedulerWeb.PhotoGallery do
  @moduledoc """
  The photos of one owner (a `Meal` or a `MealDish`) with an add button. A live component
  because one page can hold several galleries, each needing its own upload.

      <.live_component module={PhotoGallery} id="meal-photos" owner={@meal} title="The table" />

  Every DOM id inside is prefixed with `id`. Tapping a photo sends `view_photo` (with the
  photo's id) to the page, which opens its viewer; after an upload or delete the page gets
  `:photos_changed`. `compact` makes a tighter grid for a dish card.
  """
  use CookingSchedulerWeb, :live_component

  alias CookingScheduler.{Photos, Storage}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:error, nil)
     |> assign(:compact, false)
     |> allow_upload(:photo,
       accept: Photos.accepted_extensions(),
       max_entries: 6,
       max_file_size: Photos.max_bytes(),
       auto_upload: true,
       progress: &progress/3
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, assign(socket, :photos, Photos.list_photos(socket.assigns.owner))}
  end

  defp progress(:photo, entry, socket) do
    if entry.done? do
      owner = socket.assigns.owner

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Photos.add_photo(owner, path, entry.client_name)}
        end)

      error =
        case result do
          {:ok, _} -> nil
          {:error, :not_an_image} -> "#{entry.client_name} isn't a picture we can use"
          {:error, :too_large} -> "#{entry.client_name} is too big"
          {:error, _} -> "#{entry.client_name} couldn't be saved, try again"
        end

      send(self(), :photos_changed)
      {:noreply, socket |> assign(:photos, Photos.list_photos(owner)) |> assign(:error, error)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    upload = socket.assigns.uploads.photo

    errors =
      for entry <- upload.entries,
          err <- upload_errors(upload, entry),
          do: "#{entry.client_name}: #{error_text(err)}"

    {:noreply, assign(socket, :error, List.first(errors))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.photos, &(to_string(&1.id) == to_string(id))) do
      nil -> :ok
      photo -> {:ok, _} = Photos.delete_photo(photo)
    end

    send(self(), :photos_changed)
    {:noreply, assign(socket, :photos, Photos.list_photos(socket.assigns.owner))}
  end

  defp error_text(:too_large), do: "too big (10 MB at most)"
  defp error_text(:not_accepted), do: "not a JPEG, PNG, WebP or GIF"
  defp error_text(:too_many_files), do: "too many at once (6 at most)"
  defp error_text(_), do: "couldn't upload"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :enabled, Storage.enabled?())

    ~H"""
    <div id={@id}>
      <ul
        :if={@enabled}
        id={"#{@id}-grid"}
        class={[
          "grid",
          (@compact && "grid-cols-4 gap-1.5") || "grid-cols-3 gap-2 sm:grid-cols-4"
        ]}
      >
        <li
          :for={photo <- @photos}
          id={"#{@id}-photo-#{photo.id}"}
          class={[
            "group relative aspect-square overflow-hidden bg-base-content/5",
            (@compact && "rounded-xl") || "rounded-2xl"
          ]}
        >
          <button
            type="button"
            id={"#{@id}-view-#{photo.id}"}
            phx-click={JS.push("view_photo", value: %{photo: photo.id})}
            aria-label={"View #{photo.filename || "photo"}"}
            class="block size-full"
          >
            <img
              src={~p"/photos/#{photo.id}"}
              alt={photo.filename || "Photo"}
              loading="lazy"
              class="size-full object-cover transition duration-300 group-hover:scale-105"
            />
          </button>
          <.confirm_button
            id={"#{@id}-delete-#{photo.id}"}
            title="Delete this photo?"
            message="This can't be undone."
            confirm_label="Delete"
            tone={:danger}
            on_confirm={JS.push("delete", value: %{id: photo.id}, target: @myself)}
            aria-label="Delete photo"
            class="btn btn-circle btn-xs absolute right-1.5 top-1.5 border-0 bg-base-100/80 opacity-0 backdrop-blur transition hover:text-error focus:opacity-100 group-hover:opacity-100 [@media(hover:none)]:opacity-100"
          >
            <.icon name="hero-trash" class="size-4" />
          </.confirm_button>
        </li>

        <li
          :for={entry <- @uploads.photo.entries}
          id={"#{@id}-uploading-#{entry.ref}"}
          class="relative flex aspect-square items-center justify-center overflow-hidden rounded-2xl bg-base-content/5"
        >
          <.live_img_preview entry={entry} class="size-full object-cover opacity-50" />
          <span class="absolute inset-x-3 bottom-3 h-1.5 overflow-hidden rounded-full bg-base-content/20">
            <span class="block h-full bg-primary transition-all" style={"width: #{entry.progress}%"}></span>
          </span>
        </li>

        <li class="aspect-square">
          <.form
            for={%{}}
            id={"#{@id}-form"}
            phx-change="validate"
            phx-target={@myself}
            class="size-full"
          >
            <label
              for={@uploads.photo.ref}
              id={"#{@id}-add"}
              class={[
                "flex size-full cursor-pointer flex-col items-center justify-center gap-0.5 border-2 border-dashed border-base-content/20 text-base-content/60 transition hover:border-primary hover:text-primary",
                (@compact && "rounded-xl text-[11px]") || "rounded-2xl text-sm"
              ]}
            >
              <.icon name="hero-camera" class={(@compact && "size-5") || "size-6"} />
              {if @compact, do: "Add", else: "Add photos"}
            </label>
            <.live_file_input upload={@uploads.photo} class="sr-only" />
          </.form>
        </li>
      </ul>

      <p :if={@error} id={"#{@id}-error"} class="mt-2 text-sm text-error">{@error}</p>
    </div>
    """
  end
end
