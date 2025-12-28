defmodule CadenceWeb.ProcedureLive.DagEditorComponent do
  @moduledoc """
  LiveComponent for editing DAG procedure definitions.

  Provides both visual and text-based editing modes:
  - Visual: Node-based editor for adding/connecting steps
  - Text: YAML/JSON editor for direct source editing

  The component synchronizes between both views.
  """
  use CadenceWeb, :live_component

  alias Cadence.Procedures.Dag.Validator

  @step_types [
    {"check", "Check condition before proceeding"},
    {"command", "Send a command to the target"},
    {"wait", "Wait for a duration"},
    {"wait_for", "Wait for a telemetry condition"},
    {"log", "Log a message"},
    {"set", "Set a variable"},
    {"assert", "Assert a condition (fail if false)"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:mode, :visual)
     |> assign(:selected_step, nil)
     |> assign(:editing_step, nil)
     |> assign(:validation_errors, [])
     |> assign(:text_source, "")}
  end

  @impl true
  def update(assigns, socket) do
    steps = assigns[:steps] || socket.assigns[:steps] || %{}

    # Convert to text for text mode (only if not already set or steps changed)
    text_source =
      if map_size(steps) > 0 do
        Jason.encode!(%{"steps" => steps}, pretty: true)
      else
        ~s|{"steps": {}}|
      end

    # Preserve internal state (editing_step, selected_step, mode) during parent updates
    socket =
      socket
      |> assign(:id, assigns[:id] || socket.assigns[:id])
      |> assign(:steps, steps)
      |> assign(:text_source, text_source)

    # Only set these if not already set (preserve internal state)
    socket =
      if socket.assigns[:mode] do
        socket
      else
        socket
        |> assign(:mode, :visual)
        |> assign(:selected_step, nil)
        |> assign(:editing_step, nil)
        |> assign(:validation_errors, [])
      end

    {:ok, validate_dag(socket)}
  end

  defp validate_dag(socket) do
    case Validator.validate(socket.assigns.steps) do
      :ok ->
        assign(socket, :validation_errors, [])

      {:error, errors} ->
        assign(socket, :validation_errors, errors)
    end
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)

    socket =
      if mode == :text do
        # Sync text from current steps
        text = Jason.encode!(%{"steps" => socket.assigns.steps}, pretty: true)
        assign(socket, :text_source, text)
      else
        # Parse text back to steps if valid
        case Jason.decode(socket.assigns.text_source) do
          {:ok, %{"steps" => steps}} when is_map(steps) ->
            assign(socket, :steps, steps)

          _ ->
            socket
        end
      end

    {:noreply, assign(socket, :mode, mode)}
  end

  def handle_event("add_step", _, socket) do
    # Generate a unique step name
    existing = Map.keys(socket.assigns.steps)
    step_name = generate_step_name(existing)

    new_step = %{
      "type" => "log",
      "message" => "New step"
    }

    steps = Map.put(socket.assigns.steps, step_name, new_step)

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> assign(:editing_step, step_name)
     |> notify_change()
     |> validate_dag()}
  end

  def handle_event("select_step", %{"step" => step_name}, socket) do
    {:noreply, assign(socket, :selected_step, step_name)}
  end

  def handle_event("edit_step", %{"step" => step_name}, socket) do
    {:noreply, assign(socket, :editing_step, step_name)}
  end

  def handle_event("delete_step", %{"step" => step_name}, socket) do
    steps = Map.delete(socket.assigns.steps, step_name)

    # Also remove this step from any depends_on lists
    steps =
      Map.new(steps, fn {name, step} ->
        deps = step["depends_on"] || []
        {name, Map.put(step, "depends_on", List.delete(deps, step_name))}
      end)

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> assign(:selected_step, nil)
     |> assign(:editing_step, nil)
     |> notify_change()
     |> validate_dag()}
  end

  def handle_event("save_step", %{"step" => params}, socket) do
    step_name = socket.assigns.editing_step

    # Build step from params
    step = build_step_from_params(params)

    # Handle rename
    new_name = params["name"] || step_name

    steps =
      if new_name != step_name do
        # Rename: remove old, add new, update references
        socket.assigns.steps
        |> Map.delete(step_name)
        |> Map.put(new_name, step)
        |> update_step_references(step_name, new_name)
      else
        Map.put(socket.assigns.steps, step_name, step)
      end

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> assign(:editing_step, nil)
     |> notify_change()
     |> validate_dag()}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing_step, nil)}
  end

  # Capture form changes within the step editor to prevent bubbling to parent
  def handle_event("step_form_change", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_text", %{"source" => source}, socket) do
    {:noreply, assign(socket, :text_source, source)}
  end

  def handle_event("apply_text", _, socket) do
    case Jason.decode(socket.assigns.text_source) do
      {:ok, %{"steps" => steps}} when is_map(steps) ->
        {:noreply,
         socket
         |> assign(:steps, steps)
         |> notify_change()
         |> validate_dag()}

      {:ok, _} ->
        {:noreply, put_flash(socket, :error, "Source must have a 'steps' object")}

      {:error, %Jason.DecodeError{} = error} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON: #{Exception.message(error)}")}
    end
  end

  def handle_event("add_dependency", %{"step" => step_name, "dep" => dep_name}, socket) do
    steps = socket.assigns.steps
    step = Map.get(steps, step_name, %{})
    deps = step["depends_on"] || []

    if dep_name in deps do
      {:noreply, socket}
    else
      step = Map.put(step, "depends_on", [dep_name | deps])
      steps = Map.put(steps, step_name, step)

      {:noreply,
       socket
       |> assign(:steps, steps)
       |> notify_change()
       |> validate_dag()}
    end
  end

  def handle_event("remove_dependency", %{"step" => step_name, "dep" => dep_name}, socket) do
    steps = socket.assigns.steps
    step = Map.get(steps, step_name, %{})
    deps = step["depends_on"] || []

    step = Map.put(step, "depends_on", List.delete(deps, dep_name))
    steps = Map.put(steps, step_name, step)

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> notify_change()
     |> validate_dag()}
  end

  defp generate_step_name(existing) do
    base = "step"
    num = 1

    generate_step_name(existing, base, num)
  end

  defp generate_step_name(existing, base, num) do
    name = "#{base}_#{num}"

    if name in existing do
      generate_step_name(existing, base, num + 1)
    else
      name
    end
  end

  defp build_step_from_params(params) do
    step_type = params["type"] || "log"
    step = apply_step_type(%{"type" => step_type}, step_type, params)

    # Add dependencies if present
    deps = parse_dependencies(params["depends_on"])
    if deps != [], do: Map.put(step, "depends_on", deps), else: step
  end

  defp apply_step_type(step, "check", params) do
    step
    |> Map.put("condition", params["condition"] || "true")
    |> Map.put("message", params["message"])
    |> Map.put("on_fail", params["on_fail"] || "abort")
  end

  defp apply_step_type(step, "command", params) do
    step
    |> Map.put("name", params["command_name"])
    |> maybe_put_args(params["args"])
  end

  defp apply_step_type(step, "wait", params) do
    Map.put(step, "duration", parse_int(params["duration"], 1000))
  end

  defp apply_step_type(step, "wait_for", params) do
    step
    |> Map.put("item", params["item"])
    |> Map.put("operator", params["operator"] || "==")
    |> Map.put("value", params["value"])
    |> Map.put("timeout", parse_int(params["timeout"], 30_000))
  end

  defp apply_step_type(step, "log", params) do
    step
    |> Map.put("level", params["level"] || "info")
    |> Map.put("message", params["message"] || "")
  end

  defp apply_step_type(step, "set", params) do
    step
    |> Map.put("name", params["var_name"])
    |> Map.put("value", params["value"])
  end

  defp apply_step_type(step, "assert", params) do
    step
    |> Map.put("condition", params["condition"] || "true")
    |> Map.put("message", params["message"])
  end

  defp apply_step_type(step, _type, _params), do: step

  defp maybe_put_args(step, nil), do: step
  defp maybe_put_args(step, ""), do: step

  defp maybe_put_args(step, args_str) do
    case Jason.decode(args_str) do
      {:ok, args} when is_map(args) -> Map.put(step, "args", args)
      _ -> step
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_dependencies(nil), do: []
  defp parse_dependencies(""), do: []
  # Handle list from checkboxes (multiple values with same name)
  defp parse_dependencies(deps) when is_list(deps), do: deps

  defp parse_dependencies(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp update_step_references(steps, old_name, new_name) do
    Map.new(steps, fn {name, step} ->
      {name, update_step_dependencies(step, old_name, new_name)}
    end)
  end

  defp update_step_dependencies(step, old_name, new_name) do
    deps = step["depends_on"] || []
    updated_deps = Enum.map(deps, &replace_dependency(&1, old_name, new_name))
    Map.put(step, "depends_on", updated_deps)
  end

  defp replace_dependency(dep, old_name, new_name) when dep == old_name, do: new_name
  defp replace_dependency(dep, _old_name, _new_name), do: dep

  defp notify_change(socket) do
    send(self(), {__MODULE__, {:steps_changed, socket.assigns.steps}})
    socket
  end

  defp step_types, do: @step_types

  defp available_dependencies(steps, current_step) do
    steps
    |> Map.keys()
    |> Enum.reject(&(&1 == current_step))
    |> Enum.sort()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="dag-editor">
      <!-- Mode Switcher -->
      <div class="flex items-center justify-between mb-4">
        <div class="tabs tabs-boxed">
          <button
            type="button"
            class={["tab", @mode == :visual && "tab-active"]}
            phx-click="switch_mode"
            phx-value-mode="visual"
            phx-target={@myself}
          >
            <.icon name="hero-squares-2x2" class="h-4 w-4 mr-1" /> Visual
          </button>
          <button
            type="button"
            class={["tab", @mode == :text && "tab-active"]}
            phx-click="switch_mode"
            phx-value-mode="text"
            phx-target={@myself}
          >
            <.icon name="hero-code-bracket" class="h-4 w-4 mr-1" /> JSON
          </button>
        </div>

        <%= if @mode == :visual do %>
          <button
            type="button"
            class="btn btn-primary btn-sm"
            phx-click="add_step"
            phx-target={@myself}
          >
            <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Step
          </button>
        <% end %>
      </div>
      
    <!-- Validation Errors -->
      <%= if @validation_errors != [] do %>
        <div class="alert alert-error mb-4">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <div>
            <h3 class="font-bold">Validation Errors</h3>
            <ul class="list-disc list-inside text-sm">
              <li :for={error <- @validation_errors}>{error}</li>
            </ul>
          </div>
        </div>
      <% end %>

      <%= if @mode == :visual do %>
        <.visual_editor
          steps={@steps}
          selected_step={@selected_step}
          editing_step={@editing_step}
          myself={@myself}
        />
      <% else %>
        <.text_editor source={@text_source} myself={@myself} />
      <% end %>
    </div>
    """
  end

  attr :steps, :map, required: true
  attr :selected_step, :string
  attr :editing_step, :string
  attr :myself, :any, required: true

  defp visual_editor(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if map_size(@steps) == 0 do %>
        <div class="text-center py-12 bg-base-200 rounded-lg">
          <.icon name="hero-cube-transparent" class="h-12 w-12 mx-auto text-base-content/30" />
          <p class="mt-4 text-base-content/60">No steps defined yet</p>
          <p class="text-sm text-base-content/40">Click "Add Step" to get started</p>
        </div>
      <% else %>
        <div class="grid gap-3">
          <%= for {step_name, step} <- Enum.sort(@steps) do %>
            <div class={[
              "p-4 rounded-lg border-2 transition-colors",
              @selected_step == step_name && "border-primary bg-primary/5",
              @selected_step != step_name &&
                "border-base-300 bg-base-100 hover:border-base-content/30"
            ]}>
              <div class="flex items-start justify-between">
                <div
                  class="flex-1 cursor-pointer"
                  phx-click="select_step"
                  phx-value-step={step_name}
                  phx-target={@myself}
                >
                  <div class="flex items-center gap-2">
                    <span class="font-medium">{step_name}</span>
                    <span class="badge badge-sm badge-ghost">{step["type"]}</span>
                  </div>

                  <%= if step["depends_on"] && length(step["depends_on"]) > 0 do %>
                    <div class="mt-1 text-xs text-base-content/60">
                      Depends on: {Enum.join(step["depends_on"], ", ")}
                    </div>
                  <% end %>

                  <div class="mt-2 text-sm text-base-content/70">
                    <.step_summary step={step} />
                  </div>
                </div>

                <div class="flex items-center gap-1">
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="edit_step"
                    phx-value-step={step_name}
                    phx-target={@myself}
                  >
                    <.icon name="hero-pencil" class="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="delete_step"
                    phx-value-step={step_name}
                    phx-target={@myself}
                    data-confirm="Are you sure you want to delete this step?"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
      
    <!-- Step Editor Modal -->
      <%= if @editing_step do %>
        <.step_editor_modal
          step_name={@editing_step}
          step={Map.get(@steps, @editing_step, %{})}
          all_steps={@steps}
          myself={@myself}
        />
      <% end %>
    </div>
    """
  end

  attr :step, :map, required: true

  defp step_summary(assigns) do
    ~H"""
    <%= case @step["type"] do %>
      <% "check" -> %>
        <span>Check: <code class="text-xs bg-base-200 px-1 rounded">{@step["condition"]}</code></span>
      <% "command" -> %>
        <span>Command: <code class="font-mono">{@step["name"]}</code></span>
      <% "wait" -> %>
        <span>Wait {@step["duration"] || 0}ms</span>
      <% "wait_for" -> %>
        <span>
          Wait for <code class="text-xs">{@step["item"]} {@step["operator"]} {@step["value"]}</code>
        </span>
      <% "log" -> %>
        <span>{@step["level"] || "info"}: "{@step["message"]}"</span>
      <% "set" -> %>
        <span>Set {@step["name"]} = <code class="text-xs">{inspect(@step["value"])}</code></span>
      <% "assert" -> %>
        <span>
          Assert: <code class="text-xs bg-base-200 px-1 rounded">{@step["condition"]}</code>
        </span>
      <% _ -> %>
        <span>Unknown step type</span>
    <% end %>
    """
  end

  attr :step_name, :string, required: true
  attr :step, :map, required: true
  attr :all_steps, :map, required: true
  attr :myself, :any, required: true

  defp step_editor_modal(assigns) do
    available_deps = available_dependencies(assigns.all_steps, assigns.step_name)
    current_deps = assigns.step["depends_on"] || []
    assigns = assign(assigns, :available_deps, available_deps)
    assigns = assign(assigns, :current_deps, current_deps)

    ~H"""
    <div
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      id="step-editor-backdrop"
      phx-window-keydown="cancel_edit"
      phx-key="Escape"
      phx-target={@myself}
    >
      <div class="bg-base-100 rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-auto">
        <div class="p-6">
          <h3 class="text-lg font-bold mb-4">Edit Step</h3>

          <form
            phx-submit="save_step"
            phx-change="step_form_change"
            phx-target={@myself}
            class="space-y-4"
            onchange="event.stopPropagation()"
            oninput="event.stopPropagation()"
          >
            <!-- Step Name -->
            <div>
              <label class="label"><span class="label-text">Step Name</span></label>
              <input
                type="text"
                name="step[name]"
                value={@step_name}
                class="input input-bordered w-full"
                required
              />
            </div>
            
    <!-- Step Type -->
            <div>
              <label class="label"><span class="label-text">Type</span></label>
              <select name="step[type]" class="select select-bordered w-full" id="step-type-select">
                <%= for {type, description} <- step_types() do %>
                  <option value={type} selected={@step["type"] == type} title={description}>
                    {type}
                  </option>
                <% end %>
              </select>
            </div>
            
    <!-- Type-specific fields -->
            <.step_type_fields step={@step} />
            
    <!-- Dependencies -->
            <div>
              <label class="label"><span class="label-text">Depends On</span></label>
              <%= if @available_deps == [] do %>
                <p class="text-sm text-base-content/50">No other steps available</p>
              <% else %>
                <div class="flex flex-wrap gap-2">
                  <%= for dep <- @available_deps do %>
                    <label class="flex items-center gap-1 cursor-pointer">
                      <input
                        type="checkbox"
                        name="step[depends_on]"
                        value={dep}
                        checked={dep in @current_deps}
                        class="checkbox checkbox-sm"
                      />
                      <span class="text-sm">{dep}</span>
                    </label>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="flex justify-end gap-2 pt-4">
              <button
                type="button"
                class="btn btn-ghost"
                phx-click="cancel_edit"
                phx-target={@myself}
              >
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">
                Save Step
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  attr :step, :map, required: true

  defp step_type_fields(assigns) do
    ~H"""
    <div class="space-y-4 p-4 bg-base-200 rounded-lg">
      <%= case @step["type"] do %>
        <% "check" -> %>
          <div>
            <label class="label"><span class="label-text">Condition</span></label>
            <input
              type="text"
              name="step[condition]"
              value={@step["condition"]}
              class="input input-bordered w-full font-mono"
              placeholder="telemetry.PACKET.item >= 10"
            />
          </div>
          <div>
            <label class="label"><span class="label-text">Failure Message</span></label>
            <input
              type="text"
              name="step[message]"
              value={@step["message"]}
              class="input input-bordered w-full"
            />
          </div>
          <div>
            <label class="label"><span class="label-text">On Failure</span></label>
            <select name="step[on_fail]" class="select select-bordered w-full">
              <option value="abort" selected={@step["on_fail"] == "abort"}>Abort</option>
              <option value="skip" selected={@step["on_fail"] == "skip"}>Skip</option>
              <option value="warn" selected={@step["on_fail"] == "warn"}>Warn and continue</option>
            </select>
          </div>
        <% "command" -> %>
          <div>
            <label class="label"><span class="label-text">Command Name</span></label>
            <input
              type="text"
              name="step[command_name]"
              value={@step["name"]}
              class="input input-bordered w-full font-mono"
              placeholder="ENABLE_HEATER"
            />
          </div>
          <div>
            <label class="label"><span class="label-text">Arguments (JSON)</span></label>
            <textarea
              name="step[args]"
              class="textarea textarea-bordered w-full font-mono"
              placeholder='{"zone": "PRIMARY"}'
              rows="2"
            >{if @step["args"], do: Jason.encode!(@step["args"]), else: ""}</textarea>
          </div>
        <% "wait" -> %>
          <div>
            <label class="label"><span class="label-text">Duration (ms)</span></label>
            <input
              type="number"
              name="step[duration]"
              value={@step["duration"] || 1000}
              class="input input-bordered w-full"
              min="0"
            />
          </div>
        <% "wait_for" -> %>
          <div>
            <label class="label"><span class="label-text">Telemetry Item</span></label>
            <input
              type="text"
              name="step[item]"
              value={@step["item"]}
              class="input input-bordered w-full font-mono"
              placeholder="EPS.battery_voltage"
            />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="label"><span class="label-text">Operator</span></label>
              <select name="step[operator]" class="select select-bordered w-full">
                <option value="==" selected={@step["operator"] == "=="}>==</option>
                <option value="!=" selected={@step["operator"] == "!="}>!=</option>
                <option value=">" selected={@step["operator"] == ">"}>&gt;</option>
                <option value=">=" selected={@step["operator"] == ">="}>&gt;=</option>
                <option value="<" selected={@step["operator"] == "<"}>&lt;</option>
                <option value="<=" selected={@step["operator"] == "<="}>&lt;=</option>
              </select>
            </div>
            <div>
              <label class="label"><span class="label-text">Value</span></label>
              <input
                type="text"
                name="step[value]"
                value={@step["value"]}
                class="input input-bordered w-full"
              />
            </div>
          </div>
          <div>
            <label class="label"><span class="label-text">Timeout (ms)</span></label>
            <input
              type="number"
              name="step[timeout]"
              value={@step["timeout"] || 30000}
              class="input input-bordered w-full"
              min="0"
            />
          </div>
        <% "log" -> %>
          <div>
            <label class="label"><span class="label-text">Level</span></label>
            <select name="step[level]" class="select select-bordered w-full">
              <option value="debug" selected={@step["level"] == "debug"}>Debug</option>
              <option value="info" selected={@step["level"] == "info" or is_nil(@step["level"])}>
                Info
              </option>
              <option value="warn" selected={@step["level"] == "warn"}>Warning</option>
              <option value="error" selected={@step["level"] == "error"}>Error</option>
            </select>
          </div>
          <div>
            <label class="label"><span class="label-text">Message</span></label>
            <input
              type="text"
              name="step[message]"
              value={@step["message"]}
              class="input input-bordered w-full"
              placeholder="Starting procedure..."
            />
          </div>
        <% "set" -> %>
          <div>
            <label class="label"><span class="label-text">Variable Name</span></label>
            <input
              type="text"
              name="step[var_name]"
              value={@step["name"]}
              class="input input-bordered w-full"
              placeholder="result"
            />
          </div>
          <div>
            <label class="label"><span class="label-text">Value</span></label>
            <input
              type="text"
              name="step[value]"
              value={@step["value"]}
              class="input input-bordered w-full"
              placeholder="telemetry.PACKET.item"
            />
          </div>
        <% "assert" -> %>
          <div>
            <label class="label"><span class="label-text">Condition</span></label>
            <input
              type="text"
              name="step[condition]"
              value={@step["condition"]}
              class="input input-bordered w-full font-mono"
              placeholder="params.threshold > 0"
            />
          </div>
          <div>
            <label class="label"><span class="label-text">Failure Message</span></label>
            <input
              type="text"
              name="step[message]"
              value={@step["message"]}
              class="input input-bordered w-full"
              placeholder="Threshold must be positive"
            />
          </div>
        <% _ -> %>
          <p class="text-base-content/50">Unknown step type</p>
      <% end %>
    </div>
    """
  end

  attr :source, :string, required: true
  attr :myself, :any, required: true

  defp text_editor(assigns) do
    ~H"""
    <div class="space-y-4">
      <textarea
        class="textarea textarea-bordered w-full font-mono text-sm"
        rows="20"
        phx-change="update_text"
        phx-target={@myself}
        name="source"
      >{@source}</textarea>

      <div class="flex justify-end">
        <button type="button" class="btn btn-primary" phx-click="apply_text" phx-target={@myself}>
          Apply Changes
        </button>
      </div>
    </div>
    """
  end
end
