defmodule CadenceWeb.MissionLive.Procedures do
  @moduledoc """
  LiveView for managing and executing V2 procedures within a mission.
  """

  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.Procedure
  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Procedures.V2.ExecutionQueries

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, params) do
    mission = socket.assigns.mission
    selected_tags = parse_tag_params(params["tags"])
    filters_form = build_filters_form(selected_tags)

    procedures =
      Procedures.list_procedures(
        mission.organization_id,
        mission_id: mission.id,
        tags: selected_tags
      )

    execution_counts = execution_counts(mission.id)
    available_tags = Procedures.list_tags(mission.organization_id, mission_id: mission.id)

    socket
    |> assign(:page_title, "Procedures")
    |> assign(:procedures, procedures)
    |> assign(:selected_procedure, nil)
    |> assign(:versions, [])
    |> assign(:recent_executions, [])
    |> assign(:execution_counts, execution_counts)
    |> assign(:available_tags, available_tags)
    |> assign(:selected_tags, selected_tags)
    |> assign(:filters_form, filters_form)
  end

  defp apply_action(socket, :show, %{"procedure_id" => procedure_id}) do
    socket = apply_action(socket, :index, %{})
    mission = socket.assigns.mission

    case load_procedure_for_mission(mission, procedure_id) do
      {:ok, procedure} ->
        versions = Procedures.list_versions(procedure.id)
        executions = ExecutionQueries.list_executions_for_procedure(procedure.id, limit: 10)

        socket
        |> assign(:page_title, procedure.name)
        |> assign(:selected_procedure, procedure)
        |> assign(:versions, attach_approval_statuses(versions))
        |> assign(:recent_executions, executions)

      {:error, message} ->
        socket
        |> put_flash(:error, message)
        |> push_patch(to: ~p"/missions/#{mission}/procedures")
    end
  end

  defp apply_action(socket, :execute, %{"procedure_id" => procedure_id}) do
    socket = apply_action(socket, :show, %{"procedure_id" => procedure_id})
    procedure = socket.assigns.selected_procedure
    version = current_version(procedure)
    parameters = extract_parameters(version)

    execution_form =
      to_form(
        %{
          "target_id" => "",
          "parameters" => defaults_for_parameters(parameters)
        },
        as: :execution
      )

    socket
    |> assign(:page_title, "Execute #{procedure.name}")
    |> assign(:execution_form, execution_form)
    |> assign(:execution_parameters, parameters)
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => %{"tags" => tags}}, socket) do
    mission = socket.assigns.mission
    tags = tags |> String.trim() |> normalize_tag_params()

    {:noreply, push_patch(socket, to: ~p"/missions/#{mission}/procedures?tags=#{tags}")}
  end

  def handle_event("create_procedure", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    default_name = "New Procedure #{Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")}"

    attrs = %{
      name: default_name,
      description: nil,
      tags: [],
      organization_id: mission.organization_id,
      mission_id: mission.id
    }

    case Procedures.create_procedure_v2(attrs, user_id: scope.user.id) do
      {:ok, {procedure, version}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Procedure created")
         |> push_navigate(
           to: ~p"/missions/#{mission}/procedures-v2/#{procedure.id}/versions/#{version.id}/edit"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create procedure: #{inspect(reason)}")}
    end
  end

  def handle_event("start_execution", %{"execution" => params}, socket) do
    mission = socket.assigns.mission
    procedure = socket.assigns.selected_procedure
    target_id = normalize_optional(params["target_id"])
    parameters = params["parameters"] || %{}

    case Procedures.start_execution(procedure.id,
           target_id: target_id,
           parameters: parameters,
           user_id: socket.assigns.current_scope.user.id,
           triggered_by: :manual
         ) do
      {:ok, execution} ->
        {:noreply,
         socket
         |> put_flash(:info, "Execution started")
         |> push_navigate(
           to: ~p"/missions/#{mission}/procedures-v2/#{procedure.id}/executions/#{execution.id}"
         )}

      {:error, {:validation, errors}} ->
        {:noreply, put_flash(socket, :error, "Invalid parameters: #{inspect(errors)}")}

      {:error, {:target_not_found, identifier}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Target #{inspect(identifier)} not found for this mission"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start execution: #{inspect(reason)}")}
    end
  end

  defp build_filters_form(selected_tags) do
    to_form(%{"tags" => Enum.join(selected_tags, ",")}, as: :filters)
  end

  defp load_procedure_for_mission(mission, procedure_id) do
    case Procedures.get_procedure(procedure_id) do
      nil ->
        {:error, "Procedure not found"}

      %Procedure{mission_id: mission_id} = procedure when mission_id == mission.id ->
        {:ok, procedure}

      _procedure ->
        {:error, "Procedure not found in this mission"}
    end
  end

  defp attach_approval_statuses(versions) do
    Enum.map(versions, &maybe_attach_approval_status/1)
  end

  defp maybe_attach_approval_status(%{status: :in_review} = version) do
    Map.put(version, :approval_status, Procedures.get_approval_status(version))
  end

  defp maybe_attach_approval_status(version), do: version

  defp execution_counts(mission_id) do
    ExecutionQueries.list_executions_for_mission(mission_id,
      status: [:running, :paused, :pausing]
    )
    |> Enum.reduce(%{running: 0, paused: 0}, fn execution, acc ->
      case execution.status do
        :running -> %{acc | running: acc.running + 1}
        :paused -> %{acc | paused: acc.paused + 1}
        :pausing -> %{acc | running: acc.running + 1}
        _ -> acc
      end
    end)
  end

  defp current_version(nil), do: nil

  defp current_version(%Procedure{current_version_id: nil}), do: nil

  defp current_version(%Procedure{current_version_id: version_id}) do
    Procedures.get_version(version_id)
  end

  defp extract_parameters(nil), do: []

  defp extract_parameters(%ProcedureVersion{parameters_schema: %{"parameters" => params}})
       when is_list(params) do
    params
  end

  defp extract_parameters(_), do: []

  defp defaults_for_parameters(params) do
    Enum.reduce(params, %{}, fn param, acc ->
      Map.put(acc, param["name"], param["default"])
    end)
  end

  defp parse_tag_params(nil), do: []
  defp parse_tag_params(""), do: []

  defp parse_tag_params(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_tag_params(""), do: ""

  defp normalize_tag_params(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(",")
  end

  defp normalize_optional(nil), do: nil
  defp normalize_optional(""), do: nil
  defp normalize_optional(value), do: value

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="max-w-7xl mx-auto px-6 py-8">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Procedures</h1>
            <p class="text-sm text-base-content/60">
              {length(@procedures)} procedures · {@execution_counts.running} running
            </p>
          </div>
          <button
            type="button"
            id="create-procedure"
            class="btn btn-primary"
            phx-click="create_procedure"
          >
            <.icon name="hero-plus" class="h-4 w-4" /> New Procedure
          </button>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div class="lg:col-span-1 space-y-4">
            <.form for={@filters_form} id="procedure-filters" phx-submit="apply_filters">
              <.input
                field={@filters_form[:tags]}
                type="text"
                label="Filter by tags (comma-separated)"
                placeholder="ops, thermal, recovery"
              />
              <button type="submit" class="btn btn-sm btn-ghost">Apply</button>
            </.form>

            <div class="bg-surface-elevated rounded-lg p-4">
              <h2 class="text-sm font-semibold mb-3">Available Tags</h2>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={tag <- @available_tags}
                  class="badge badge-ghost"
                >
                  {tag}
                </span>
                <span :if={Enum.empty?(@available_tags)} class="text-xs text-base-content/60">
                  No tags yet
                </span>
              </div>
            </div>

            <div class="bg-surface-elevated rounded-lg p-4">
              <h2 class="text-sm font-semibold mb-3">Procedures</h2>
              <div class="space-y-2">
                <.link
                  :for={procedure <- @procedures}
                  navigate={~p"/missions/#{@mission}/procedures/#{procedure.id}"}
                  class={[
                    "block rounded-md px-3 py-2 text-sm hover:bg-base-200 transition",
                    @selected_procedure && @selected_procedure.id == procedure.id &&
                      "bg-base-200 font-semibold"
                  ]}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="truncate">{procedure.name}</span>
                    <span class="text-xs text-base-content/50">
                      v{procedure.current_version_id && procedure.current_version_id != "" &&
                        "current"}
                    </span>
                  </div>
                </.link>
                <div :if={Enum.empty?(@procedures)} class="text-xs text-base-content/60">
                  No procedures yet.
                </div>
              </div>
            </div>
          </div>

          <div class="lg:col-span-2 space-y-6">
            <%= if @selected_procedure do %>
              <div class="bg-surface-elevated rounded-lg p-6 space-y-4">
                <div class="flex items-start justify-between">
                  <div>
                    <h2 class="text-xl font-semibold">{@selected_procedure.name}</h2>
                    <p class="text-sm text-base-content/60">
                      {@selected_procedure.description || "No description"}
                    </p>
                  </div>
                  <div class="flex items-center gap-2">
                    <.link
                      :if={@selected_procedure.current_version_id}
                      class="btn btn-sm btn-outline"
                      navigate={
                        ~p"/missions/#{@mission}/procedures-v2/#{@selected_procedure.id}/versions/#{@selected_procedure.current_version_id}/edit"
                      }
                    >
                      Edit
                    </.link>
                    <.link
                      class="btn btn-sm btn-primary"
                      navigate={
                        ~p"/missions/#{@mission}/procedures/#{@selected_procedure.id}/execute"
                      }
                    >
                      Execute
                    </.link>
                  </div>
                </div>

                <div class="flex flex-wrap gap-2">
                  <span :for={tag <- @selected_procedure.tags || []} class="badge badge-ghost">
                    {tag}
                  </span>
                </div>
              </div>

              <div class="bg-surface-elevated rounded-lg p-6">
                <h3 class="text-sm font-semibold mb-4">Versions</h3>
                <div class="space-y-2">
                  <div
                    :for={version <- @versions}
                    class="flex items-center justify-between rounded-md bg-base-100 px-3 py-2 text-sm"
                  >
                    <div class="flex items-center gap-2">
                      <span class="font-medium">v{version.version_number}</span>
                      <span class="text-xs text-base-content/60">{version.status}</span>
                    </div>
                    <.link
                      class="btn btn-xs btn-ghost"
                      navigate={
                        ~p"/missions/#{@mission}/procedures-v2/#{@selected_procedure.id}/versions/#{version.id}/edit"
                      }
                    >
                      Open
                    </.link>
                  </div>
                  <div :if={Enum.empty?(@versions)} class="text-xs text-base-content/60">
                    No versions yet.
                  </div>
                </div>
              </div>

              <div class="bg-surface-elevated rounded-lg p-6">
                <h3 class="text-sm font-semibold mb-4">Recent Executions</h3>
                <div class="space-y-2">
                  <div
                    :for={execution <- @recent_executions}
                    class="flex items-center justify-between rounded-md bg-base-100 px-3 py-2 text-sm"
                  >
                    <div>
                      <div class="font-medium">{execution.id}</div>
                      <div class="text-xs text-base-content/60">
                        {execution.status} · {execution.inserted_at}
                      </div>
                    </div>
                    <.link
                      class="btn btn-xs btn-ghost"
                      navigate={
                        ~p"/missions/#{@mission}/procedures-v2/#{@selected_procedure.id}/executions/#{execution.id}"
                      }
                    >
                      View
                    </.link>
                  </div>
                  <div :if={Enum.empty?(@recent_executions)} class="text-xs text-base-content/60">
                    No executions yet.
                  </div>
                </div>
              </div>
            <% else %>
              <div class="bg-surface-elevated rounded-lg p-6 text-sm text-base-content/60">
                Select a procedure to view details.
              </div>
            <% end %>

            <%= if @live_action == :execute && @selected_procedure do %>
              <div class="bg-surface-elevated rounded-lg p-6">
                <h3 class="text-sm font-semibold mb-4">Execute Procedure</h3>
                <.form
                  for={@execution_form}
                  id="procedure-execution-form"
                  phx-submit="start_execution"
                >
                  <.input
                    field={@execution_form[:target_id]}
                    type="text"
                    label="Target ID (optional)"
                    placeholder="SC-001"
                  />

                  <div class="mt-4 space-y-3">
                    <h4 class="text-xs font-semibold text-base-content/60 uppercase tracking-wide">
                      Parameters
                    </h4>
                    <%= for param <- @execution_parameters do %>
                      <.input
                        type={parameter_input_type(param)}
                        name={"execution[parameters][#{param["name"]}]"}
                        value={param["default"]}
                        label={param["name"]}
                        placeholder={param["description"]}
                        required={param["required"] == true}
                      />
                    <% end %>
                    <div :if={Enum.empty?(@execution_parameters)} class="text-xs text-base-content/60">
                      No parameters required.
                    </div>
                  </div>

                  <button type="submit" class="btn btn-primary mt-4">
                    Start Execution
                  </button>
                </.form>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp parameter_input_type(%{"type" => "number"}), do: "number"
  defp parameter_input_type(%{"type" => "boolean"}), do: "checkbox"
  defp parameter_input_type(_), do: "text"
end
