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
    mission = socket.assigns.mission
    user_id = socket.assigns.current_scope.user.id

    case load_version_for_mission(mission, procedure_id, version_id) do
      {:ok, procedure, version} ->
        # If the version is approved, create a new draft and redirect to it
        if version.status == :approved do
          case Procedures.create_draft_from_version(version, user_id: user_id) do
            {:ok, new_version} ->
              socket
              |> put_flash(
                :info,
                "Created new draft v#{new_version.version_number} from approved v#{version.version_number}"
              )
              |> push_navigate(
                to:
                  ~p"/missions/#{mission}/procedures-v2/#{procedure.id}/versions/#{new_version.id}/edit"
              )

            {:error, _reason} ->
              socket
              |> put_flash(:error, "Failed to create new draft version")
              |> push_navigate(to: ~p"/missions/#{mission}/procedures/#{procedure.id}")
          end
        else
          # Normal edit flow for draft/in_review/changes_requested versions
          setup_edit_socket(socket, procedure, version)
        end

      {:error, message} ->
        socket
        |> put_flash(:error, message)
        |> push_navigate(to: ~p"/missions/#{mission}/procedures")
    end
  end

  # Sets up the socket for editing a version
  defp setup_edit_socket(socket, procedure, version) do
    sections = V2.list_sections_with_steps(version.id)

    parameter_types =
      ~w(string number integer boolean enum target telemetry_item command duration datetime array)

    execution_mode_options = [
      {"Manual", "manual"},
      {"Assisted", "assisted"},
      {"Automatic", "automatic"}
    ]

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
    |> assign(:execution_mode_options, execution_mode_options)
    |> assign(:show_request_changes_form, false)
    |> assign(:show_submit_form, false)
    |> refresh_version_assigns(version)
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

  def handle_event("save_new_parameter", %{"parameter" => params}, socket) do
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

  def handle_event("save_parameter", %{"index" => index, "parameter" => params}, socket) do
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

  def handle_event("save_settings", %{"settings" => params}, socket) do
    version = socket.assigns.version

    attrs = %{
      execution_mode: parse_execution_mode(params["execution_mode"]),
      allow_hazardous_commands: parse_boolean(params["allow_hazardous_commands"]),
      allow_suggested_edits: parse_boolean(params["allow_suggested_edits"])
    }

    case update_version_settings(version, attrs) do
      {:ok, updated_version} ->
        {:noreply, refresh_version_assigns(socket, updated_version)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
    end
  end

  def handle_event("toggle_submit_form", _params, socket) do
    {:noreply, assign(socket, :show_submit_form, !socket.assigns.show_submit_form)}
  end

  def handle_event("submit_for_review", %{"submit" => %{"note" => note}}, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.submit_for_review(version, user_id, note: note) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> assign(:show_submit_form, false)
         |> put_flash(:info, "Version submitted for review")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit: #{inspect(reason)}")}
    end
  end

  def handle_event("submit_for_review", _params, socket) do
    # Quick submit without note
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.submit_for_review(version, user_id) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> put_flash(:info, "Version submitted for review")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to submit: #{inspect(reason)}")}
    end
  end

  def handle_event("withdraw_submission", _params, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.withdraw_submission(version, user_id) do
      {:ok, updated_version} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> put_flash(:info, "Submission withdrawn")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to withdraw: #{inspect(reason)}")}
    end
  end

  def handle_event("approve_version", _params, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.add_approval(version, user_id, :approved) do
      {:ok, %{version: updated_version}} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> put_flash(:info, "Approval recorded")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to approve: #{inspect(reason)}")}
    end
  end

  def handle_event("toggle_request_changes_form", _params, socket) do
    {:noreply,
     assign(socket, :show_request_changes_form, !socket.assigns.show_request_changes_form)}
  end

  def handle_event("request_changes", %{"request_changes" => %{"body" => body}}, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.add_review(version, user_id, :request_changes, body: body) do
      {:ok, %{version: updated_version}} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> assign(:show_request_changes_form, false)
         |> put_flash(:info, "Changes requested")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to request changes: #{inspect(reason)}")}
    end
  end

  def handle_event("resolve_thread", %{"thread_id" => thread_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Procedures.get_thread(thread_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Thread not found")}

      thread ->
        case Procedures.resolve_thread(thread, user_id) do
          {:ok, _result} ->
            version = Procedures.get_version(socket.assigns.version.id)

            {:noreply,
             socket
             |> refresh_version_assigns(version)
             |> put_flash(:info, "Thread resolved")}

          {:error, :already_resolved} ->
            {:noreply, put_flash(socket, :info, "Thread already resolved")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to resolve: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("resubmit_for_review", %{"resubmit" => %{"note" => note}}, socket) do
    version = socket.assigns.version
    user_id = socket.assigns.current_scope.user.id

    case Procedures.resubmit(version, user_id, note: note) do
      {:ok, %{version: updated_version}} ->
        {:noreply,
         socket
         |> refresh_version_assigns(updated_version)
         |> put_flash(:info, "Version resubmitted for review")}

      {:error, :unresolved_threads} ->
        {:noreply,
         put_flash(socket, :error, "Please resolve all review threads before resubmitting")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to resubmit: #{inspect(reason)}")}
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

  def handle_event(
        "save_section_name",
        %{"id" => section_id, "section" => %{"name" => name}},
        socket
      ) do
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

  def handle_event("save_step", %{"step_id" => step_id, "step" => params}, socket) do
    step = V2.get_step!(step_id)

    attrs = %{
      name: params["name"] || step.name,
      title: params["title"],
      requires_signoff: params["requires_signoff"] == "true",
      on_fail: parse_on_fail(params["on_fail"]),
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
    block_params = Map.get(params, "block", params)
    content = build_content_from_params(block.block_type, block_params)

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
    do: %{"item" => "", "label" => "", "unit" => ""}

  defp default_content_for_type("telemetry_check"),
    do: %{"item" => "", "operator" => "==", "expected" => ""}

  defp default_content_for_type("telemetry_wait"),
    do: %{"item" => "", "operator" => "==", "expected" => "", "timeout_ms" => 30_000}

  defp default_content_for_type("command"),
    do: %{"command_name" => "", "target" => "", "arguments" => %{}, "priority" => 3}

  defp default_content_for_type("command_sequence"),
    do: %{"commands" => []}

  defp default_content_for_type("text_input"),
    do: %{"label" => "", "variable_name" => "", "placeholder" => ""}

  defp default_content_for_type("number_input"),
    do: %{"label" => "", "variable_name" => "", "min" => nil, "max" => nil}

  defp default_content_for_type("select_input"),
    do: %{"label" => "", "variable_name" => "", "options" => []}

  defp default_content_for_type("checkbox_input"),
    do: %{"label" => "", "variable_name" => "", "options" => []}

  defp default_content_for_type("timestamp_input"),
    do: %{"label" => "", "variable_name" => "", "placeholder" => ""}

  defp default_content_for_type("duration_input"),
    do: %{"label" => "", "variable_name" => "", "unit" => "seconds"}

  defp default_content_for_type("attachment_input"),
    do: %{"label" => "", "variable_name" => "", "placeholder" => ""}

  defp default_content_for_type("signature_input"),
    do: %{"label" => "", "variable_name" => "", "placeholder" => ""}

  defp default_content_for_type(_), do: %{}

  # Build content map from form params
  defp build_content_from_params(:text, params), do: %{"markdown" => params["markdown"] || ""}
  defp build_content_from_params(:note, params), do: %{"text" => params["text"] || ""}
  defp build_content_from_params(:caution, params), do: %{"text" => params["text"] || ""}
  defp build_content_from_params(:warning, params), do: %{"text" => params["text"] || ""}

  defp build_content_from_params(:telemetry_value, params) do
    %{
      "item" => params["item"] || "",
      "label" => params["label"] || "",
      "unit" => params["unit"] || ""
    }
  end

  defp build_content_from_params(:telemetry_check, params) do
    %{
      "item" => params["item"] || "",
      "operator" => params["operator"] || "==",
      "expected" => params["expected"] || ""
    }
  end

  defp build_content_from_params(:telemetry_wait, params) do
    %{
      "item" => params["item"] || "",
      "operator" => params["operator"] || "==",
      "expected" => params["expected"] || "",
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

  defp build_content_from_params(:command_sequence, params) do
    commands =
      case params["commands"] do
        nil -> []
        "" -> []
        json when is_binary(json) -> parse_json_args(json)
        list when is_list(list) -> list
      end

    %{"commands" => commands}
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

  defp build_content_from_params(:checkbox_input, params) do
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

  defp build_content_from_params(:timestamp_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "placeholder" => params["placeholder"] || ""
    }
  end

  defp build_content_from_params(:duration_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "unit" => params["unit"] || "seconds"
    }
  end

  defp build_content_from_params(:attachment_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "placeholder" => params["placeholder"] || ""
    }
  end

  defp build_content_from_params(:signature_input, params) do
    %{
      "label" => params["label"] || "",
      "variable_name" => params["variable_name"] || "",
      "placeholder" => params["placeholder"] || ""
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

  defp parse_execution_mode(nil), do: :manual
  defp parse_execution_mode(""), do: :manual
  defp parse_execution_mode("manual"), do: :manual
  defp parse_execution_mode("assisted"), do: :assisted
  defp parse_execution_mode("automatic"), do: :automatic
  defp parse_execution_mode(mode) when is_atom(mode), do: mode
  defp parse_execution_mode(_), do: :manual

  defp parse_on_fail(nil), do: :pause
  defp parse_on_fail("pause"), do: :pause
  defp parse_on_fail("abort"), do: :abort
  defp parse_on_fail("continue"), do: :continue
  defp parse_on_fail(_), do: :pause

  defp parse_boolean(value) when value in [true, "true", "on", 1, "1"], do: true
  defp parse_boolean(_), do: false

  defp status_label(:draft), do: "Draft"
  defp status_label(:in_review), do: "In Review"
  defp status_label(:changes_requested), do: "Changes Requested"
  defp status_label(:approved), do: "Approved"
  defp status_label(:closed), do: "Closed"
  defp status_label(:deprecated), do: "Deprecated"
  defp status_label(status), do: to_string(status)

  defp update_version_settings(version, attrs) do
    version
    |> Ecto.Changeset.change(attrs)
    |> Cadence.Repo.update()
  end

  defp refresh_version_assigns(socket, version) do
    approval_status =
      if version.status in [:in_review, :changes_requested] do
        Procedures.get_approval_status(version)
      else
        nil
      end

    # Load review threads when in review or changes_requested status
    review_threads =
      if version.status in [:in_review, :changes_requested] do
        Procedures.list_threads(version.id)
      else
        []
      end

    # Count unresolved threads
    unresolved_count = Enum.count(review_threads, &(&1.status != :resolved))

    settings_form =
      to_form(
        %{
          "execution_mode" => to_string(version.execution_mode || :manual),
          "allow_hazardous_commands" => version.allow_hazardous_commands,
          "allow_suggested_edits" => version.allow_suggested_edits
        },
        as: :settings
      )

    socket
    |> assign(:version, version)
    |> assign(:settings_form, settings_form)
    |> assign(:approval_status, approval_status)
    |> assign(:review_threads, review_threads)
    |> assign(:unresolved_count, unresolved_count)
    |> assign(:request_changes_form, to_form(%{}, as: :request_changes))
    |> assign(:resubmit_form, to_form(%{}, as: :resubmit))
    |> assign(:submit_form, to_form(%{}, as: :submit))
  end

  defp load_version_for_mission(mission, procedure_id, version_id) do
    case Procedures.get_procedure(procedure_id) do
      %Cadence.Procedures.Procedure{mission_id: mission_id} = procedure
      when mission_id == mission.id ->
        case Procedures.get_version(version_id) do
          %Cadence.Procedures.ProcedureVersion{procedure_id: ^procedure_id} = version ->
            {:ok, procedure, version}

          _ ->
            {:error, "Procedure version not found"}
        end

      _ ->
        {:error, "Procedure not found in this mission"}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Review Threads Panel Component
  # ────────────────────────────────────────────────────────────────────

  attr :threads, :list, required: true
  attr :unresolved_count, :integer, required: true
  attr :resubmit_form, :map, required: true

  defp review_threads_panel(assigns) do
    ~H"""
    <div class="bg-warning/5 border border-warning/20 rounded-md overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center justify-between px-4 py-3 bg-warning/10 border-b border-warning/20">
        <div class="flex items-center gap-2">
          <.icon name="hero-chat-bubble-left-right" class="h-5 w-5 text-warning" />
          <span class="font-semibold text-sm">Review Feedback</span>
          <span class="badge badge-sm badge-warning">{length(@threads)} threads</span>
        </div>
        <%= if @unresolved_count == 0 do %>
          <span class="text-success text-sm flex items-center gap-1">
            <.icon name="hero-check-circle" class="h-4 w-4" /> All resolved
          </span>
        <% end %>
      </div>

      <%!-- Thread List --%>
      <div class="divide-y divide-warning/10 max-h-64 overflow-y-auto">
        <%= for thread <- @threads do %>
          <.thread_item thread={thread} />
        <% end %>
      </div>

      <%!-- Resubmit Section --%>
      <div class="p-4 bg-base-200/50 border-t border-warning/20">
        <%= if @unresolved_count == 0 do %>
          <.form for={@resubmit_form} id="resubmit-form" phx-submit="resubmit_for_review">
            <div class="space-y-2">
              <.input
                type="text"
                field={@resubmit_form[:note]}
                placeholder="Optional: Add a note about your changes..."
              />
              <button type="submit" class="btn btn-sm btn-primary w-full">
                <.icon name="hero-arrow-path" class="h-4 w-4" /> Resubmit for Review
              </button>
            </div>
          </.form>
        <% else %>
          <div class="text-center text-sm text-base-content/60">
            <.icon name="hero-information-circle" class="h-4 w-4 inline" />
            Resolve all threads to resubmit for review
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :thread, :map, required: true

  defp thread_item(assigns) do
    # Get the thread body from the review or first comment
    thread_body = get_thread_body(assigns.thread)
    assigns = assign(assigns, :thread_body, thread_body)

    ~H"""
    <div class={[
      "p-3 flex items-start justify-between gap-3",
      @thread.status == :resolved && "bg-success/5",
      @thread.status != :resolved && "hover:bg-warning/5"
    ]}>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-1">
          <span class="text-sm font-medium">{@thread.author.email}</span>
          <span class="text-xs text-base-content/50">
            {Calendar.strftime(@thread.inserted_at, "%b %d, %H:%M")}
          </span>
          <%= if @thread.status == :resolved do %>
            <span class="badge badge-xs badge-success">Resolved</span>
          <% end %>
        </div>
        <p class="text-sm text-base-content/80 line-clamp-2">{@thread_body}</p>
      </div>
      <%= if @thread.status != :resolved do %>
        <button
          type="button"
          class="btn btn-xs btn-success btn-outline shrink-0"
          phx-click="resolve_thread"
          phx-value-thread_id={@thread.id}
        >
          <.icon name="hero-check" class="h-3 w-3" /> Resolve
        </button>
      <% end %>
    </div>
    """
  end

  defp get_thread_body(thread) do
    cond do
      # First try the review body
      thread.review && thread.review.body ->
        thread.review.body

      # Then try the first comment
      is_list(thread.comments) && length(thread.comments) > 0 ->
        List.first(thread.comments).body

      true ->
        "(No comment)"
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Render
  # ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    parameters = get_parameters(assigns.version)
    assigns = assign(assigns, :parameters, parameters)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="h-[calc(100vh-4rem)] flex flex-col overflow-hidden" id="procedure-editor">
        <!-- Header -->
        <div class="flex flex-col gap-3 px-6 py-4 border-b border-primary/20 bg-surface-raised">
          <div class="flex items-center justify-between">
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
                @version.status == :draft && "badge-ghost",
                @version.status == :approved && "badge-success",
                @version.status == :deprecated && "badge-ghost text-base-content/50",
                @version.status == :in_review && "badge-info",
                @version.status == :changes_requested && "badge-warning"
              ]}>
                {status_label(@version.status)}
              </span>
            </div>
          </div>

          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="text-xs text-base-content/60">
              <%= if @approval_status do %>
                {@approval_status.approved_count}/{@approval_status.required} approvals · {if @approval_status.is_blocked,
                  do: "Blocked",
                  else: "#{@approval_status.pending} pending"}
              <% else %>
                Ready when you are
              <% end %>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <%= if @version.status == :draft do %>
                <button
                  type="button"
                  class="btn btn-sm btn-ghost"
                  phx-click="toggle_submit_form"
                  title="Submit with note"
                >
                  <.icon name="hero-chat-bubble-bottom-center-text" class="h-4 w-4" />
                </button>
                <button
                  type="button"
                  class="btn btn-sm btn-primary"
                  phx-click="submit_for_review"
                >
                  Submit for review
                </button>
              <% end %>
              <%= if @version.status == :in_review do %>
                <.link
                  navigate={
                    ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review"
                  }
                  class="btn btn-sm btn-info gap-1"
                >
                  <.icon name="hero-chat-bubble-left-right" class="h-4 w-4" /> View Review
                </.link>
              <% end %>
              <%= if @version.status == :changes_requested do %>
                <span class="badge badge-warning gap-1">
                  <.icon name="hero-chat-bubble-left-right" class="h-3 w-3" />
                  {@unresolved_count} unresolved
                </span>
                <.link
                  navigate={
                    ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review"
                  }
                  class="btn btn-sm btn-warning btn-outline gap-1"
                >
                  View Feedback
                </.link>
              <% end %>
            </div>
          </div>

          <%!-- Submit with Note Form --%>
          <%= if @show_submit_form do %>
            <div class="bg-primary/5 border border-primary/20 rounded-md p-3">
              <.form for={@submit_form} id="submit-for-review-form" phx-submit="submit_for_review">
                <div class="space-y-2">
                  <.input
                    type="text"
                    field={@submit_form[:note]}
                    label="Add a note for reviewers (optional)"
                    placeholder="What should reviewers focus on?"
                  />
                  <div class="flex justify-end gap-2">
                    <button type="button" class="btn btn-sm btn-ghost" phx-click="toggle_submit_form">
                      Cancel
                    </button>
                    <button type="submit" class="btn btn-sm btn-primary">
                      <.icon name="hero-paper-airplane" class="h-4 w-4" /> Submit for Review
                    </button>
                  </div>
                </div>
              </.form>
            </div>
          <% end %>

          <%!-- In Review Banner --%>
          <%= if @version.status == :in_review do %>
            <div class="bg-info/10 border border-info/20 rounded-md p-3 flex items-center gap-3">
              <.icon name="hero-clock" class="h-5 w-5 text-info" />
              <div class="flex-1">
                <span class="font-medium text-sm">This version is under review</span>
                <span class="text-xs text-base-content/60 block">
                  {@approval_status.approved_count}/{@approval_status.required} approvals
                </span>
              </div>
              <.link
                navigate={
                  ~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@version.id}/review"
                }
                class="btn btn-sm btn-info btn-outline"
              >
                View Review
              </.link>
            </div>
          <% end %>

          <%!-- Review Threads Panel (when changes requested) --%>
          <%= if @version.status == :changes_requested and length(@review_threads) > 0 do %>
            <.review_threads_panel
              threads={@review_threads}
              unresolved_count={@unresolved_count}
              resubmit_form={@resubmit_form}
            />
          <% end %>
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
                  settings_form={@settings_form}
                  execution_mode_options={@execution_mode_options}
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
    </Layouts.app>
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
  attr :settings_form, :map, required: true
  attr :execution_mode_options, :list, required: true

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
              <div class="space-y-3">
                <h3 class="hud-label">Execution Settings</h3>
                <.form for={@settings_form} id="procedure-settings-form" phx-submit="save_settings">
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                    <.input
                      field={@settings_form[:execution_mode]}
                      type="select"
                      label="Execution mode"
                      options={@execution_mode_options}
                    />
                    <div class="space-y-1">
                      <.input
                        field={@settings_form[:allow_hazardous_commands]}
                        type="checkbox"
                        label="Allow hazardous commands"
                      />
                      <.input
                        field={@settings_form[:allow_suggested_edits]}
                        type="checkbox"
                        label="Allow suggested edits"
                      />
                    </div>
                  </div>
                  <div class="flex justify-end">
                    <button type="submit" class="btn btn-sm btn-primary">Save Settings</button>
                  </div>
                </.form>
              </div>

              <div class="hud-divider"></div>

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
    form = to_form(assigns.param, as: :parameter)

    assigns =
      assigns
      |> assign(:event, event)
      |> assign(:cancel_event, cancel_event)
      |> assign(:form, form)

    ~H"""
    <.form
      for={@form}
      id={"parameter-form-#{@index || "new"}"}
      phx-submit={@event}
      class="p-4 bg-surface-elevated hud-border rounded-sm space-y-3"
    >
      <%= if @index do %>
        <input type="hidden" name="index" value={@index} />
      <% end %>

      <div class="grid grid-cols-2 gap-3">
        <.input
          type="text"
          field={@form[:name]}
          label="Name"
          class="input input-bordered input-sm w-full font-mono rounded-sm"
          placeholder="parameter_name"
          required
        />
        <.input
          type="select"
          field={@form[:type]}
          label="Type"
          options={@parameter_types}
          class="select select-bordered select-sm w-full rounded-sm"
        />
      </div>

      <.input
        type="text"
        field={@form[:description]}
        label="Description"
        class="input input-bordered input-sm w-full rounded-sm"
        placeholder="Optional description"
      />

      <div class="flex items-center gap-4">
        <.input
          type="checkbox"
          field={@form[:required]}
          label="Required"
        />
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
    </.form>
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
    assigns =
      assign(assigns, :section_form, to_form(%{"name" => assigns.section.name}, as: :section))

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
              <.form
                for={@section_form}
                id={"section-name-form-#{@section.id}"}
                phx-submit="save_section_name"
                phx-value-id={@section.id}
                class="flex-1"
              >
                <.input
                  type="text"
                  field={@section_form[:name]}
                  id={"section-name-#{@section.id}"}
                  class="input input-sm input-bordered rounded-sm"
                  autofocus
                  phx-blur="cancel_edit_section"
                />
              </.form>
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
    step_form =
      to_form(
        %{
          "name" => assigns.step.name,
          "title" => assigns.step.title || "",
          "requires_signoff" => assigns.step.requires_signoff,
          "on_fail" => to_string(assigns.step.on_fail || :pause),
          "required_roles" => Enum.join(assigns.step.required_roles || [], ", ")
        },
        as: :step
      )

    assigns = assign(assigns, :step_form, step_form)

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
          <.form
            for={@step_form}
            id={"step-form-#{@step.id}"}
            phx-submit="save_step"
            class="space-y-3"
          >
            <input type="hidden" name="step_id" value={@step.id} />

            <div class="grid grid-cols-2 gap-3">
              <.input
                type="text"
                field={@step_form[:name]}
                label="Name"
                class="input input-bordered input-sm w-full font-mono rounded-sm"
                required
              />
              <.input
                type="text"
                field={@step_form[:title]}
                label="Title"
                class="input input-bordered input-sm w-full rounded-sm"
                placeholder="Human-readable title"
              />
            </div>

            <div class="grid grid-cols-3 gap-3">
              <.input
                type="checkbox"
                field={@step_form[:requires_signoff]}
                label="Requires Signoff"
              />
              <.input
                type="select"
                field={@step_form[:on_fail]}
                label="On Failure"
                options={[{"Pause", "pause"}, {"Abort", "abort"}, {"Continue", "continue"}]}
                class="select select-bordered select-sm w-full rounded-sm"
              />
              <.input
                type="text"
                field={@step_form[:required_roles]}
                label="Required Roles"
                class="input input-bordered input-sm w-full rounded-sm"
                placeholder="operator, supervisor"
              />
            </div>

            <div class="flex justify-end gap-3">
              <button type="button" class="btn btn-sm btn-ghost" phx-click="cancel_edit_step">
                Cancel
              </button>
              <button type="submit" class="btn btn-sm btn-primary">Save</button>
            </div>
          </.form>
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
          <.block_type_btn
            step_id={@step_id}
            type="checkbox_input"
            icon="hero-check"
            label="Checkbox"
          />
          <.block_type_btn
            step_id={@step_id}
            type="timestamp_input"
            icon="hero-clock"
            label="Timestamp"
          />
          <.block_type_btn
            step_id={@step_id}
            type="duration_input"
            icon="hero-clock"
            label="Duration"
          />
          <.block_type_btn
            step_id={@step_id}
            type="attachment_input"
            icon="hero-paper-clip"
            label="Attachment"
          />
          <.block_type_btn
            step_id={@step_id}
            type="signature_input"
            icon="hero-pencil"
            label="Signature"
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
          <.block_type_btn
            step_id={@step_id}
            type="command_sequence"
            icon="hero-queue-list"
            label="Command Sequence"
          />
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
    <.form
      for={to_form(%{}, as: :block)}
      id={"block-edit-form-#{@block.id}"}
      phx-submit="save_block"
      class="space-y-4"
    >
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
    </.form>
    """
  end

  attr :block, :map, required: true

  defp block_edit_fields(assigns) do
    operator_options = ["==", "!=", ">", ">=", "<", "<="]

    priority_options = [
      {"Emergency", 0},
      {"Critical", 1},
      {"High", 2},
      {"Normal", 3},
      {"Low", 4},
      {"Background", 5}
    ]

    command_args_text =
      if assigns.block.content["arguments"] && assigns.block.content["arguments"] != %{} do
        Jason.encode!(assigns.block.content["arguments"], pretty: true)
      else
        ""
      end

    command_sequence_text =
      if is_list(assigns.block.content["commands"]) and assigns.block.content["commands"] != [] do
        Jason.encode!(assigns.block.content["commands"], pretty: true)
      else
        ""
      end

    assigns =
      assign(assigns,
        operator_options: operator_options,
        priority_options: priority_options,
        command_args_text: command_args_text,
        command_sequence_text: command_sequence_text
      )

    ~H"""
    <%= case @block.block_type do %>
      <% :text -> %>
        <.input
          type="textarea"
          name="markdown"
          label="Markdown"
          value={@block.content["markdown"] || ""}
          rows="3"
          placeholder="Enter markdown text..."
        />
      <% type when type in [:note, :caution, :warning] -> %>
        <.input
          type="textarea"
          name="text"
          label="Text"
          value={@block.content["text"] || ""}
          rows="3"
          placeholder="Enter text..."
        />
      <% :telemetry_value -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="item"
            label="Telemetry Item"
            value={@block.content["item"] || ""}
            placeholder="target.PACKET.item"
          />
          <div class="grid grid-cols-2 gap-2">
            <.input
              type="text"
              name="label"
              label="Label"
              value={@block.content["label"] || ""}
              placeholder="Label"
            />
            <.input
              type="text"
              name="unit"
              label="Unit"
              value={@block.content["unit"] || ""}
              placeholder="Unit (e.g., V, A, Hz)"
            />
          </div>
        </div>
      <% :telemetry_check -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="item"
            label="Telemetry Item"
            value={@block.content["item"] || ""}
            placeholder="target.PACKET.item"
          />
          <div class="grid grid-cols-2 gap-2">
            <.input
              type="select"
              name="operator"
              label="Operator"
              options={@operator_options}
              value={@block.content["operator"] || "=="}
            />
            <.input
              type="text"
              name="expected"
              label="Expected"
              value={@block.content["expected"] || ""}
              placeholder="Expected value"
            />
          </div>
        </div>
      <% :telemetry_wait -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="item"
            label="Telemetry Item"
            value={@block.content["item"] || ""}
            placeholder="target.PACKET.item"
          />
          <div class="grid grid-cols-3 gap-2">
            <.input
              type="select"
              name="operator"
              label="Operator"
              options={@operator_options}
              value={@block.content["operator"] || "=="}
            />
            <.input
              type="text"
              name="expected"
              label="Expected"
              value={@block.content["expected"] || ""}
              placeholder="Expected value"
            />
            <.input
              type="number"
              name="timeout_ms"
              label="Timeout (ms)"
              value={@block.content["timeout_ms"] || 30_000}
              placeholder="30000"
            />
          </div>
        </div>
      <% :command -> %>
        <div class="space-y-2">
          <div class="grid grid-cols-2 gap-2">
            <.input
              type="text"
              name="command_name"
              label="Command Name"
              value={@block.content["command_name"] || ""}
              placeholder="COMMAND_NAME"
            />
            <.input
              type="text"
              name="target"
              label="Target"
              value={@block.content["target"] || ""}
              placeholder="{{params.target}} or target_id"
            />
          </div>
          <div class="grid grid-cols-4 gap-2">
            <div class="col-span-3">
              <.input
                type="textarea"
                name="arguments"
                label="Arguments (JSON)"
                value={@command_args_text}
                rows="2"
                placeholder='{"arg": "value"}'
              />
            </div>
            <div>
              <.input
                type="select"
                name="priority"
                label="Priority"
                options={@priority_options}
                value={@block.content["priority"] || 3}
              />
            </div>
          </div>
        </div>
      <% :command_sequence -> %>
        <.input
          type="textarea"
          name="commands"
          label="Commands (JSON array)"
          value={@command_sequence_text}
          rows="4"
          placeholder='[{"command_name":"CMD","arguments":{}}]'
        />
      <% :text_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <div class="grid grid-cols-2 gap-2">
            <.input
              type="text"
              name="variable_name"
              label="Variable Name"
              value={@block.content["variable_name"] || ""}
              placeholder="variable_name"
            />
            <.input
              type="text"
              name="placeholder"
              label="Placeholder"
              value={@block.content["placeholder"] || ""}
              placeholder="Placeholder text"
            />
          </div>
        </div>
      <% :number_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <div class="grid grid-cols-3 gap-2">
            <.input
              type="text"
              name="variable_name"
              label="Variable Name"
              value={@block.content["variable_name"] || ""}
              placeholder="variable"
            />
            <.input
              type="number"
              name="min"
              label="Min"
              value={@block.content["min"]}
              placeholder="Min"
            />
            <.input
              type="number"
              name="max"
              label="Max"
              value={@block.content["max"]}
              placeholder="Max"
            />
          </div>
        </div>
      <% :select_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <.input
            type="text"
            name="variable_name"
            label="Variable Name"
            value={@block.content["variable_name"] || ""}
            placeholder="variable_name"
          />
          <.input
            type="textarea"
            name="options"
            label="Options"
            value={Enum.join(@block.content["options"] || [], "\n")}
            rows="3"
            placeholder="One option per line"
          />
        </div>
      <% :checkbox_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <.input
            type="text"
            name="variable_name"
            label="Variable Name"
            value={@block.content["variable_name"] || ""}
            placeholder="variable_name"
          />
          <.input
            type="textarea"
            name="options"
            label="Options (optional)"
            value={Enum.join(@block.content["options"] || [], "\n")}
            rows="3"
            placeholder="One option per line"
          />
        </div>
      <% :timestamp_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <.input
            type="text"
            name="variable_name"
            label="Variable Name"
            value={@block.content["variable_name"] || ""}
            placeholder="variable_name"
          />
          <.input
            type="text"
            name="placeholder"
            label="Placeholder"
            value={@block.content["placeholder"] || ""}
            placeholder="YYYY-MM-DD HH:MM"
          />
        </div>
      <% :duration_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <div class="grid grid-cols-2 gap-2">
            <.input
              type="text"
              name="variable_name"
              label="Variable Name"
              value={@block.content["variable_name"] || ""}
              placeholder="duration_value"
            />
            <.input
              type="text"
              name="unit"
              label="Unit"
              value={@block.content["unit"] || "seconds"}
              placeholder="seconds"
            />
          </div>
        </div>
      <% :attachment_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <.input
            type="text"
            name="variable_name"
            label="Variable Name"
            value={@block.content["variable_name"] || ""}
            placeholder="attachment_ref"
          />
          <.input
            type="text"
            name="placeholder"
            label="Placeholder"
            value={@block.content["placeholder"] || ""}
            placeholder="Paste a URL or file reference"
          />
        </div>
      <% :signature_input -> %>
        <div class="space-y-2">
          <.input
            type="text"
            name="label"
            label="Label"
            value={@block.content["label"] || ""}
            placeholder="Label"
          />
          <.input
            type="text"
            name="variable_name"
            label="Variable Name"
            value={@block.content["variable_name"] || ""}
            placeholder="operator_signature"
          />
          <.input
            type="text"
            name="placeholder"
            label="Placeholder"
            value={@block.content["placeholder"] || ""}
            placeholder="Signed by..."
          />
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
    checkbox_input: "hero-check",
    timestamp_input: "hero-clock",
    duration_input: "hero-clock",
    attachment_input: "hero-paper-clip",
    signature_input: "hero-pencil",
    telemetry_value: "hero-signal",
    telemetry_check: "hero-check-circle",
    telemetry_wait: "hero-clock",
    command: "hero-command-line",
    command_sequence: "hero-queue-list"
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
            <span class="text-primary">{@block.content["item"] || "item.path"}</span>
            <%= if @block.content["unit"] && @block.content["unit"] != "" do %>
              <span class="opacity-60 ml-1">({@block.content["unit"]})</span>
            <% end %>
          </div>
        <% :telemetry_check -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded flex items-center gap-2">
            <span class="text-primary">{@block.content["item"] || "item.path"}</span>
            <span class="opacity-60">{@block.content["operator"] || "=="}</span>
            <span class="text-success">{@block.content["expected"] || "?"}</span>
          </div>
        <% :telemetry_wait -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded">
            <div class="flex items-center gap-2">
              <.icon name="hero-clock" class="h-3 w-3" />
              <span>Wait for</span>
              <span class="text-primary">{@block.content["item"] || "item.path"}</span>
              <span class="opacity-60">{@block.content["operator"] || "=="}</span>
              <span class="text-success">{@block.content["expected"] || "?"}</span>
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
        <% :command_sequence -> %>
          <div class="font-mono text-xs bg-base-200 p-2 rounded">
            {length(@block.content["commands"] || [])} commands
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
        <% :checkbox_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Checkbox"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
            </div>
          </div>
        <% :timestamp_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Timestamp"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
            </div>
          </div>
        <% :duration_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Duration"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"} · {@block.content["unit"] ||
                "seconds"}
            </div>
          </div>
        <% :attachment_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Attachment"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
            </div>
          </div>
        <% :signature_input -> %>
          <div class="space-y-1">
            <div class="font-medium">{@block.content["label"] || "Signature"}</div>
            <div class="text-xs opacity-60">
              Variable: {@block.content["variable_name"] || "unnamed"}
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
