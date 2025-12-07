defmodule CadenceWeb.ProcedureLive.ParameterFormComponent do
  @moduledoc """
  Form component for procedure parameter input.

  Renders form fields based on the procedure's parameter schema, supporting
  all parameter types defined in `Cadence.Procedures.Parameters`.
  """
  use CadenceWeb, :live_component

  alias Cadence.Procedures.Parameters
  alias Cadence.Targets

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :errors, %{})}
  end

  @impl true
  def update(assigns, socket) do
    schema = assigns[:parameters_schema] || %{}
    # Handle both new format {"parameters" => [...]} and legacy format {"name" => {...}}
    param_defs = normalize_param_defs(schema)

    # Initialize values with defaults
    initial_values = extract_defaults(param_defs)
    current_values = Map.merge(initial_values, assigns[:values] || %{})

    # Load targets if we have a target parameter
    targets =
      if has_target_param?(param_defs) do
        Targets.list_targets(assigns.mission_id)
      else
        []
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:param_defs, param_defs)
     |> assign(:values, current_values)
     |> assign(:targets, targets)
     |> assign(:errors, %{})}
  end

  @impl true
  def handle_event("validate", %{"parameters" => params}, socket) do
    context = %{mission_id: socket.assigns.mission_id}

    case Parameters.validate(params, socket.assigns.parameters_schema, context) do
      {:ok, _validated} ->
        {:noreply, assign(socket, :errors, %{})}

      {:error, errors} ->
        error_map = Map.new(errors)
        {:noreply, assign(socket, :errors, error_map)}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("submit", %{"parameters" => params}, socket) do
    context = %{mission_id: socket.assigns.mission_id}

    case Parameters.validate(params, socket.assigns.parameters_schema, context) do
      {:ok, validated} ->
        send(self(), {__MODULE__, {:submit_parameters, validated}})
        {:noreply, socket}

      {:error, errors} ->
        error_map = Map.new(errors)
        {:noreply, assign(socket, :errors, error_map)}
    end
  end

  def handle_event("submit", _params, socket) do
    # No parameters, just submit empty
    send(self(), {__MODULE__, {:submit_parameters, %{}}})
    {:noreply, socket}
  end

  # Normalize parameter definitions to handle both formats:
  # - New format: %{"parameters" => [%{"name" => "x", "type" => "string"}, ...]}
  # - Legacy format: %{"x" => %{"type" => "string"}, ...}
  defp normalize_param_defs(%{"parameters" => params}) when is_list(params), do: params
  defp normalize_param_defs(schema) when is_map(schema) and map_size(schema) > 0 do
    # Check if it's legacy format (no "parameters" key, values are maps with "type")
    if Enum.all?(schema, fn {k, v} -> is_binary(k) and is_map(v) and Map.has_key?(v, "type") end) do
      # Convert legacy format to new format
      schema
      |> Enum.map(fn {name, definition} -> Map.put(definition, "name", name) end)
      |> Enum.sort_by(& &1["name"])
    else
      []
    end
  end
  defp normalize_param_defs(_), do: []

  defp extract_defaults(param_defs) do
    param_defs
    |> Enum.filter(&Map.has_key?(&1, "default"))
    |> Enum.map(fn p -> {p["name"], p["default"]} end)
    |> Map.new()
  end

  defp has_target_param?(param_defs) do
    Enum.any?(param_defs, fn p -> p["type"] == "target" end)
  end

  defp get_value(values, name) do
    Map.get(values, name) || Map.get(values, to_string(name))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={%{}}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="submit"
        class="space-y-4"
      >
        <%= if Enum.empty?(@param_defs) do %>
          <p class="text-sm text-base-content/60">
            No parameters required for this procedure.
          </p>
        <% else %>
          <div class="space-y-4">
            <.param_field
              :for={param <- @param_defs}
              param={param}
              value={get_value(@values, param["name"])}
              error={Map.get(@errors, param["name"])}
              targets={@targets}
            />
          </div>
        <% end %>

        <div class="flex justify-end gap-2 pt-4 border-t border-base-300">
          <.button type="button" phx-click={@on_cancel} class="btn-ghost">
            Cancel
          </.button>
          <.button type="submit" class="btn-success">
            <.icon name="hero-play" class="h-4 w-4 mr-1" /> Execute
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  # Individual parameter field component
  attr :param, :map, required: true
  attr :value, :any, default: nil
  attr :error, :string, default: nil
  attr :targets, :list, default: []

  defp param_field(assigns) do
    ~H"""
    <div>
      <label class="label">
        <span class="label-text">
          {@param["name"]}
          <span :if={@param["required"]} class="text-error">*</span>
        </span>
        <span :if={@param["description"]} class="label-text-alt text-base-content/50">
          {@param["description"]}
        </span>
      </label>

      <%= case @param["type"] do %>
        <% "string" -> %>
          <input
            type="text"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            class={["input input-bordered w-full", @error && "input-error"]}
            placeholder={@param["placeholder"] || ""}
            minlength={@param["min_length"]}
            maxlength={@param["max_length"]}
          />

        <% "number" -> %>
          <input
            type="number"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            step="any"
            class={["input input-bordered w-full", @error && "input-error"]}
            min={@param["min"]}
            max={@param["max"]}
          />

        <% "integer" -> %>
          <input
            type="number"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            step="1"
            class={["input input-bordered w-full", @error && "input-error"]}
            min={@param["min"]}
            max={@param["max"]}
          />

        <% "boolean" -> %>
          <div class="flex items-center gap-2">
            <input
              type="checkbox"
              name={"parameters[#{@param["name"]}]"}
              value="true"
              checked={@value == true or @value == "true"}
              class="checkbox"
            />
            <input type="hidden" name={"parameters[#{@param["name"]}]"} value="false" />
          </div>

        <% "enum" -> %>
          <select
            name={"parameters[#{@param["name"]}]"}
            class={["select select-bordered w-full", @error && "select-error"]}
          >
            <option value="">Select...</option>
            <option
              :for={option <- @param["options"] || []}
              value={option}
              selected={@value == option}
            >
              {option}
            </option>
          </select>

        <% "target" -> %>
          <select
            name={"parameters[#{@param["name"]}]"}
            class={["select select-bordered w-full", @error && "select-error"]}
          >
            <option value="">Select target...</option>
            <option :for={target <- @targets} value={target.id} selected={@value == target.id}>
              {target.name}
            </option>
          </select>

        <% "telemetry_item" -> %>
          <input
            type="text"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            class={["input input-bordered w-full font-mono", @error && "input-error"]}
            placeholder="PACKET.item_name"
          />

        <% "command" -> %>
          <input
            type="text"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            class={["input input-bordered w-full font-mono", @error && "input-error"]}
            placeholder="COMMAND_NAME"
          />

        <% "duration" -> %>
          <div class="flex items-center gap-2">
            <input
              type="number"
              name={"parameters[#{@param["name"]}]"}
              value={@value}
              step="1"
              min={@param["min"] || 0}
              max={@param["max"]}
              class={["input input-bordered flex-1", @error && "input-error"]}
            />
            <span class="text-sm text-base-content/60">ms</span>
          </div>

        <% "datetime" -> %>
          <input
            type="datetime-local"
            name={"parameters[#{@param["name"]}]"}
            value={format_datetime_local(@value)}
            class={["input input-bordered w-full", @error && "input-error"]}
          />

        <% "array" -> %>
          <.array_field param={@param} value={@value} error={@error} />

        <% _ -> %>
          <input
            type="text"
            name={"parameters[#{@param["name"]}]"}
            value={@value}
            class={["input input-bordered w-full", @error && "input-error"]}
          />
      <% end %>

      <label :if={@error} class="label">
        <span class="label-text-alt text-error">{@error}</span>
      </label>

      <label :if={@param["default"] && !@error} class="label">
        <span class="label-text-alt text-base-content/40">
          Default: {inspect(@param["default"])}
        </span>
      </label>
    </div>
    """
  end

  # Array field component - simplified for now
  attr :param, :map, required: true
  attr :value, :any, default: nil
  attr :error, :string, default: nil

  defp array_field(assigns) do
    # For arrays, we use a textarea with JSON or comma-separated values
    value_str =
      case assigns.value do
        nil -> ""
        list when is_list(list) -> Enum.join(list, ", ")
        other -> to_string(other)
      end

    assigns = assign(assigns, :value_str, value_str)

    ~H"""
    <div>
      <textarea
        name={"parameters[#{@param["name"]}]"}
        class={["textarea textarea-bordered w-full", @error && "textarea-error"]}
        placeholder="Enter values separated by commas"
        rows="2"
      >{@value_str}</textarea>
      <p class="text-xs text-base-content/50 mt-1">
        Enter multiple values separated by commas
      </p>
    </div>
    """
  end

  defp format_datetime_local(nil), do: ""
  defp format_datetime_local(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end
  defp format_datetime_local(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> format_datetime_local(dt)
      _ -> str
    end
  end
  defp format_datetime_local(_), do: ""
end
