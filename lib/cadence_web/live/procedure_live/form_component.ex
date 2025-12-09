defmodule CadenceWeb.ProcedureLive.FormComponent do
  @moduledoc """
  Form component for creating and editing procedures.
  """
  use CadenceWeb, :live_component

  alias Cadence.Procedures

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>
          Define a procedure that can be executed manually or triggered automatically.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="procedure-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" required />

        <.input field={@form[:description]} type="textarea" label="Description" rows={3} />

        <div class="form-control">
          <label class="label">
            <span class="label-text">Tags</span>
          </label>
          <input
            type="text"
            name="tags_input"
            value={@tags_input}
            class="input input-bordered w-full"
            placeholder="Enter tags separated by commas (e.g., safety, recovery, phase-1)"
            phx-target={@myself}
            phx-debounce="blur"
          />
          <label class="label">
            <span class="label-text-alt text-base-content/50">
              Tags must contain only lowercase letters, numbers, and hyphens
            </span>
          </label>
          <div :if={length(@parsed_tags) > 0} class="flex flex-wrap gap-1 mt-1">
            <span :for={tag <- @parsed_tags} class="badge badge-primary badge-sm">{tag}</span>
          </div>
        </div>

        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          options={[
            {"DAG", "dag"},
            {"Script", "script"}
          ]}
        />

        <!-- DAG Settings -->
        <div :if={@form[:type].value == "dag" or @form[:type].value == :dag} class="space-y-4">
          <p class="text-sm text-base-content/60">
            DAG format allows parallel execution of independent steps with explicit dependencies.
            Edit steps in the DAG editor below.
          </p>

          <div class="form-control">
            <label class="label">
              <span class="label-text">On Step Failure</span>
            </label>
            <select
              name="on_step_failure"
              class="select select-bordered w-full max-w-xs"
              phx-debounce="blur"
            >
              <option value="abort" selected={@on_step_failure == "abort"}>
                Abort - Stop entire procedure
              </option>
              <option value="continue" selected={@on_step_failure == "continue"}>
                Continue - Block dependents, continue independent branches
              </option>
              <option value="pause" selected={@on_step_failure == "pause"}>
                Pause - Wait for operator decision
              </option>
            </select>
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Controls what happens when a step fails. Individual steps can override this.
              </span>
            </label>
          </div>
        </div>

        <!-- Script Code Editor -->
        <div :if={@form[:type].value == "script" or @form[:type].value == :script}>
          <label class="block text-sm font-medium mb-2">Lua Code</label>
          <textarea
            name="code"
            id="procedure_code"
            rows={12}
            class="textarea textarea-bordered w-full font-mono text-sm"
            phx-debounce="blur"
          >{@code}</textarea>
          <p class="text-xs text-base-content/50 mt-1">
            Write Lua code using the Cadence API (cadence.telemetry.get, cadence.command.send, etc.)
          </p>
        </div>

        <:actions>
          <.button phx-disable-with="Saving..." class="btn-primary">Save Procedure</.button>
        </:actions>
      </.simple_form>

      <!-- DAG Editor - outside the form to prevent event bubbling issues -->
      <div
        :if={@form[:type].value == "dag" or @form[:type].value == :dag}
        class="mt-4"
      >
        <.live_component
          module={CadenceWeb.ProcedureLive.DagEditorComponent}
          id="dag-editor"
          steps={@dag_steps}
        />
      </div>
    </div>
    """
  end

  @impl true
  def update(%{dag_steps: dag_steps}, socket) do
    # Handle DAG editor step changes forwarded via send_update
    {:ok, assign(socket, :dag_steps, dag_steps)}
  end

  def update(%{procedure: procedure} = assigns, socket) do
    # Extract source data for editing
    {source_json, code, dag_steps, on_step_failure} = extract_source(procedure)

    # Extract tags for editing
    tags = procedure.tags || []
    tags_input = Enum.join(tags, ", ")

    changeset = Procedures.change_procedure(procedure)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:source_json, source_json)
     |> assign(:code, code)
     |> assign(:dag_steps, dag_steps)
     |> assign(:on_step_failure, on_step_failure)
     |> assign(:tags_input, tags_input)
     |> assign(:parsed_tags, tags)
     |> assign_form(changeset)}
  end

  defp extract_source(procedure) do
    if procedure.id do
      case Procedures.get_version(procedure.current_version_id) do
        nil ->
          {"", "-- Lua code here", default_dag_steps(), "abort"}

        version ->
          on_step_failure = version.source["on_step_failure"] || "abort"

          case procedure.type do
            :dag ->
              steps = version.source["steps"] || %{}
              dag_steps = if is_map(steps), do: steps, else: default_dag_steps()
              {"", "", dag_steps, on_step_failure}

            :script ->
              {"", version.source["code"] || "-- Lua code here", default_dag_steps(), "abort"}

            _ ->
              {"", "-- Lua code here", default_dag_steps(), "abort"}
          end
      end
    else
      {"", "-- Lua code here", default_dag_steps(), "abort"}
    end
  end

  defp default_dag_steps do
    %{
      "init" => %{"type" => "log", "level" => "info", "message" => "Starting procedure", "depends_on" => []},
      "finish" => %{"type" => "log", "level" => "info", "message" => "Procedure complete", "depends_on" => ["init"]}
    }
  end

  @impl true
  def handle_event("validate", %{"procedure" => procedure_params} = params, socket) do
    # Parse tags from input
    tags_input = params["tags_input"] || socket.assigns.tags_input
    parsed_tags = parse_tags(tags_input)

    changeset =
      socket.assigns.procedure
      |> Procedures.change_procedure(procedure_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:source_json, params["source_json"] || socket.assigns.source_json)
     |> assign(:code, params["code"] || socket.assigns.code)
     |> assign(:on_step_failure, params["on_step_failure"] || socket.assigns.on_step_failure)
     |> assign(:tags_input, tags_input)
     |> assign(:parsed_tags, parsed_tags)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"procedure" => procedure_params} = params, socket) do
    # Build source from the form inputs
    # Type could be string or atom depending on whether the select was changed
    type = to_string(procedure_params["type"] || socket.assigns.procedure.type || "dag")
    on_step_failure = params["on_step_failure"] || socket.assigns.on_step_failure

    # Parse tags from input
    tags_input = params["tags_input"] || socket.assigns.tags_input
    parsed_tags = parse_tags(tags_input)

    # Add tags to procedure params
    procedure_params = Map.put(procedure_params, "tags", parsed_tags)

    source =
      case type do
        "dag" ->
          # DAG format: steps is a map keyed by step name
          %{
            "steps" => socket.assigns.dag_steps,
            "on_step_failure" => on_step_failure
          }

        "script" ->
          %{"code" => params["code"] || ""}

        _ ->
          %{"steps" => %{}}
      end

    save_procedure(socket, socket.assigns.action, procedure_params, source)
  end

  defp save_procedure(socket, :edit, procedure_params, source) do
    case Procedures.update_procedure(socket.assigns.procedure, procedure_params) do
      {:ok, procedure} ->
        # Only create a new version if the source has changed
        current_source = get_current_source(procedure)

        if source_changed?(current_source, source) do
          Procedures.create_version(
            procedure.id,
            %{source: source},
            user_id: socket.assigns.current_user.id
          )
        end

        notify_parent({:saved, procedure})

        {:noreply,
         socket
         |> put_flash(:info, "Procedure updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_procedure(socket, :new, procedure_params, source) do
    attrs =
      Map.merge(procedure_params, %{
        "organization_id" => socket.assigns.mission.organization_id,
        "mission_id" => socket.assigns.mission.id
      })

    case Procedures.create_procedure(attrs,
           user_id: socket.assigns.current_user.id,
           source: source
         ) do
      {:ok, procedure} ->
        notify_parent({:saved, procedure})

        {:noreply,
         socket
         |> put_flash(:info, "Procedure created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp get_current_source(procedure) do
    if procedure.current_version_id do
      case Procedures.get_version(procedure.current_version_id) do
        nil -> nil
        version -> version.source
      end
    else
      nil
    end
  end

  defp source_changed?(nil, _new_source), do: true
  defp source_changed?(_current, nil), do: true

  defp source_changed?(current_source, new_source) do
    # Normalize both sources for comparison (handle string vs atom keys)
    normalize_source(current_source) != normalize_source(new_source)
  end

  defp normalize_source(source) when is_map(source) do
    source
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp normalize_source(source), do: source

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp parse_tags(input) when is_binary(input) do
    input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_tags(_), do: []
end
