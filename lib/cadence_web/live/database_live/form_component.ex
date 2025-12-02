defmodule CadenceWeb.DatabaseLive.FormComponent do
  @moduledoc """
  Form component for importing a new DefinitionSet version into a Database.

  This is a simplified version that always imports into a specific Database.
  """
  use CadenceWeb, :live_component

  alias Cadence.MissionDatabase
  alias Cadence.MissionDatabase.{DefinitionSet, Database, YamlImporter}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Upload a YAML file to import a new version into <%= @database.name %>.</:subtitle>
      </.header>

      <form
        id="database-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-6"
      >
        <div class="space-y-6">
          <div>
            <label class="block text-sm font-semibold leading-6 text-zinc-800 mb-2">
              Database File (YAML)
            </label>
            <div
              class="mt-2 flex justify-center rounded-lg border border-dashed border-zinc-900/25 px-6 py-10"
              phx-drop-target={@uploads.yaml_file.ref}
            >
              <div class="text-center">
                <svg
                  class="mx-auto h-12 w-12 text-gray-300"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path
                    fill-rule="evenodd"
                    d="M1.5 6a2.25 2.25 0 012.25-2.25h16.5A2.25 2.25 0 0122.5 6v12a2.25 2.25 0 01-2.25 2.25H3.75A2.25 2.25 0 011.5 18V6zM3 16.06V18c0 .414.336.75.75.75h16.5A.75.75 0 0021 18v-1.94l-2.69-2.689a1.5 1.5 0 00-2.12 0l-.88.879.97.97a.75.75 0 11-1.06 1.06l-5.16-5.159a1.5 1.5 0 00-2.12 0L3 16.061zm10.125-7.81a1.125 1.125 0 112.25 0 1.125 1.125 0 01-2.25 0z"
                    clip-rule="evenodd"
                  />
                </svg>
                <div class="mt-4 flex text-sm leading-6 text-gray-600">
                  <label
                    for={@uploads.yaml_file.ref}
                    class="relative cursor-pointer rounded-md bg-white font-semibold text-zinc-900 focus-within:outline-none focus-within:ring-2 focus-within:ring-zinc-900 focus-within:ring-offset-2 hover:text-zinc-700"
                  >
                    <span>Upload a file</span>
                    <.live_file_input upload={@uploads.yaml_file} class="sr-only" />
                  </label>
                  <p class="pl-1">or drag and drop</p>
                </div>
                <p class="text-xs leading-5 text-gray-600">YAML files (.yaml or .yml)</p>
              </div>
            </div>

            <%= for entry <- @uploads.yaml_file.entries do %>
              <div class="mt-4 p-4 bg-zinc-50 rounded-lg border border-zinc-200">
                <div class="flex items-center justify-between">
                  <div class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-zinc-500"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                      />
                    </svg>
                    <span class="text-sm font-medium text-zinc-700"><%= entry.client_name %></span>
                    <span class="text-xs text-zinc-500">
                      (<%= format_bytes(entry.client_size) %>)
                    </span>
                  </div>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    phx-target={@myself}
                    class="text-sm text-zinc-500 hover:text-zinc-700"
                  >
                    Remove
                  </button>
                </div>
                <progress value={entry.progress} max="100" class="w-full h-1 mt-2">
                  <%= entry.progress %>%
                </progress>
                <%= for err <- upload_errors(@uploads.yaml_file, entry) do %>
                  <p class="text-red-600 text-sm mt-2"><%= error_to_string(err) %></p>
                <% end %>
              </div>
            <% end %>
          </div>

          <div>
            <label class="block text-sm font-semibold leading-6 text-zinc-800" for="version">
              Version Override (optional)
            </label>
            <input
              type="text"
              name="version"
              id="version"
              value={@version_override}
              placeholder="Leave blank to use version from YAML"
              class="mt-2 block w-full rounded-md border-zinc-300 shadow-sm focus:border-zinc-900 focus:ring-zinc-900 sm:text-sm"
            />
            <p class="mt-1 text-sm text-zinc-500">
              Override the version string if you need to specify a different version.
            </p>
          </div>

          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              name="publish"
              id="publish"
              checked={@publish_immediately}
              class="rounded border-zinc-300 text-zinc-900 focus:ring-zinc-900"
            />
            <label for="publish" class="text-sm font-medium text-zinc-700">
              Publish immediately after import
            </label>
          </div>
        </div>

        <div class="mt-6 flex items-center justify-end gap-x-6">
          <.link patch={@patch} class="text-sm font-semibold leading-6 text-zinc-900">
            Cancel
          </.link>
          <.button
            type="submit"
            phx-disable-with="Importing..."
            disabled={Enum.empty?(@uploads.yaml_file.entries)}
          >
            Import
          </.button>
        </div>
      </form>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:version_override, "")
     |> assign(:publish_immediately, false)
     |> allow_upload(:yaml_file,
       accept: :any,
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    version_override = Map.get(params, "version", "")
    publish_immediately = Map.get(params, "publish", "false") == "on"

    {:noreply,
     socket
     |> assign(:version_override, version_override)
     |> assign(:publish_immediately, publish_immediately)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :yaml_file, ref)}
  end

  def handle_event("save", params, socket) do
    mission = socket.assigns.mission
    database = socket.assigns.database
    scope = socket.assigns.current_scope

    # Consume uploaded file
    uploaded_files =
      consume_uploaded_entries(socket, :yaml_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case uploaded_files do
      [] ->
        {:noreply, put_flash(socket, :error, "Please upload a YAML file")}

      [yaml_content | _] ->
        case Bodyguard.permit(Cadence.Missions.Policy, :manage_targets, scope, mission) do
          :ok ->
            import_database(socket, database, yaml_content, params)

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "You don't have permission to manage databases in this mission")
             |> push_patch(to: socket.assigns.patch)}
        end
    end
  end

  defp import_database(socket, database, yaml_content, params) do
    version_override = Map.get(params, "version", "")
    publish = Map.get(params, "publish", "false") == "on"

    opts = [database_id: database.id]
    opts = if version_override != "", do: Keyword.put(opts, :version, version_override), else: opts

    case YamlImporter.import_string(database, yaml_content, opts) do
      {:ok, definition_set} ->
        definition_set =
          if publish do
            case DefinitionSet.publish(definition_set) do
              {:ok, published} -> published
              {:error, _} -> definition_set
            end
          else
            definition_set
          end

        notify_parent({:saved, definition_set})

        message =
          if publish,
            do: "Version #{definition_set.version} imported and published",
            else: "Version #{definition_set.version} imported (draft)"

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_patch(to: socket.assigns.patch)}

      {:error, {:yaml_parse_error, reason}} ->
        {:noreply, put_flash(socket, :error, "YAML parse error: #{inspect(reason)}")}

      {:error, {:validation_error, message}} ->
        {:noreply, put_flash(socket, :error, "Validation error: #{message}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Import failed: #{inspect(reason)}")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(err), do: "Error: #{inspect(err)}"
end
