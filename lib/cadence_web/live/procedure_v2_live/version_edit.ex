defmodule CadenceWeb.ProcedureV2Live.VersionEdit do
  @moduledoc """
  LiveView for editing procedure versions using the V2 block-based editor.

  Provides a document-centric two-column layout:
  - Left: Navigation sidebar (settings, sections, steps)
  - Center: Full procedure document (settings section + all sections/steps/blocks)

  The layout mirrors the execution view for consistency.
  """
  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.V2

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

  defp apply_action(socket, :edit_version, %{
         "procedure_id" => procedure_id,
         "version_id" => version_id
       }) do
    procedure = Procedures.get_procedure!(procedure_id)
    version = Procedures.get_version!(version_id)
    sections = V2.list_sections_with_steps(version_id)

    parameter_types =
      ~w(string number integer boolean enum target telemetry_item command duration datetime array)

    socket
    |> assign(:page_title, "Edit: #{procedure.name} (v#{version.version_number})")
    |> assign(:procedure, procedure)
    |> assign(:version, version)
    |> assign(:sections, sections)
    |> assign(:collapsed_section_ids, MapSet.new())
    |> assign(:settings_expanded, true)
    |> assign(:editing_section_id, nil)
    |> assign(:editing_step_id, nil)
    |> assign(:editing_block_id, nil)
    |> assign(:show_block_palette_for_step, nil)
    |> assign(:editing_parameter_index, nil)
    |> assign(:adding_parameter, false)
    |> assign(:parameter_types, parameter_types)
  end

  # ────────────────────────────────────────────────────────────────────
  # Event Handlers - Settings/Parameters
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    {:noreply, assign(socket, :settings_expanded, !socket.assigns.settings_expanded)}
  end

  def handle_event("add_parameter", _params, socket) do
    {:noreply, assign(socket, :adding_parameter, true)}
  end

  def handle_event("cancel_add_parameter", _params, socket) do
    {:noreply, assign(socket, :adding_parameter, false)}
  end

  def handle_event("save_new_parameter", params, socket) do
    version = socket.assigns.version
    current_params = get_parameters(version)

    new_param = %{
      "name" => params["name"] || "",
      "type" => params["type"] || "string",
      "required" => params["required"] == "true",
      "description" => params["description"] || ""
    }

    # Add type-specific fields
    new_param = add_type_specific_fields(new_param, params)

    new_params = current_params ++ [new_param]

    case update_parameters_schema(version, new_params) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> assign(:version, updated_version)
         |> assign(:adding_parameter, false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add parameter")}
    end
  end

  def handle_event("edit_parameter", %{"index" => index}, socket) do
    {:noreply, assign(socket, :editing_parameter_index, String.to_integer(index))}
  end

  def handle_event("cancel_edit_parameter", _params, socket) do
    {:noreply, assign(socket, :editing_parameter_index, nil)}
  end

  def handle_event("save_parameter", %{"index" => index} = params, socket) do
    version = socket.assigns.version
    current_params = get_parameters(version)
    idx = String.to_integer(index)

    updated_param = %{
      "name" => params["name"] || "",
      "type" => params["type"] || "string",
      "required" => params["required"] == "true",
      "description" => params["description"] || ""
    }

    # Add type-specific fields
    updated_param = add_type_specific_fields(updated_param, params)

    new_params = List.replace_at(current_params, idx, updated_param)

    case update_parameters_schema(version, new_params) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> assign(:version, updated_version)
         |> assign(:editing_parameter_index, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save parameter")}
    end
  end

  def handle_event("delete_parameter", %{"index" => index}, socket) do
    version = socket.assigns.version
    current_params = get_parameters(version)
    idx = String.to_integer(index)

    new_params = List.delete_at(current_params, idx)

    case update_parameters_schema(version, new_params) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> assign(:version, updated_version)
         |> assign(:editing_parameter_index, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete parameter")}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Event Handlers - Sections
  # ────────────────────────────────────────────────────────────────────

  def handle_event("toggle_section_collapsed", %{"id" => section_id}, socket) do
    collapsed = socket.assigns.collapsed_section_ids

    new_collapsed =
      if MapSet.member?(collapsed, section_id) do
        MapSet.delete(collapsed, section_id)
      else
        MapSet.put(collapsed, section_id)
      end

    {:noreply, assign(socket, :collapsed_section_ids, new_collapsed)}
  end

  def handle_event("scroll_to_section", %{"id" => section_id}, socket) do
    {:noreply, push_event(socket, "scroll-to", %{id: "section-#{section_id}"})}
  end

  def handle_event("add_section", _params, socket) do
    version_id = socket.assigns.version.id
    position = length(socket.assigns.sections)

    case V2.create_section(version_id, %{name: "New Section", position: position}) do
      {:ok, section} ->
        sections = V2.list_sections_with_steps(version_id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:editing_section_id, section.id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create section")}
    end
  end

  def handle_event("edit_section", %{"id" => section_id}, socket) do
    {:noreply, assign(socket, :editing_section_id, section_id)}
  end

  def handle_event("save_section_name", %{"id" => section_id, "name" => name}, socket) do
    section = V2.get_section!(section_id)

    case V2.update_section(section, %{name: name}) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:editing_section_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update section name")}
    end
  end

  def handle_event("cancel_edit_section", _params, socket) do
    {:noreply, assign(socket, :editing_section_id, nil)}
  end

  def handle_event("delete_section", %{"id" => section_id}, socket) do
    section = V2.get_section!(section_id)

    case V2.delete_section(section) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> put_flash(:info, "Section deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete section")}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Event Handlers - Steps
  # ────────────────────────────────────────────────────────────────────

  def handle_event("scroll_to_step", %{"id" => step_id}, socket) do
    {:noreply, push_event(socket, "scroll-to", %{id: "step-#{step_id}"})}
  end

  def handle_event("add_step", %{"section_id" => section_id}, socket) do
    steps = V2.list_steps(section_id)
    position = length(steps)

    case V2.create_step(section_id, %{name: "new_step_#{position + 1}", position: position}) do
      {:ok, _step} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)
        {:noreply, assign(socket, :sections, sections)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to create step")}
    end
  end

  def handle_event("edit_step", %{"id" => step_id}, socket) do
    {:noreply, assign(socket, :editing_step_id, step_id)}
  end

  def handle_event("cancel_edit_step", _params, socket) do
    {:noreply, assign(socket, :editing_step_id, nil)}
  end

  def handle_event("save_step", %{"step_id" => step_id} = params, socket) do
    step = V2.get_step!(step_id)

    attrs = %{
      name: params["name"] || step.name,
      title: params["title"],
      requires_signoff: params["requires_signoff"] == "true",
      on_fail: String.to_existing_atom(params["on_fail"] || "pause"),
      required_roles: parse_roles(params["required_roles"])
    }

    case V2.update_step(step, attrs) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:editing_step_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update step")}
    end
  end

  def handle_event("delete_step", %{"id" => step_id}, socket) do
    step = V2.get_step!(step_id)

    case V2.delete_step(step) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> put_flash(:info, "Step deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete step")}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Event Handlers - Blocks
  # ────────────────────────────────────────────────────────────────────

  def handle_event("toggle_block_palette", %{"step_id" => step_id}, socket) do
    current = socket.assigns.show_block_palette_for_step

    new_value = if current == step_id, do: nil, else: step_id
    {:noreply, assign(socket, :show_block_palette_for_step, new_value)}
  end

  def handle_event("add_block", %{"step_id" => step_id, "type" => block_type}, socket) do
    step = V2.get_step_with_blocks!(step_id)
    position = length(step.blocks)
    block_type_atom = String.to_existing_atom(block_type)

    block_attrs = %{
      block_type: block_type_atom,
      position: position,
      content: default_content_for_type(block_type),
      name: default_name_for_block(block_type_atom, position)
    }

    case V2.create_block(step_id, block_attrs) do
      {:ok, block} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:show_block_palette_for_step, nil)
         |> assign(:editing_block_id, block.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add block")}
    end
  end

  def handle_event("delete_block", %{"id" => block_id}, socket) do
    block = V2.get_block!(block_id)

    case V2.delete_block(block) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:editing_block_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete block")}
    end
  end

  def handle_event("edit_block", %{"id" => block_id}, socket) do
    {:noreply, assign(socket, :editing_block_id, block_id)}
  end

  def handle_event("cancel_edit_block", _params, socket) do
    {:noreply, assign(socket, :editing_block_id, nil)}
  end

  def handle_event("save_block", %{"block_id" => block_id} = params, socket) do
    block = V2.get_block!(block_id)
    content = build_content_from_params(block.block_type, params)

    case V2.update_block(block, %{content: content}) do
      {:ok, _} ->
        sections = V2.list_sections_with_steps(socket.assigns.version.id)

        {:noreply,
         socket
         |> assign(:sections, sections)
         |> assign(:editing_block_id, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save block")}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Private Helpers - Parameters
  # ────────────────────────────────────────────────────────────────────

  defp get_parameters(version) do
    case version.parameters_schema do
      %{"parameters" => params} when is_list(params) -> params
      _ -> []
    end
  end

  defp update_parameters_schema(version, params) do
    schema = %{"parameters" => params}

    version
    |> Ecto.Changeset.change(%{parameters_schema: schema})
    |> Cadence.Repo.update()
  end

  defp add_type_specific_fields(%{"type" => "number"} = param, params) do
    param
    |> maybe_add_field("min", params["min"])
    |> maybe_add_field("max", params["max"])
    |> maybe_add_field("default", parse_number(params["default"]))
  end

  defp add_type_specific_fields(%{"type" => "integer"} = param, params) do
    param
    |> maybe_add_field("min", parse_int(params["min"], nil))
    |> maybe_add_field("max", parse_int(params["max"], nil))
    |> maybe_add_field("default", parse_int(params["default"], nil))
  end

  defp add_type_specific_fields(%{"type" => "enum"} = param, params) do
    Map.put(param, "options", enum_options(params["options"]))
  end

  defp add_type_specific_fields(%{"type" => "string"} = param, params) do
    maybe_add_field(param, "default", params["default"])
  end

  defp add_type_specific_fields(%{"type" => "boolean"} = param, params) do
    maybe_add_field(param, "default", params["default"] == "true")
  end

  defp add_type_specific_fields(param, _params), do: param

  defp enum_options(nil), do: []
  defp enum_options(""), do: []
  defp enum_options(value) when is_binary(value), do: String.split(value, "\n", trim: true)
  defp enum_options(value) when is_list(value), do: value

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, _key, ""), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil

  defp parse_number(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_number(num) when is_number(num), do: num
  defp parse_number(_), do: nil

  # ────────────────────────────────────────────────────────────────────
  # Private Helpers - Roles
  # ────────────────────────────────────────────────────────────────────

  defp parse_roles(nil), do: []
  defp parse_roles(""), do: []

  defp parse_roles(roles) when is_binary(roles) do
    roles
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_roles(roles) when is_list(roles), do: roles

  # ────────────────────────────────────────────────────────────────────
  # Private Helpers - Blocks
  # ────────────────────────────────────────────────────────────────────

  defp default_name_for_block(block_type, position)
       when block_type in [
              :text_input,
              :number_input,
              :select_input,
              :checkbox_input,
              :timestamp_input,
              :duration_input,
              :attachment_input,
              :signature_input
            ] do
    "#{block_type}_#{position}"
  end

  defp default_name_for_block(_block_type, _position), do: nil

  defp default_content_for_type("text"), do: %{"markdown" => ""}
  defp default_content_for_type("note"), do: %{"text" => "", "severity" => "info"}
  defp default_content_for_type("caution"), do: %{"text" => ""}
  defp default_content_for_type("warning"), do: %{"text" => ""}

  defp default_content_for_type("telemetry_value"),
    do: %{"item_path" => "", "label" => "", "unit" => ""}

  defp default_content_for_type("telemetry_check"),
    do: %{"item_path" => "", "operator" => "==", "expected_value" => ""}

  defp default_content_for_type("telemetry_wait"),
    do: %{"item_path" => "", "operator" => "==", "expected_value" => "", "timeout_ms" => 30_000}

  defp default_content_for_type("command"),
    do: %{"command_name" => "", "target" => "", "arguments" => %{}, "priority" => 3}

  defp default_content_for_type("text_input"),
    do: %{"label" => "", "variable_name" => "", "placeholder" => ""}

  defp default_content_for_type("number_input"),
    do: %{"label" => "", "variable_name" => "", "min" => nil, "max" => nil}

  defp default_content_for_type("select_input"),
    do: %{"label" => "", "variable_name" => "", "options" => []}

  defp default_content_for_type(_), do: %{}

  # Build content map from form params
  defp build_content_from_params(:text, params), do: %{"markdown" => params["markdown"] || ""}
  defp build_content_from_params(:note, params), do: %{"text" => params["text"] || ""}
  defp build_content_from_params(:caution, params), do: %{"text" => params["text"] || ""}
  defp build_content_from_params(:warning, params), do: %{"text" => params["text"] || ""}

  defp build_content_from_params(:telemetry_value, params) do
    %{
      "item_path" => params["item_path"] || "",
      "label" => params["label"] || "",
      "unit" => params["unit"] || ""
    }
  end

  defp build_content_from_params(:telemetry_check, params) do
    %{
      "item_path" => params["item_path"] || "",
      "operator" => params["operator"] || "==",
      "expected_value" => params["expected_value"] || ""
    }
  end

  defp build_content_from_params(:telemetry_wait, params) do
    %{
      "item_path" => params["item_path"] || "",
      "operator" => params["operator"] || "==",
      "expected_value" => params["expected_value"] || "",
      "timeout_ms" => parse_int(params["timeout_ms"], 30_000)
    }
  end

  defp build_content_from_params(:command, params) do
    args =
      case params["arguments"] do
        nil -> %{}
        "" -> %{}
        json when is_binary(json) -> parse_json_args(json)
        map when is_map(map) -> map
      end

    %{
      "command_name" => params["command_name"] || "",
      "target" => params["target"] || "",
      "arguments" => args,
      "priority" => parse_int(params["priority"], 3)
    }
  end

  defp build_content_from_params(:text_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "placeholder" => params["placeholder"] || ""
    }
  end

  defp build_content_from_params(:number_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "min" => parse_optional_number(params["min"]),
      "max" => parse_optional_number(params["max"])
    }
  end

  defp build_content_from_params(:select_input, params) do
    options =
      case params["options"] do
        nil -> []
        "" -> []
        str when is_binary(str) -> String.split(str, "\n", trim: true)
        list when is_list(list) -> list
      end

    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "options" => options
    }
  end

  defp build_content_from_params(_, params) do
    params
    |> Map.drop(["block_id", "step_id", "_csrf_token"])
    |> Map.reject(fn {k, _} -> String.starts_with?(k, "_") end)
  end

  defp parse_json_args(json) do
    Jason.decode!(json)
  rescue
    _ -> %{}
  end

  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end

  defp parse_int(num, _default) when is_integer(num), do: num
  defp parse_int(_, default), do: default

  defp parse_optional_number(nil), do: nil
  defp parse_optional_number(""), do: nil

  defp parse_optional_number(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> nil
    end
  end

  defp parse_optional_number(num) when is_number(num), do: num
  defp parse_optional_number(_), do: nil

  defp section_letter(index) do
    <<?A + index::utf8>>
  end

  # ────────────────────────────────────────────────────────────────────
  # Render
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    parameters = get_parameters(assigns.version)
    assigns = assign(assigns, :parameters, parameters)

    ~H"""
    <div class="h-[calc(100vh-4rem)] flex flex-col overflow-hidden" id="procedure-editor">
      <!-- Header -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-primary/20 bg-surface-raised">
        <div class="flex items-center gap-4">
          <.link
            navigate={~p"/missions/#{@mission}/procedures/#{@procedure}"}
            class="btn btn-ghost btn-sm hover-glow-cyan transition-smooth"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" />
          </.link>
          <div>
            <h1 class="text-lg font-bold tracking-wide">{@procedure.name}</h1>
            <span class="hud-label">
              Version {@version.version_number} • Editing
            </span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span class={[
            "badge",
            @version.status == :draft && "badge-warning",
            @version.status == :approved && "badge-success",
            @version.status == :deprecated && "badge-ghost"
          ]}>
            {@version.status}
          </span>
        </div>
      </div>
      
    <!-- Two Column Layout -->
      <div class="flex-1 flex overflow-hidden">
        <!-- Left Panel: Navigation Sidebar -->
        <div class="w-64 border-r border-cyan-subtle bg-surface-raised hud-grid flex flex-col">
          <div class="flex-1 overflow-y-auto p-3">
            <!-- Settings Nav Item -->
            <div
              class={[
                "flex items-center gap-2 px-3 py-2 rounded-sm cursor-pointer mb-3",
                "hover:bg-cyan-ghost transition-smooth"
              ]}
              phx-click="toggle_settings"
            >
              <.icon name="hero-cog-6-tooth" class="h-4 w-4 opacity-70" />
              <span class="text-sm font-medium text-base-content">Procedure Settings</span>
              <%= if length(@parameters) > 0 do %>
                <span class="badge badge-sm badge-ghost">{length(@parameters)}</span>
              <% end %>
            </div>

            <div class="hud-divider my-2"></div>
            
    <!-- Sections Navigation -->
            <div class="space-y-2">
              <%= for {section, idx} <- Enum.with_index(@sections) do %>
                <.nav_section
                  section={section}
                  section_letter={section_letter(idx)}
                  collapsed={MapSet.member?(@collapsed_section_ids, section.id)}
                />
              <% end %>

              <%= if Enum.empty?(@sections) do %>
                <div class="text-center py-4 opacity-60 text-sm">
                  No sections yet
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Add Section Button -->
          <div class="p-3 border-t border-cyan-subtle">
            <button
              type="button"
              class="btn btn-ghost btn-sm w-full justify-start gap-2 hover-glow-cyan transition-smooth"
              phx-click="add_section"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> Add Section
            </button>
          </div>
        </div>
        
    <!-- Center Panel: Full Procedure Document -->
        <div class="flex-1 bg-surface-base flex flex-col overflow-hidden">
          <div class="flex-1 overflow-y-auto" id="procedure-scroll-container" phx-hook="ScrollTo">
            <div class="p-4 space-y-6 max-w-4xl mx-auto">
              <!-- Settings Section -->
              <.settings_section
                expanded={@settings_expanded}
                parameters={@parameters}
                editing_index={@editing_parameter_index}
                adding={@adding_parameter}
                parameter_types={@parameter_types}
              />
              
    <!-- Procedure Sections -->
              <%= for {section, idx} <- Enum.with_index(@sections) do %>
                <.document_section
                  section={section}
                  section_letter={section_letter(idx)}
                  collapsed={MapSet.member?(@collapsed_section_ids, section.id)}
                  editing_section={section.id == @editing_section_id}
                  editing_step_id={@editing_step_id}
                  editing_block_id={@editing_block_id}
                  show_palette_for_step={@show_block_palette_for_step}
                />
              <% end %>

              <%= if Enum.empty?(@sections) do %>
                <div class="text-center py-16 opacity-60">
                  <.icon name="hero-document-plus" class="h-12 w-12 mx-auto mb-4" />
                  <p class="text-lg">No sections yet</p>
                  <p class="text-sm opacity-80 mt-2">Click "Add Section" to get started</p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Navigation Components
  # ────────────────────────────────────────────────────────────────────

  attr :section, :map, required: true
  attr :section_letter, :string, required: true
  attr :collapsed, :boolean, default: false

  defp nav_section(assigns) do
    ~H"""
    <div class="space-y-1">
      <div
        class="group flex items-center gap-2 px-3 py-2 rounded-sm cursor-pointer hover:bg-cyan-ghost transition-smooth"
        phx-click="scroll_to_section"
        phx-value-id={@section.id}
      >
        <span class="hud-label">{@section_letter}.</span>
        <span class="flex-1 text-sm font-medium truncate text-base-content">{@section.name}</span>
        <span class="text-xs opacity-50">{length(@section.steps)}</span>
      </div>

      <%= unless @collapsed do %>
        <div class="ml-6 space-y-1">
          <%= for {step, step_idx} <- Enum.with_index(@section.steps) do %>
            <div
              class="flex items-center gap-2 px-3 py-1.5 rounded-sm text-sm cursor-pointer hover:bg-cyan-ghost transition-smooth"
              phx-click="scroll_to_step"
              phx-value-id={step.id}
            >
              <span class="hud-label">
                {@section_letter}{step_idx + 1}
              </span>
              <span class="truncate text-sm opacity-80">{step.name}</span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Settings Section Component
  # ────────────────────────────────────────────────────────────────────

  attr :expanded, :boolean, default: true
  attr :parameters, :list, default: []
  attr :editing_index, :integer, default: nil
  attr :adding, :boolean, default: false
  attr :parameter_types, :list, required: true

  defp settings_section(assigns) do
    ~H"""
    <div id="settings-section" class="scroll-mt-6">
      <div class="hud-panel bg-surface-raised">
        <!-- Header -->
        <div
          class="flex items-center justify-between p-4 cursor-pointer hover:bg-cyan-ghost transition-smooth hud-panel-header"
          phx-click="toggle_settings"
        >
          <div class="flex items-center gap-3">
            <button type="button" class="btn btn-ghost btn-xs">
              <%= if @expanded do %>
                <.icon name="hero-chevron-down" class="h-4 w-4" />
              <% else %>
                <.icon name="hero-chevron-right" class="h-4 w-4" />
              <% end %>
            </button>
            <.icon name="hero-cog-6-tooth" class="h-5 w-5 opacity-70" />
            <span class="font-semibold text-base-content tracking-wide">Procedure Settings</span>
          </div>
          <%= if length(@parameters) > 0 do %>
            <span class="badge badge-sm">{length(@parameters)} parameters</span>
          <% end %>
        </div>
        
    <!-- Content -->
        <%= if @expanded do %>
          <div class="border-t border-cyan-subtle p-4">
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <h3 class="hud-label">
                  Input Parameters
                </h3>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm gap-1 hover-glow-cyan transition-smooth"
                  phx-click="add_parameter"
                >
                  <.icon name="hero-plus" class="h-4 w-4" /> Add Parameter
                </button>
              </div>

              <%= if Enum.empty?(@parameters) && !@adding do %>
                <div class="text-center py-8 text-sm opacity-60">
                  <.icon name="hero-variable" class="h-8 w-8 mx-auto mb-2" />
                  <p>No parameters defined</p>
                  <p class="text-xs opacity-80">
                    Parameters allow users to provide input when executing this procedure
                  </p>
                </div>
              <% else %>
                <div class="space-y-3">
                  <%= for {param, idx} <- Enum.with_index(@parameters) do %>
                    <.parameter_card
                      param={param}
                      index={idx}
                      editing={@editing_index == idx}
                      parameter_types={@parameter_types}
                    />
                  <% end %>
                </div>
              <% end %>

              <%= if @adding do %>
                <.parameter_form
                  param={
                    %{"name" => "", "type" => "string", "required" => false, "description" => ""}
                  }
                  index={nil}
                  is_new={true}
                  parameter_types={@parameter_types}
                />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :param, :map, required: true
  attr :index, :any, required: true
  attr :editing, :boolean, default: false
  attr :parameter_types, :list, required: true

  defp parameter_card(assigns) do
    ~H"""
    <%= if @editing do %>
      <.parameter_form
        param={@param}
        index={@index}
        is_new={false}
        parameter_types={@parameter_types}
      />
    <% else %>
      <div class="flex items-center justify-between p-4 bg-surface-elevated hud-border rounded-sm group hover:hud-border-glow transition-smooth">
        <div class="flex items-center gap-3">
          <div>
            <div class="flex items-center gap-2">
              <span class="font-mono font-medium text-sm">{@param["name"]}</span>
              <span class="badge badge-sm badge-outline">{@param["type"]}</span>
              <%= if @param["required"] do %>
                <span class="badge badge-sm badge-error">required</span>
              <% end %>
            </div>
            <%= if @param["description"] && @param["description"] != "" do %>
              <p class="text-xs opacity-70 mt-2">{@param["description"]}</p>
            <% end %>
          </div>
        </div>
        <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-smooth">
          <button
            type="button"
            class="btn btn-ghost btn-xs hover-glow-cyan"
            phx-click="edit_parameter"
            phx-value-index={@index}
          >
            <.icon name="hero-pencil" class="h-4 w-4" />
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-xs text-error"
            phx-click="delete_parameter"
            phx-value-index={@index}
            data-confirm="Delete this parameter?"
          >
            <.icon name="hero-trash" class="h-4 w-4" />
          </button>
        </div>
      </div>
    <% end %>
    """
  end

  attr :param, :map, required: true
  attr :index, :any, default: nil
  attr :is_new, :boolean, default: false
  attr :parameter_types, :list, required: true

  defp parameter_form(assigns) do
    event = if assigns.is_new, do: "save_new_parameter", else: "save_parameter"
    cancel_event = if assigns.is_new, do: "cancel_add_parameter", else: "cancel_edit_parameter"
    assigns = assign(assigns, event: event, cancel_event: cancel_event)

    ~H"""
    <form phx-submit={@event} class="p-4 bg-surface-elevated hud-border rounded-sm space-y-3">
      <%= if @index do %>
        <input type="hidden" name="index" value={@index} />
      <% end %>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="hud-label">Name</label>
          <input
            type="text"
            name="name"
            value={@param["name"]}
            class="mt-1 input input-bordered input-sm w-full font-mono rounded-sm"
            placeholder="parameter_name"
            required
          />
        </div>
        <div>
          <label class="hud-label">Type</label>
          <select name="type" class="mt-1 select select-bordered select-sm w-full rounded-sm">
            <%= for type <- @parameter_types do %>
              <option value={type} selected={@param["type"] == type}>{type}</option>
            <% end %>
          </select>
        </div>
      </div>

      <div>
        <label class="hud-label">Description</label>
        <input
          type="text"
          name="description"
          value={@param["description"]}
          class="mt-1 input input-bordered input-sm w-full rounded-sm"
          placeholder="Optional description"
        />
      </div>

      <div class="flex items-center gap-4">
        <label class="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            name="required"
            value="true"
            checked={@param["required"]}
            class="checkbox checkbox-sm"
          />
          <span class="text-sm">Required</span>
        </label>
      </div>
      
    <!-- Type-specific fields could go here -->

      <div class="flex items-center justify-end gap-3 pt-3">
        <button type="button" class="btn btn-sm btn-ghost" phx-click={@cancel_event}>
          Cancel
        </button>
        <button type="submit" class="btn btn-sm btn-primary">
          {if @is_new, do: "Add", else: "Save"}
        </button>
      </div>
    </form>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Document Section Component
  # ────────────────────────────────────────────────────────────────────

  attr :section, :map, required: true
  attr :section_letter, :string, required: true
  attr :collapsed, :boolean, default: false
  attr :editing_section, :boolean, default: false
  attr :editing_step_id, :string, default: nil
  attr :editing_block_id, :string, default: nil
  attr :show_palette_for_step, :string, default: nil

  defp document_section(assigns) do
    ~H"""
    <div id={"section-#{@section.id}"} class="scroll-mt-6">
      <!-- Sticky Section Header -->
      <div class="sticky top-0 z-10 bg-surface-elevated hud-border border-l-2 border-l-primary rounded-sm mb-4">
        <div class="flex items-center justify-between p-4">
          <div class="flex items-center gap-3">
            <button
              type="button"
              phx-click="toggle_section_collapsed"
              phx-value-id={@section.id}
              class="btn btn-ghost btn-xs"
            >
              <%= if @collapsed do %>
                <.icon name="hero-chevron-right" class="h-4 w-4" />
              <% else %>
                <.icon name="hero-chevron-down" class="h-4 w-4" />
              <% end %>
            </button>

            <%= if @editing_section do %>
              <form phx-submit="save_section_name" phx-value-id={@section.id} class="flex-1">
                <input
                  type="text"
                  name="name"
                  value={@section.name}
                  class="input input-sm input-bordered rounded-sm"
                  autofocus
                  phx-blur="cancel_edit_section"
                />
              </form>
            <% else %>
              <span class="font-semibold tracking-wide">
                Section {@section_letter}: {@section.name}
              </span>
            <% end %>
          </div>

          <div class="flex items-center gap-3">
            <span class="hud-label">{length(@section.steps)} steps</span>
            <div class="dropdown dropdown-end">
              <label tabindex="0" class="btn btn-ghost btn-xs hover-glow-cyan transition-smooth">
                <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
              </label>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow-lg bg-surface-elevated hud-border rounded-sm w-40"
              >
                <li>
                  <button phx-click="edit_section" phx-value-id={@section.id}>
                    <.icon name="hero-pencil" class="h-4 w-4" /> Rename
                  </button>
                </li>
                <li>
                  <button
                    class="text-error"
                    phx-click="delete_section"
                    phx-value-id={@section.id}
                    data-confirm="Delete this section and all its steps?"
                  >
                    <.icon name="hero-trash" class="h-4 w-4" /> Delete
                  </button>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Section Steps -->
      <%= unless @collapsed do %>
        <div class="space-y-4 pl-3">
          <%= for {step, step_idx} <- Enum.with_index(@section.steps) do %>
            <.step_card
              step={step}
              section_letter={@section_letter}
              step_index={step_idx + 1}
              editing={step.id == @editing_step_id}
              editing_block_id={@editing_block_id}
              show_palette={step.id == @show_palette_for_step}
            />
          <% end %>
          
    <!-- Add Step Button -->
          <button
            type="button"
            class="flex items-center gap-2 px-4 py-3 text-sm opacity-60 hover:opacity-100 hover:text-primary hover:bg-cyan-ghost rounded-sm w-full transition-smooth"
            phx-click="add_step"
            phx-value-section_id={@section.id}
          >
            <.icon name="hero-plus" class="h-4 w-4" /> Add step to {@section.name}
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Step Card Component
  # ────────────────────────────────────────────────────────────────────

  attr :step, :map, required: true
  attr :section_letter, :string, required: true
  attr :step_index, :integer, required: true
  attr :editing, :boolean, default: false
  attr :editing_block_id, :string, default: nil
  attr :show_palette, :boolean, default: false

  defp step_card(assigns) do
    ~H"""
    <div
      id={"step-#{@step.id}"}
      class="bg-surface-raised hud-border rounded-sm scroll-mt-24 hover:hud-border-glow transition-smooth"
    >
      <!-- Step Header -->
      <div class="flex items-center justify-between p-4 border-b border-cyan-subtle">
        <div class="flex items-center gap-4">
          <span class="w-9 h-9 rounded-full bg-neutral text-neutral-content flex items-center justify-center text-sm font-bold glow-cyan-soft">
            {@section_letter}{@step_index}
          </span>
          <div>
            <span class="font-mono font-medium">{@step.name}</span>
            <%= if @step.title do %>
              <span class="opacity-70 ml-2">{@step.title}</span>
            <% end %>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <!-- Step badges -->
          <%= if @step.requires_signoff do %>
            <span class="badge badge-sm badge-warning">signoff</span>
          <% end %>

          <button
            type="button"
            class="btn btn-ghost btn-xs hover-glow-cyan transition-smooth"
            phx-click="edit_step"
            phx-value-id={@step.id}
            title="Edit step properties"
          >
            <.icon name="hero-cog-6-tooth" class="h-4 w-4" />
          </button>

          <button
            type="button"
            class="btn btn-ghost btn-xs text-error"
            phx-click="delete_step"
            phx-value-id={@step.id}
            data-confirm="Delete this step?"
          >
            <.icon name="hero-trash" class="h-4 w-4" />
          </button>
        </div>
      </div>
      
    <!-- Step Properties Edit Form (inline) -->
      <%= if @editing do %>
        <div class="p-4 bg-surface-elevated border-b border-cyan-subtle">
          <form phx-submit="save_step" class="space-y-3">
            <input type="hidden" name="step_id" value={@step.id} />

            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="hud-label">Name</label>
                <input
                  type="text"
                  name="name"
                  value={@step.name}
                  class="mt-1 input input-bordered input-sm w-full font-mono rounded-sm"
                  required
                />
              </div>
              <div>
                <label class="hud-label">Title</label>
                <input
                  type="text"
                  name="title"
                  value={@step.title || ""}
                  class="mt-1 input input-bordered input-sm w-full rounded-sm"
                  placeholder="Human-readable title"
                />
              </div>
            </div>

            <div class="grid grid-cols-3 gap-3">
              <div>
                <label class="flex items-center gap-2">
                  <input
                    type="checkbox"
                    name="requires_signoff"
                    value="true"
                    checked={@step.requires_signoff}
                    class="checkbox checkbox-sm"
                  />
                  <span class="text-sm">Requires Signoff</span>
                </label>
              </div>
              <div>
                <label class="hud-label">On Failure</label>
                <select name="on_fail" class="mt-1 select select-bordered select-sm w-full rounded-sm">
                  <option value="pause" selected={@step.on_fail == :pause}>Pause</option>
                  <option value="abort" selected={@step.on_fail == :abort}>Abort</option>
                  <option value="continue" selected={@step.on_fail == :continue}>Continue</option>
                </select>
              </div>
              <div>
                <label class="hud-label">Required Roles</label>
                <input
                  type="text"
                  name="required_roles"
                  value={Enum.join(@step.required_roles || [], ", ")}
                  class="mt-1 input input-bordered input-sm w-full rounded-sm"
                  placeholder="operator, supervisor"
                />
              </div>
            </div>

            <div class="flex justify-end gap-3">
              <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_edit_step">
                Cancel
              </button>
              <button type="submit" class="btn btn-sm btn-primary">Save</button>
            </div>
          </form>
        </div>
      <% end %>
      
    <!-- Blocks -->
      <div class="p-4 space-y-3">
        <%= for block <- @step.blocks do %>
          <.block_card block={block} editing={block.id == @editing_block_id} />
        <% end %>

        <%= if Enum.empty?(@step.blocks) && !@show_palette do %>
          <div class="text-center py-8 opacity-60">
            <.icon name="hero-cube-transparent" class="h-8 w-8 mx-auto mb-2" />
            <p class="text-sm">No blocks yet</p>
          </div>
        <% end %>
        
    <!-- Block Palette -->
        <%= if @show_palette do %>
          <.block_palette step_id={@step.id} />
        <% end %>
        
    <!-- Add Block Button -->
        <button
          type="button"
          class={[
            "flex items-center gap-2 px-4 py-3 text-sm rounded-sm w-full transition-smooth",
            @show_palette && "btn btn-primary btn-sm",
            !@show_palette && "opacity-60 hover:opacity-100 hover:text-primary hover:bg-cyan-ghost"
          ]}
          phx-click="toggle_block_palette"
          phx-value-step_id={@step.id}
        >
          <.icon name={if @show_palette, do: "hero-x-mark", else: "hero-plus"} class="h-4 w-4" />
          {if @show_palette, do: "Close", else: "Add Block"}
        </button>
      </div>
    </div>
    """
  end

  # ────────────────────────────────────────────────────────────────────
  # Block Components
  # ────────────────────────────────────────────────────────────────────

  attr :step_id, :string, required: true

  defp block_palette(assigns) do
    ~H"""
    <div class="p-4 bg-surface-elevated hud-border rounded-sm">
      <div class="grid grid-cols-4 gap-3">
        <div class="space-y-2">
          <span class="hud-label">Content</span>
          <.block_type_btn step_id={@step_id} type="text" icon="hero-document-text" label="Text" />
          <.block_type_btn step_id={@step_id} type="note" icon="hero-information-circle" label="Note" />
          <.block_type_btn
            step_id={@step_id}
            type="caution"
            icon="hero-exclamation-triangle"
            label="Caution"
          />
          <.block_type_btn
            step_id={@step_id}
            type="warning"
            icon="hero-exclamation-circle"
            label="Warning"
          />
        </div>
        <div class="space-y-2">
          <span class="hud-label">Inputs</span>
          <.block_type_btn
            step_id={@step_id}
            type="text_input"
            icon="hero-pencil-square"
            label="Text Input"
          />
          <.block_type_btn
            step_id={@step_id}
            type="number_input"
            icon="hero-calculator"
            label="Number"
          />
          <.block_type_btn
            step_id={@step_id}
            type="select_input"
            icon="hero-list-bullet"
            label="Select"
          />
        </div>
        <div class="space-y-2">
          <span class="hud-label">Telemetry</span>
          <.block_type_btn step_id={@step_id} type="telemetry_value" icon="hero-signal" label="Value" />
          <.block_type_btn
            step_id={@step_id}
            type="telemetry_check"
            icon="hero-check-circle"
            label="Check"
          />
          <.block_type_btn step_id={@step_id} type="telemetry_wait" icon="hero-clock" label="Wait" />
        </div>
        <div class="space-y-2">
          <span class="hud-label">Commands</span>
          <.block_type_btn step_id={@step_id} type="command" icon="hero-command-line" label="Command" />
        </div>
      </div>
    </div>
    """
  end

  attr :step_id, :string, required: true
  attr :type, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp block_type_btn(assigns) do
    ~H"""
    <button
      type="button"
      class="btn btn-sm btn-ghost justify-start w-full hover-glow-cyan transition-smooth rounded-sm"
      phx-click="add_block"
      phx-value-step_id={@step_id}
      phx-value-type={@type}
    >
      <.icon name={@icon} class="h-4 w-4" />
      <span>{@label}</span>
    </button>
    """
  end

  attr :block, :map, required: true
  attr :editing, :boolean, default: false

  defp block_card(assigns) do
    ~H"""
    <div class={[
      "bg-surface-raised rounded-sm p-3 group transition-smooth",
      @editing && "hud-border-glow ring-1 ring-primary/20",
      !@editing && "hud-border hover:hud-border-glow"
    ]}>
      <div class="flex items-start justify-between">
        <div class="flex items-center gap-2 mb-2">
          <.block_icon type={@block.block_type} />
          <span class="hud-label">
            {format_block_type(@block.block_type)}
          </span>
        </div>
        <div class="flex items-center gap-1">
          <%= if not @editing do %>
            <button
              type="button"
              class="btn btn-ghost btn-xs opacity-0 group-hover:opacity-100 transition-smooth"
              phx-click="edit_block"
              phx-value-id={@block.id}
              title="Edit block"
            >
              <.icon name="hero-pencil" class="h-4 w-4" />
            </button>
          <% end %>
          <button
            type="button"
            class="btn btn-ghost btn-xs text-error opacity-0 group-hover:opacity-100 transition-smooth"
            phx-click="delete_block"
            phx-value-id={@block.id}
            title="Delete block"
          >
            <.icon name="hero-trash" class="h-4 w-4" />
          </button>
        </div>
      </div>
      <%= if @editing do %>
        <.block_edit_form block={@block} />
      <% else %>
        <div class="cursor-pointer" phx-click="edit_block" phx-value-id={@block.id}>
          <.block_content block={@block} />
        </div>
      <% end %>
    </div>
    """
  end

  attr :block, :map, required: true

  defp block_edit_form(assigns) do
    ~H"""
    <form phx-submit="save_block" class="space-y-4">
      <input type="hidden" name="block_id" value={@block.id} />
      <.block_edit_fields block={@block} />
      <div class="flex items-center justify-end gap-3 pt-3">
        <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_edit_block">
          Cancel
        </button>
        <button type="submit" class="btn btn-sm btn-primary">
          Save
        </button>
      </div>
    </form>
    """
  end

  attr :block, :map, required: true

  defp block_edit_fields(assigns) do
    ~H"""
    <%= case @block.block_type do %>
      <% :text -> %>
        <textarea
          name="markdown"
          class="textarea textarea-bordered w-full"
          rows="3"
          placeholder="Enter markdown text..."
        >{@block.content["markdown"] || ""}</textarea>
      <% type when type in [:note, :caution, :warning] -> %>
        <textarea
          name="text"
          class="textarea textarea-bordered w-full"
          rows="3"
          placeholder="Enter text..."
        >{@block.content["text"] || ""}</textarea>
      <% :telemetry_value -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="item_path"
            value={@block.content["item_path"] || ""}
            class="input input-bordered input-sm w-full font-mono"
            placeholder="TARGET.PACKET.item"
          />
          <div class="grid grid-cols-2 gap-2">
            <input
              type="text"
              name="label"
              value={@block.content["label"] || ""}
              class="input input-bordered input-sm"
              placeholder="Label"
            />
            <input
              type="text"
              name="unit"
              value={@block.content["unit"] || ""}
              class="input input-bordered input-sm"
              placeholder="Unit (e.g., V, A, Hz)"
            />
          </div>
        </div>
      <% :telemetry_check -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="item_path"
            value={@block.content["item_path"] || ""}
            class="input input-bordered input-sm w-full font-mono"
            placeholder="TARGET.PACKET.item"
          />
          <div class="grid grid-cols-2 gap-2">
            <select name="operator" class="select select-bordered select-sm">
              <%= for op <- ["==", "!=", ">", ">=", "<", "<="] do %>
                <option value={op} selected={@block.content["operator"] == op}>{op}</option>
              <% end %>
            </select>
            <input
              type="text"
              name="expected_value"
              value={@block.content["expected_value"] || ""}
              class="input input-bordered input-sm"
              placeholder="Expected value"
            />
          </div>
        </div>
      <% :telemetry_wait -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="item_path"
            value={@block.content["item_path"] || ""}
            class="input input-bordered input-sm w-full font-mono"
            placeholder="TARGET.PACKET.item"
          />
          <div class="grid grid-cols-3 gap-2">
            <select name="operator" class="select select-bordered select-sm">
              <%= for op <- ["==", "!=", ">", ">=", "<", "<="] do %>
                <option value={op} selected={@block.content["operator"] == op}>{op}</option>
              <% end %>
            </select>
            <input
              type="text"
              name="expected_value"
              value={@block.content["expected_value"] || ""}
              class="input input-bordered input-sm"
              placeholder="Expected"
            />
            <input
              type="number"
              name="timeout_ms"
              value={@block.content["timeout_ms"] || 30000}
              class="input input-bordered input-sm"
              placeholder="Timeout (ms)"
            />
          </div>
        </div>
      <% :command -> %>
        <div class="space-y-2">
          <div class="grid grid-cols-2 gap-2">
            <input
              type="text"
              name="command_name"
              value={@block.content["command_name"] || ""}
              class="input input-bordered input-sm font-mono"
              placeholder="COMMAND_NAME"
            />
            <input
              type="text"
              name="target"
              value={@block.content["target"] || ""}
              class="input input-bordered input-sm font-mono"
              placeholder="{{params.target}} or target_id"
            />
          </div>
          <div class="grid grid-cols-4 gap-2">
            <div class="col-span-3">
              <textarea
                name="arguments"
                class="textarea textarea-bordered textarea-sm w-full font-mono"
                rows="2"
                placeholder='{"arg": "value"}'
              ><%= if @block.content["arguments"] && @block.content["arguments"] != %{}, do: Jason.encode!(@block.content["arguments"], pretty: true), else: "" %></textarea>
            </div>
            <div>
              <label class="text-xs opacity-70">Priority</label>
              <select name="priority" class="select select-bordered select-sm w-full">
                <%= for {label, val} <- [{"Emergency", 0}, {"Critical", 1}, {"High", 2}, {"Normal", 3}, {"Low", 4}, {"Background", 5}] do %>
                  <option value={val} selected={(@block.content["priority"] || 3) == val}>
                    {label}
                  </option>
                <% end %>
              </select>
            </div>
          </div>
        </div>
      <% :text_input -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="label"
            value={@block.content["label"] || ""}
            class="input input-bordered input-sm w-full"
            placeholder="Label"
          />
          <div class="grid grid-cols-2 gap-2">
            <input
              type="text"
              name="variable_name"
              value={@block.content["variable_name"] || ""}
              class="input input-bordered input-sm font-mono"
              placeholder="variable_name"
            />
            <input
              type="text"
              name="placeholder"
              value={@block.content["placeholder"] || ""}
              class="input input-bordered input-sm"
              placeholder="Placeholder text"
            />
          </div>
        </div>
      <% :number_input -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="label"
            value={@block.content["label"] || ""}
            class="input input-bordered input-sm w-full"
            placeholder="Label"
          />
          <div class="grid grid-cols-3 gap-2">
            <input
              type="text"
              name="variable_name"
              value={@block.content["variable_name"] || ""}
              class="input input-bordered input-sm font-mono"
              placeholder="variable"
            />
            <input
              type="number"
              name="min"
              value={@block.content["min"]}
              class="input input-bordered input-sm"
              placeholder="Min"
            />
            <input
              type="number"
              name="max"
              value={@block.content["max"]}
              class="input input-bordered input-sm"
              placeholder="Max"
            />
          </div>
        </div>
      <% :select_input -> %>
        <div class="space-y-2">
          <input
            type="text"
            name="label"
            value={@block.content["label"] || ""}
            class="input input-bordered input-sm w-full"
            placeholder="Label"
          />
          <input
            type="text"
            name="variable_name"
            value={@block.content["variable_name"] || ""}
            class="input input-bordered input-sm w-full font-mono"
            placeholder="variable_name"
          />
          <textarea
            name="options"
            class="textarea textarea-bordered textarea-sm w-full"
            rows="3"
            placeholder="One option per line"
          ><%= Enum.join(@block.content["options"] || [], "\n") %></textarea>
        </div>
      <% _ -> %>
        <div class="text-sm opacity-60">
          Edit not available for this block type
        </div>
    <% end %>
    """
  end

  attr :type, :atom, required: true

  @block_type_icons %{
    text: "hero-document-text",
    note: "hero-information-circle",
    caution: "hero-exclamation-triangle",
    warning: "hero-exclamation-circle",
    text_input: "hero-pencil-square",
    number_input: "hero-calculator",
    select_input: "hero-list-bullet",
    telemetry_value: "hero-signal",
    telemetry_check: "hero-check-circle",
    telemetry_wait: "hero-clock",
    command: "hero-command-line"
  }

  defp block_icon(assigns) do
    icon = Map.get(@block_type_icons, assigns.type, "hero-cube")
    assigns = assign(assigns, :icon, icon)

    ~H"""
    <.icon name={@icon} class="h-4 w-4" />
    """
  end

  attr :block, :map, required: true

  defp block_content(assigns) do
    ~H"""
    <div class="text-sm">
      <%= case @block.block_type do %>
        <% :text -> %>
          <p class="opacity-90">{@block.content["markdown"] || "(empty)"}</p>
        <% :note -> %>
          <div class="bg-info/10 border-l-4 border-info p-2 rounded">
            {@block.content["text"] || "(empty note)"}
          </div>
        <% :caution -> %>
          <div class="bg-warning/10 border-l-4 border-warning p-2 rounded">
            {@block.content["text"] || "(empty caution)"}
          </div>
        <% :warning -> %>
          <div class="bg-error/10 border-l-4 border-error p-2 rounded">
            {@block.content["text"] || "(empty warning)"}
          </div>
        <% :telemetry_value -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded">
            <span class="text-primary">{@block.content["item_path"] || "item.path"}</span>
            <%= if @block.content["unit"] && @block.content["unit"] != "" do %>
              <span class="opacity-60 ml-1">({@block.content["unit"]})</span>
            <% end %>
          </div>
        <% :telemetry_check -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded flex items-center gap-2">
            <span class="text-primary">{@block.content["item_path"] || "item.path"}</span>
            <span class="opacity-60">{@block.content["operator"] || "=="}</span>
            <span class="text-success">{@block.content["expected_value"] || "?"}</span>
          </div>
        <% :telemetry_wait -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded">
            <div class="flex items-center gap-2">
              <.icon name="hero-clock" class="h-3 w-3" />
              <span>Wait for</span>
              <span class="text-primary">{@block.content["item_path"] || "item.path"}</span>
              <span class="opacity-60">{@block.content["operator"] || "=="}</span>
              <span class="text-success">{@block.content["expected_value"] || "?"}</span>
            </div>
            <div class="opacity-60 mt-1">
              Timeout: {@block.content["timeout_ms"] || 30000}ms
            </div>
          </div>
        <% :command -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded space-y-1">
            <div class="flex items-center gap-2">
              <span class="text-warning">{@block.content["command_name"] || "COMMAND"}</span>
              <%= if @block.content["target"] && @block.content["target"] != "" do %>
                <span class="opacity-60">→</span>
                <span class="text-info">{@block.content["target"]}</span>
              <% end %>
            </div>
            <%= if @block.content["arguments"] && @block.content["arguments"] != %{} do %>
              <div class="opacity-70">
                {Jason.encode!(@block.content["arguments"])}
              </div>
            <% end %>
          </div>
        <% :text_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Input"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
            </div>
          </div>
        <% :number_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Number Input"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
              <%= if @block.content["min"] || @block.content["max"] do %>
                | Range: {@block.content["min"] || "*"} - {@block.content["max"] || "*"}
              <% end %>
            </div>
          </div>
        <% :select_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Select"}</div>
            <div class="text-xs opacity-60">
              {length(@block.content["options"] || [])} options
            </div>
          </div>
        <% _ -> %>
          <div class="opacity-60 font-mono text-xs">
            {Jason.encode!(@block.content, pretty: true)}
          </div>
      <% end %>
    </div>
    """
  end

  defp format_block_type(type) do
    type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
