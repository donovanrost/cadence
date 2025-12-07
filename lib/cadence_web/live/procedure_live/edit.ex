defmodule CadenceWeb.ProcedureLive.Edit do
  @moduledoc """
  Full-page DAG procedure editor.

  This LiveView is intentionally minimal - it handles:
  - Initial data load
  - Saving to database
  - Authorization

  All UI state (zoom, pan, selection, modals) is managed client-side in the JS hook.
  """
  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.Procedure

  @impl true
  def mount(%{"id" => _mission_id, "procedure_id" => procedure_id}, _session, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :update, socket.assigns.current_scope, mission) do
      :ok ->
        procedure = Procedures.get_procedure(procedure_id)

        if procedure && procedure.mission_id == mission.id do
          {steps, inputs, on_step_failure, _format} = load_procedure_source(procedure)

          {:ok,
           socket
           |> assign(:page_title, "Edit: #{procedure.name}")
           |> assign(:procedure, procedure)
           |> assign(:steps, steps)
           |> assign(:inputs, inputs)
           |> assign(:on_step_failure, on_step_failure)
           |> assign(:dirty, false)
           |> assign(:saving, false)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Procedure not found")
           |> push_navigate(to: ~p"/missions/#{mission}/procedures")}
        end

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to edit procedures")
         |> push_navigate(to: ~p"/missions/#{mission}/procedures")}
    end
  end

  def mount(%{"id" => _mission_id}, _session, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :update, socket.assigns.current_scope, mission) do
      :ok ->
        {:ok,
         socket
         |> assign(:page_title, "New Procedure")
         |> assign(:procedure, %Procedure{type: :dag, mission_id: mission.id})
         |> assign(:steps, %{})
         |> assign(:inputs, %{})
         |> assign(:on_step_failure, "abort")
         |> assign(:dirty, false)
         |> assign(:saving, false)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "You don't have permission to create procedures")
         |> push_navigate(to: ~p"/missions/#{mission}/procedures")}
    end
  end

  defp load_procedure_source(procedure) do
    if procedure.current_version_id do
      case Procedures.get_version(procedure.current_version_id) do
        nil ->
          {%{}, %{}, "abort", :dag}

        version ->
          source = version.source || %{}
          steps = source["steps"] || %{}
          on_step_failure = source["on_step_failure"] || "abort"
          # Convert from storage format to editor format
          inputs = params_schema_to_editor_format(version.parameters_schema)
          format = if is_map(steps), do: :dag, else: :linear
          {steps, inputs, on_step_failure, format}
      end
    else
      {%{}, %{}, "abort", :dag}
    end
  end

  # Convert from storage format {"parameters" => [...]} to editor format {"name" => {...}}
  defp params_schema_to_editor_format(nil), do: %{}
  defp params_schema_to_editor_format(%{"parameters" => params}) when is_list(params) do
    params
    |> Enum.map(fn param ->
      name = param["name"]
      definition = Map.drop(param, ["name"])
      {name, definition}
    end)
    |> Map.new()
  end
  defp params_schema_to_editor_format(schema) when is_map(schema) do
    # Already in editor format or empty
    if Map.has_key?(schema, "parameters"), do: %{}, else: schema
  end
  defp params_schema_to_editor_format(_), do: %{}

  # Convert from editor format {"name" => {...}} to storage format {"parameters" => [...]}
  defp editor_format_to_params_schema(inputs) when is_map(inputs) and map_size(inputs) > 0 do
    params =
      inputs
      |> Enum.map(fn {name, definition} ->
        Map.put(definition, "name", name)
      end)
      |> Enum.sort_by(& &1["name"])

    %{"parameters" => params}
  end
  defp editor_format_to_params_schema(_), do: %{}

  # ============================================================================
  # Event Handlers - Only data mutations, no UI state
  # ============================================================================

  @impl true
  def handle_event("save", %{"name" => name, "steps" => steps_json, "inputs" => inputs_json} = params, socket) do
    mission = socket.assigns.mission
    procedure = socket.assigns.procedure
    on_step_failure = params["on_step_failure"] || socket.assigns.on_step_failure

    with {:ok, steps} <- Jason.decode(steps_json),
         {:ok, inputs} <- Jason.decode(inputs_json),
         :ok <- validate_input_references(steps, inputs) do
      source = %{"steps" => steps, "on_step_failure" => on_step_failure}
      # Convert editor format to storage format
      params_schema = editor_format_to_params_schema(inputs)
      save_procedure(socket, procedure, %{"name" => name}, source, params_schema, mission)
    else
      {:error, :invalid_references, errors} ->
        error_msg = format_reference_errors(errors)
        {:noreply, put_flash(socket, :error, error_msg)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid data format")}
    end
  end

  # Fallback for old format without inputs
  def handle_event("save", %{"name" => name, "steps" => steps_json} = params, socket) do
    mission = socket.assigns.mission
    procedure = socket.assigns.procedure
    on_step_failure = params["on_step_failure"] || socket.assigns.on_step_failure

    case Jason.decode(steps_json) do
      {:ok, steps} ->
        source = %{"steps" => steps, "on_step_failure" => on_step_failure}
        save_procedure(socket, procedure, %{"name" => name}, source, %{}, mission)

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid steps data")}
    end
  end

  def handle_event("cancel", _, socket) do
    mission = socket.assigns.mission
    {:noreply, push_navigate(socket, to: ~p"/missions/#{mission}/procedures")}
  end

  defp save_procedure(socket, procedure, params, source, inputs, mission) do
    socket = assign(socket, :saving, true)

    result =
      if procedure.id do
        with {:ok, procedure} <- Procedures.update_procedure(procedure, params),
             {:ok, _version} <- maybe_create_version(procedure, source, inputs, socket.assigns.current_scope.user) do
          {:ok, procedure}
        end
      else
        attrs =
          params
          |> Map.put("organization_id", mission.organization_id)
          |> Map.put("mission_id", mission.id)
          |> Map.put("type", "dag")

        # create_procedure creates the initial version with the source and inputs
        Procedures.create_procedure(attrs,
          source: source,
          parameters_schema: inputs,
          user_id: socket.assigns.current_scope.user.id
        )
      end

    case result do
      {:ok, _procedure} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> assign(:dirty, false)
         |> put_flash(:info, "Procedure saved successfully")
         |> push_navigate(to: ~p"/missions/#{mission}/procedures")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:saving, false)
         |> put_flash(:error, "Failed to save: #{inspect(changeset.errors)}")}
    end
  end

  defp maybe_create_version(procedure, source, inputs, user) do
    {current_source, current_inputs} =
      if procedure.current_version_id do
        case Procedures.get_version(procedure.current_version_id) do
          nil -> {nil, nil}
          version -> {version.source, version.parameters_schema}
        end
      else
        {nil, nil}
      end

    if source != current_source || inputs != current_inputs do
      with {:ok, version} <- Procedures.create_version(procedure, %{
             source: source,
             parameters_schema: inputs,
             status: :draft,
             created_by_id: user.id
           }),
           {:ok, _procedure} <- Procedures.update_procedure(procedure, %{current_version_id: version.id}) do
        {:ok, version}
      end
    else
      {:ok, nil}
    end
  end

  defp validate_input_references(steps, inputs) do
    alias Cadence.Procedures.InputReferences

    case InputReferences.validate_references(steps, inputs) do
      :ok -> :ok
      {:error, errors} -> {:error, :invalid_references, errors}
    end
  end

  defp format_reference_errors(errors) do
    grouped =
      errors
      |> Enum.group_by(fn {step, _input} -> step end, fn {_step, input} -> input end)

    messages =
      Enum.map(grouped, fn {step, inputs} ->
        input_list = Enum.join(inputs, ", ")
        "Step '#{step}' references undefined input(s): #{input_list}"
      end)

    "Invalid input references: " <> Enum.join(messages, "; ")
  end

  # ============================================================================
  # Render - Minimal template, JS hook does the heavy lifting
  # ============================================================================

  @impl true
  def render(assigns) do
    # Use negative margins to counteract the p-6 padding from the mission_sidebar layout
    # This allows the editor to fill the content area edge-to-edge while keeping the sidebar
    ~H"""
    <div
      id="dag-editor"
      class="-m-6 h-[calc(100vh-4rem)] flex flex-col bg-base-100"
      phx-hook="DagEditor"
      data-steps={Jason.encode!(@steps)}
      data-inputs={Jason.encode!(@inputs)}
      data-on-step-failure={@on_step_failure}
      data-procedure-name={@procedure.name || ""}
      data-procedure-id={@procedure.id}
      data-mission-url={~p"/missions/#{@mission}/procedures"}
      data-saving={to_string(@saving)}
    >
      <!-- The entire UI is rendered by the JS hook -->
      <div class="flex-1 flex items-center justify-center text-base-content/30">
        <div class="text-center">
          <div class="loading loading-spinner loading-lg"></div>
          <p class="mt-4">Loading editor...</p>
        </div>
      </div>
    </div>
    """
  end
end
