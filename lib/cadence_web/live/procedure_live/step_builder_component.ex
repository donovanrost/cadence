defmodule CadenceWeb.ProcedureLive.StepBuilderComponent do
  @moduledoc """
  Visual step builder for DAG procedures.

  Provides a form-based interface for creating and editing procedure steps,
  with support for log, wait, command, and check step types.

  Note: This component is being transitioned to support DAG-based procedures.
  Steps are validated inline rather than through the removed Sequences module.
  """
  use CadenceWeb, :live_component

  @step_types [
    {"Log", "log", "hero-chat-bubble-left"},
    {"Wait", "wait", "hero-clock"},
    {"Command", "command", "hero-paper-airplane"},
    {"Check", "check", "hero-check-circle"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:steps, [])
     |> assign(:expanded_step, nil)
     |> assign(:editing_mode, :visual)
     |> assign(:raw_json, "")
     |> assign(:validation_errors, %{})}
  end

  @impl true
  def update(%{source_json: json} = assigns, socket) do
    steps = parse_steps_with_ids(json)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:steps, steps)
     |> assign(:raw_json, format_json(steps))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="step-builder">
      <div class="flex justify-between items-center mb-4">
        <label class="block text-sm font-medium">Procedure Steps</label>
        <button
          type="button"
          phx-click="toggle_mode"
          phx-target={@myself}
          class="btn btn-ghost btn-sm gap-1"
        >
          <%= if @editing_mode == :visual do %>
            <.icon name="hero-code-bracket" class="size-4" /> Raw JSON
          <% else %>
            <.icon name="hero-squares-2x2" class="size-4" /> Visual Builder
          <% end %>
        </button>
      </div>

      <%= if @editing_mode == :visual do %>
        <.visual_builder
          steps={@steps}
          expanded_step={@expanded_step}
          validation_errors={@validation_errors}
          myself={@myself}
        />
      <% else %>
        <.raw_json_editor raw_json={@raw_json} myself={@myself} />
      <% end %>
      
    <!-- Hidden input to store serialized steps for form submission -->
      <input type="hidden" name="source_json" value={serialize_steps(@steps)} />
    </div>
    """
  end

  defp visual_builder(assigns) do
    ~H"""
    <div class="space-y-2">
      <%= if Enum.empty?(@steps) do %>
        <div class="text-center py-8 text-base-content/50 border-2 border-dashed border-base-300 rounded-lg">
          <.icon name="hero-document-plus" class="size-8 mx-auto mb-2" />
          <p>No steps yet. Add a step to get started.</p>
        </div>
      <% else %>
        <div id="step-list" phx-hook="Sortable" class="space-y-2">
          <%= for {step, index} <- Enum.with_index(@steps) do %>
            <.step_card
              step={step}
              index={index}
              is_expanded={@expanded_step == step["id"]}
              errors={Map.get(@validation_errors, step["id"], [])}
              myself={@myself}
            />
          <% end %>
        </div>
      <% end %>
      
    <!-- Add Step Dropdown -->
      <div class="dropdown dropdown-top">
        <div tabindex="0" role="button" class="btn btn-outline btn-sm gap-1">
          <.icon name="hero-plus" class="size-4" /> Add Step
        </div>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52 mb-1"
        >
          <%= for {label, type, icon} <- step_types() do %>
            <li>
              <a phx-click="add_step" phx-value-type={type} phx-target={@myself}>
                <.icon name={icon} class="size-4" />
                {label}
              </a>
            </li>
          <% end %>
        </ul>
      </div>
    </div>
    """
  end

  defp step_card(assigns) do
    ~H"""
    <div
      class={[
        "border rounded-lg transition-all",
        @is_expanded && "border-primary bg-base-200",
        !@is_expanded && "border-base-300 bg-base-100",
        @errors != [] && "border-error"
      ]}
      draggable="true"
      data-sortable-id={@step["id"]}
    >
      <!-- Step Header -->
      <div class="flex items-center justify-between p-3">
        <!-- Drag Handle -->
        <div class="flex items-center gap-2 cursor-grab active:cursor-grabbing">
          <.icon name="hero-bars-3" class="size-4 text-base-content/40" />
          <span class="badge badge-sm badge-neutral">{@index + 1}</span>
          <.step_type_icon type={@step["type"]} />
          <span
            class="font-medium cursor-pointer"
            phx-click="toggle_expand"
            phx-value-id={@step["id"]}
            phx-target={@myself}
          >
            {step_summary(@step)}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="remove_step"
            phx-value-id={@step["id"]}
            phx-target={@myself}
            class="btn btn-ghost btn-xs text-error"
          >
            <.icon name="hero-trash" class="size-3" />
          </button>
          <button
            type="button"
            phx-click="toggle_expand"
            phx-value-id={@step["id"]}
            phx-target={@myself}
            class="btn btn-ghost btn-xs"
          >
            <.icon
              name={if @is_expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="size-4"
            />
          </button>
        </div>
      </div>
      
    <!-- Step Form (expanded) -->
      <div :if={@is_expanded} class="p-4 pt-0 border-t border-base-300">
        <.step_form step={@step} myself={@myself} />
        <%= if @errors != [] do %>
          <div class="mt-2 text-error text-sm">
            <p :for={error <- @errors}>{error}</p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{"type" => "log"}} = assigns) do
    ~H"""
    <div class="space-y-3 pt-3">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Level</span>
        </label>
        <select
          class="select select-bordered select-sm w-full"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="level"
        >
          <option value="debug" selected={@step["level"] == "debug"}>Debug</option>
          <option value="info" selected={@step["level"] == "info"}>Info</option>
          <option value="warn" selected={@step["level"] == "warn"}>Warning</option>
          <option value="error" selected={@step["level"] == "error"}>Error</option>
        </select>
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text">Message</span>
        </label>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          value={@step["message"]}
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="message"
          phx-debounce="300"
        />
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{"type" => "wait"}} = assigns) do
    ~H"""
    <div class="space-y-3 pt-3">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Duration (milliseconds)</span>
        </label>
        <input
          type="number"
          class="input input-bordered input-sm w-full"
          value={@step["duration"]}
          min="0"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="duration"
          phx-debounce="300"
        />
        <label class="label">
          <span class="label-text-alt text-base-content/50">
            {format_duration(@step["duration"])}
          </span>
        </label>
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{"type" => "check"}} = assigns) do
    ~H"""
    <div class="space-y-3 pt-3">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Condition</span>
        </label>
        <input
          type="text"
          class="input input-bordered input-sm w-full font-mono"
          value={@step["condition"]}
          placeholder="telemetry.POWER.voltage >= 24"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="condition"
          phx-debounce="300"
        />
        <label class="label">
          <span class="label-text-alt text-base-content/50">
            Lua expression that evaluates to true or false
          </span>
        </label>
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text">On Failure</span>
        </label>
        <select
          class="select select-bordered select-sm w-full"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="on_fail"
        >
          <option value="abort" selected={@step["on_fail"] == "abort"}>Abort procedure</option>
          <option value="skip" selected={@step["on_fail"] == "skip"}>Skip and continue</option>
          <option value="warn" selected={@step["on_fail"] == "warn"}>Log warning and continue</option>
        </select>
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text">Message (optional)</span>
        </label>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          value={@step["message"] || ""}
          placeholder="Failure message"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="message"
          phx-debounce="300"
        />
      </div>
    </div>
    """
  end

  defp step_form(%{step: %{"type" => "command"}} = assigns) do
    args = assigns.step["args"] || %{}
    args_list = Enum.map(args, fn {k, v} -> %{"key" => k, "value" => v} end)

    assigns = assign(assigns, :args_list, args_list)

    ~H"""
    <div class="space-y-3 pt-3">
      <div class="form-control">
        <label class="label">
          <span class="label-text">Command Name</span>
        </label>
        <input
          type="text"
          class="input input-bordered input-sm w-full font-mono"
          value={@step["name"]}
          placeholder="HEATER_ON"
          phx-change="update_step"
          phx-target={@myself}
          name="value"
          phx-value-id={@step["id"]}
          phx-value-field="name"
          phx-debounce="300"
        />
      </div>
      <div class="form-control">
        <label class="label">
          <span class="label-text">Arguments</span>
        </label>
        <div class="space-y-2">
          <%= for {arg, arg_index} <- Enum.with_index(@args_list) do %>
            <div class="flex gap-2 items-center">
              <input
                type="text"
                class="input input-bordered input-sm flex-1 font-mono"
                value={arg["key"]}
                placeholder="key"
                phx-change="update_arg"
                phx-target={@myself}
                name="value"
                phx-value-step-id={@step["id"]}
                phx-value-arg-index={arg_index}
                phx-value-field="key"
                phx-debounce="300"
              />
              <span class="text-base-content/50">=</span>
              <input
                type="text"
                class="input input-bordered input-sm flex-1 font-mono"
                value={arg["value"]}
                placeholder="value"
                phx-change="update_arg"
                phx-target={@myself}
                name="value"
                phx-value-step-id={@step["id"]}
                phx-value-arg-index={arg_index}
                phx-value-field="value"
                phx-debounce="300"
              />
              <button
                type="button"
                class="btn btn-ghost btn-xs text-error"
                phx-click="remove_arg"
                phx-value-step-id={@step["id"]}
                phx-value-arg-index={arg_index}
                phx-target={@myself}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </div>
          <% end %>
          <button
            type="button"
            class="btn btn-ghost btn-xs gap-1"
            phx-click="add_arg"
            phx-value-step-id={@step["id"]}
            phx-target={@myself}
          >
            <.icon name="hero-plus" class="size-3" /> Add argument
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp step_form(assigns) do
    ~H"""
    <div class="pt-3 text-base-content/50">
      Unknown step type: {@step["type"]}
    </div>
    """
  end

  defp raw_json_editor(assigns) do
    ~H"""
    <div>
      <textarea
        class="textarea textarea-bordered w-full font-mono text-sm"
        rows={12}
        phx-change="update_raw_json"
        phx-target={@myself}
        name="value"
        phx-debounce="blur"
      >{@raw_json}</textarea>
      <p class="text-xs text-base-content/50 mt-1">
        Enter steps as a JSON array. Each step requires a "type" field.
      </p>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("add_step", %{"type" => type}, socket) do
    new_step = default_step(type)
    steps = socket.assigns.steps ++ [new_step]

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> assign(:expanded_step, new_step["id"])
     |> validate_steps()}
  end

  def handle_event("remove_step", %{"id" => id}, socket) do
    steps = Enum.reject(socket.assigns.steps, &(&1["id"] == id))

    expanded =
      if socket.assigns.expanded_step == id do
        nil
      else
        socket.assigns.expanded_step
      end

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> assign(:expanded_step, expanded)
     |> validate_steps()}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded =
      if socket.assigns.expanded_step == id do
        nil
      else
        id
      end

    {:noreply, assign(socket, :expanded_step, expanded)}
  end

  def handle_event("update_step", %{"id" => id, "field" => field, "value" => value}, socket) do
    value = coerce_value(field, value)

    steps =
      Enum.map(socket.assigns.steps, fn step ->
        if step["id"] == id do
          Map.put(step, field, value)
        else
          step
        end
      end)

    {:noreply,
     socket
     |> assign(:steps, steps)
     |> validate_steps()}
  end

  def handle_event("add_arg", %{"step-id" => step_id}, socket) do
    steps =
      Enum.map(socket.assigns.steps, fn step ->
        if step["id"] == step_id do
          args = step["args"] || %{}
          # Generate a unique key name
          new_key = "arg#{map_size(args) + 1}"
          Map.put(step, "args", Map.put(args, new_key, ""))
        else
          step
        end
      end)

    {:noreply, assign(socket, :steps, steps)}
  end

  def handle_event(
        "remove_arg",
        %{"step-id" => step_id, "arg-index" => arg_index_str},
        socket
      ) do
    arg_index = String.to_integer(arg_index_str)

    steps =
      Enum.map(socket.assigns.steps, fn step ->
        if step["id"] == step_id do
          args = step["args"] || %{}
          args_list = Enum.to_list(args)

          new_args =
            args_list
            |> List.delete_at(arg_index)
            |> Map.new()

          Map.put(step, "args", new_args)
        else
          step
        end
      end)

    {:noreply, assign(socket, :steps, steps)}
  end

  def handle_event(
        "update_arg",
        %{
          "step-id" => step_id,
          "arg-index" => arg_index_str,
          "field" => field,
          "value" => value
        },
        socket
      ) do
    arg_index = String.to_integer(arg_index_str)

    steps =
      Enum.map(socket.assigns.steps, fn step ->
        if step["id"] == step_id do
          args = step["args"] || %{}
          args_list = Enum.to_list(args)

          {old_key, old_value} = Enum.at(args_list, arg_index, {"", ""})

          {new_key, new_value} =
            case field do
              "key" -> {value, old_value}
              "value" -> {old_key, value}
            end

          new_args =
            args_list
            |> List.delete_at(arg_index)
            |> List.insert_at(arg_index, {new_key, new_value})
            |> Map.new()

          Map.put(step, "args", new_args)
        else
          step
        end
      end)

    {:noreply, assign(socket, :steps, steps)}
  end

  def handle_event("toggle_mode", _, socket) do
    new_mode =
      case socket.assigns.editing_mode do
        :visual -> :raw
        :raw -> :visual
      end

    socket =
      case new_mode do
        :raw ->
          # Switching to raw: serialize current steps
          assign(socket, :raw_json, format_json(socket.assigns.steps))

        :visual ->
          # Switching to visual: parse raw JSON
          case Jason.decode(socket.assigns.raw_json) do
            {:ok, steps} when is_list(steps) ->
              steps_with_ids = Enum.map(steps, &ensure_id/1)
              assign(socket, :steps, steps_with_ids)

            _ ->
              # Invalid JSON, keep raw mode
              socket
              |> put_flash(:error, "Invalid JSON. Fix errors before switching to visual mode.")
          end
      end

    {:noreply, assign(socket, :editing_mode, new_mode)}
  end

  def handle_event("update_raw_json", %{"value" => value}, socket) do
    {:noreply, assign(socket, :raw_json, value)}
  end

  # Helper Functions

  defp step_types, do: @step_types

  defp parse_steps_with_ids(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, steps} when is_list(steps) ->
        Enum.map(steps, &ensure_id/1)

      _ ->
        []
    end
  end

  defp parse_steps_with_ids(_), do: []

  defp ensure_id(step) when is_map(step) do
    if Map.has_key?(step, "id") do
      step
    else
      Map.put(step, "id", generate_step_id())
    end
  end

  defp generate_step_id do
    "step_#{:erlang.unique_integer([:positive])}"
  end

  defp serialize_steps(steps) do
    # Remove the temporary IDs before serializing
    steps
    |> Enum.map(&Map.delete(&1, "id"))
    |> Jason.encode!(pretty: true)
  end

  defp format_json(steps) do
    steps
    |> Enum.map(&Map.delete(&1, "id"))
    |> Jason.encode!(pretty: true)
  end

  defp default_step("log") do
    %{
      "id" => generate_step_id(),
      "type" => "log",
      "level" => "info",
      "message" => ""
    }
  end

  defp default_step("wait") do
    %{
      "id" => generate_step_id(),
      "type" => "wait",
      "duration" => 1000
    }
  end

  defp default_step("check") do
    %{
      "id" => generate_step_id(),
      "type" => "check",
      "condition" => "",
      "on_fail" => "abort",
      "message" => ""
    }
  end

  defp default_step("command") do
    %{
      "id" => generate_step_id(),
      "type" => "command",
      "name" => "",
      "args" => %{}
    }
  end

  defp default_step(_type) do
    %{
      "id" => generate_step_id(),
      "type" => "log",
      "level" => "info",
      "message" => ""
    }
  end

  defp step_summary(%{"type" => "log", "message" => msg}) when byte_size(msg) > 0 do
    "Log: #{String.slice(msg, 0, 40)}#{if String.length(msg) > 40, do: "...", else: ""}"
  end

  defp step_summary(%{"type" => "log"}), do: "Log message"

  defp step_summary(%{"type" => "wait", "duration" => duration}) do
    "Wait #{format_duration(duration)}"
  end

  defp step_summary(%{"type" => "check", "condition" => cond}) when byte_size(cond) > 0 do
    "Check: #{String.slice(cond, 0, 30)}#{if String.length(cond) > 30, do: "...", else: ""}"
  end

  defp step_summary(%{"type" => "check"}), do: "Check condition"

  defp step_summary(%{"type" => "command", "name" => name}) when byte_size(name) > 0 do
    "Command: #{name}"
  end

  defp step_summary(%{"type" => "command"}), do: "Send command"
  defp step_summary(%{"type" => type}), do: String.capitalize(type)

  defp step_type_icon(%{type: "log"} = assigns) do
    ~H"""
    <.icon name="hero-chat-bubble-left" class="size-4 text-info" />
    """
  end

  defp step_type_icon(%{type: "wait"} = assigns) do
    ~H"""
    <.icon name="hero-clock" class="size-4 text-warning" />
    """
  end

  defp step_type_icon(%{type: "command"} = assigns) do
    ~H"""
    <.icon name="hero-paper-airplane" class="size-4 text-success" />
    """
  end

  defp step_type_icon(%{type: "check"} = assigns) do
    ~H"""
    <.icon name="hero-check-circle" class="size-4 text-secondary" />
    """
  end

  defp step_type_icon(assigns) do
    ~H"""
    <.icon name="hero-cube" class="size-4" />
    """
  end

  defp format_duration(nil), do: "1 second"
  defp format_duration(ms) when is_binary(ms), do: format_duration(String.to_integer(ms))
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 1)} seconds"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)} minutes"

  defp coerce_value("duration", value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 1000
    end
  end

  defp coerce_value(_, value), do: value

  defp validate_steps(socket) do
    errors =
      socket.assigns.steps
      |> Enum.map(fn step ->
        step_without_id = Map.delete(step, "id")

        case validate_step(step_without_id) do
          :ok -> {step["id"], []}
          {:error, reason} -> {step["id"], [reason]}
        end
      end)
      |> Enum.reject(fn {_id, errors} -> errors == [] end)
      |> Map.new()

    assign(socket, :validation_errors, errors)
  end

  # Inline step validation (previously in Sequences.Step module)
  defp validate_step(%{"type" => "log", "message" => msg}) when is_binary(msg) and msg != "" do
    :ok
  end

  defp validate_step(%{"type" => "log"}) do
    {:error, "Log step requires a non-empty message"}
  end

  defp validate_step(%{"type" => "wait", "duration" => duration})
       when is_integer(duration) and duration > 0 do
    :ok
  end

  defp validate_step(%{"type" => "wait"}) do
    {:error, "Wait step requires a positive duration in milliseconds"}
  end

  defp validate_step(%{"type" => "command", "name" => name})
       when is_binary(name) and name != "" do
    :ok
  end

  defp validate_step(%{"type" => "command"}) do
    {:error, "Command step requires a non-empty name"}
  end

  defp validate_step(%{"type" => "check", "condition" => cond})
       when is_binary(cond) and cond != "" do
    :ok
  end

  defp validate_step(%{"type" => "check"}) do
    {:error, "Check step requires a non-empty condition"}
  end

  defp validate_step(%{"type" => type}) when is_binary(type) do
    {:error, "Unknown step type: #{type}"}
  end

  defp validate_step(_) do
    {:error, "Step requires a type field"}
  end
end
