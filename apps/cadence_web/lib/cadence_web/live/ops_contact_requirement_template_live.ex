defmodule CadenceWeb.OpsContactRequirementTemplateLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.ContactRequirementTemplates

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    form =
      to_form(
        %{
          "spacecraft_id" => "",
          "schedule_type" => "fixed_interval",
          "anchor_at" => datetime_local(now),
          "time_utc" => Calendar.strftime(now, "%H:%M:%S"),
          "interval_minutes" => "360",
          "window_offset_minutes" => "0",
          "window_duration_minutes" => "30",
          "contact_intent" => "payload_downlink",
          "success_measure" => "minimum_duration",
          "minimum_duration_seconds" => "600",
          "preferred_duration_seconds" => "900",
          "minimum_data_volume_bytes" => "",
          "contact_count" => "1",
          "minimum_separation_seconds" => "0",
          "priority" => "high",
          "approval_mode" => "manual",
          "maximum_occurrences_per_run" => "100",
          "maximum_lookback_hours" => "168",
          "rationale" => ""
        },
        as: :template
      )

    socket =
      socket
      |> assign(:page_title, "Recurring Contact Needs")
      |> assign(:ops_nav_item, :planning)
      |> assign(:organization_admin?, organization_admin?(socket.assigns.current_scope))
      |> assign(:form, form)
      |> stream_configure(:templates, dom_id: &"requirement-template-#{&1.id}")
      |> load_templates()

    {:ok, socket}
  end

  @impl true
  def handle_event("validate-template", %{"template" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :template))}
  end

  def handle_event("create-template", %{"template" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with true <- socket.assigns.organization_admin?,
         {:ok, attrs} <- template_attrs(params),
         {:ok, _template, _version} <-
           ContactRequirementTemplates.create(scope, mission.mission_id, attrs) do
      {:noreply,
       socket
       |> load_templates()
       |> put_flash(:info, "Recurring Requirement Template activated.")}
    else
      false -> {:noreply, put_flash(socket, :error, action_error(:forbidden))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  def handle_event("pause-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :pause)
  end

  def handle_event("activate-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :activate)
  end

  def handle_event("close-template", %{"id" => template_id}, socket) do
    transition_template(socket, template_id, :close)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-contact-requirement-template-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="contact_requirement_template"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp load_templates(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    rows =
      scope.organization_id
      |> ContactRequirementTemplates.list(mission.mission_id)
      |> Enum.map(fn {template, version} ->
        %{
          id: template.contact_requirement_template_id,
          template: template,
          version: version
        }
      end)

    spacecraft_options =
      if socket.assigns.organization_admin? do
        scope.organization_id
        |> Cadence.SpacecraftStore.list_spacecraft(mission.mission_id)
        |> Enum.map(&{&1.display_name, &1.spacecraft_id})
      else
        []
      end

    template_dtos = Enum.map(rows, &template_row_dto(&1, socket.assigns.organization_admin?))

    socket
    |> assign(:template_count, length(rows))
    |> assign(:template_empty?, rows == [])
    |> assign(:template_rows, rows)
    |> assign(:spacecraft_options, spacecraft_options)
    |> stream(:templates, template_dtos, reset: true)
  end

  defp template_row_dto(item, organization_admin?) do
    base = %{
      id: item.id,
      lifecycle: %{
        state: Atom.to_string(item.template.lifecycle_state),
        class: template_state_class(item.template.lifecycle_state)
      },
      version_label: "v#{item.version.version}",
      title:
        "#{item.version.spacecraft_id} · #{humanize(item.version.requirement_document["contact_intent"])}",
      schedule: schedule_sentence(item.version.schedule_document),
      content_sha256: item.version.content_sha256
    }

    if organization_admin? do
      Map.put(base, :actions, template_actions_dto(item))
    else
      base
    end
  end

  defp template_actions_dto(item) do
    state = item.template.lifecycle_state

    %{
      pause:
        if(state == :active,
          do: lifecycle_action_dto("pause-template-#{item.id}", "Pause", "btn btn-ghost btn-xs"),
          else: nil
        ),
      activate:
        if(state == :paused,
          do:
            lifecycle_action_dto(
              "activate-template-#{item.id}",
              "Activate",
              "btn btn-ghost btn-xs text-success"
            ),
          else: nil
        ),
      close:
        if(state != :closed,
          do:
            lifecycle_action_dto(
              "close-template-#{item.id}",
              "Close",
              "btn btn-ghost btn-xs text-error"
            ),
          else: nil
        )
    }
  end

  defp lifecycle_action_dto(id, label, class), do: %{id: id, label: label, class: class}

  defp transition_template(socket, template_id, action) do
    %{current_scope: scope, current_mission: mission, template_rows: rows} = socket.assigns

    with true <- socket.assigns.organization_admin?,
         %{} = item <- Enum.find(rows, &(&1.id == template_id)) do
      result =
        case action do
          :pause ->
            ContactRequirementTemplates.pause(
              scope,
              mission.mission_id,
              template_id,
              item.template.current_version,
              "Paused from recurring demand workspace"
            )

          :activate ->
            ContactRequirementTemplates.activate(
              scope,
              mission.mission_id,
              template_id,
              item.template.current_version,
              "Reactivated from recurring demand workspace"
            )

          :close ->
            ContactRequirementTemplates.close(
              scope,
              mission.mission_id,
              template_id,
              item.template.current_version,
              "Closed from recurring demand workspace"
            )
        end

      case result do
        {:ok, _template} ->
          {:noreply,
           socket
           |> load_templates()
           |> put_flash(:info, "Template lifecycle updated.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, action_error(reason))}
      end
    else
      false -> {:noreply, put_flash(socket, :error, action_error(:forbidden))}
      nil -> {:noreply, put_flash(socket, :error, "Template not found.")}
    end
  end

  defp template_attrs(params) do
    with {:ok, anchor} <- parse_datetime(params["anchor_at"]),
         {:ok, window_offset_minutes} <- integer(params["window_offset_minutes"]),
         {:ok, window_duration_minutes} <- positive_integer(params["window_duration_minutes"]),
         {:ok, minimum_duration} <- optional_positive_integer(params["minimum_duration_seconds"]),
         {:ok, preferred_duration} <-
           optional_positive_integer(params["preferred_duration_seconds"]),
         {:ok, minimum_volume} <- optional_positive_integer(params["minimum_data_volume_bytes"]),
         {:ok, contact_count} <- positive_integer(params["contact_count"]),
         {:ok, separation} <- non_negative_integer(params["minimum_separation_seconds"]),
         {:ok, maximum_occurrences} <- positive_integer(params["maximum_occurrences_per_run"]),
         {:ok, lookback_hours} <- non_negative_integer(params["maximum_lookback_hours"]),
         {:ok, schedule} <-
           schedule_document(
             params,
             anchor,
             window_offset_minutes,
             window_duration_minutes
           ) do
      {:ok,
       %{
         spacecraft_id: params["spacecraft_id"],
         schedule_document: schedule,
         requirement_document: %{
           "service_direction" => "downlink",
           "contact_intent" => params["contact_intent"],
           "success_measure" => params["success_measure"],
           "minimum_duration_seconds" => minimum_duration,
           "preferred_duration_seconds" => preferred_duration,
           "minimum_data_volume_bytes" => minimum_volume,
           "contact_count" => contact_count,
           "minimum_separation_seconds" => separation,
           "priority" => params["priority"],
           "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
           "station_constraints_document" => %{"allowed" => [], "excluded" => []},
           "policy_constraints_document" => %{},
           "approval_policy_document" => %{"mode" => params["approval_mode"]},
           "rationale" => params["rationale"],
           "metadata" => %{}
         },
         catch_up_policy_document: %{
           "maximum_occurrences_per_run" => maximum_occurrences,
           "maximum_lookback_seconds" => lookback_hours * 3_600
         }
       }}
    else
      {:error, _reason} -> {:error, :invalid_requirement_template_form}
    end
  end

  defp schedule_document(params, anchor, offset_minutes, duration_minutes) do
    base = %{
      "type" => params["schedule_type"],
      "anchor_at" => DateTime.to_iso8601(anchor),
      "ends_at" => nil,
      "window_offset_seconds" => offset_minutes * 60,
      "window_duration_seconds" => duration_minutes * 60
    }

    case params["schedule_type"] do
      "fixed_interval" ->
        with {:ok, interval_minutes} <- positive_integer(params["interval_minutes"]) do
          {:ok, Map.put(base, "interval_seconds", interval_minutes * 60)}
        end

      "daily" ->
        case Time.from_iso8601(params["time_utc"] || "") do
          {:ok, time} -> {:ok, Map.put(base, "time_utc", Time.to_iso8601(time))}
          {:error, _reason} -> {:error, :invalid_daily_time}
        end

      _other ->
        {:error, :invalid_schedule_type}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      {:error, _reason} -> {:error, :invalid_datetime}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_datetime}

  defp integer(value) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, :invalid_integer}
    end
  end

  defp positive_integer(value) do
    with {:ok, integer} <- integer(value),
         true <- integer > 0 do
      {:ok, integer}
    else
      _reason -> {:error, :invalid_positive_integer}
    end
  end

  defp non_negative_integer(value) do
    with {:ok, integer} <- integer(value),
         true <- integer >= 0 do
      {:ok, integer}
    else
      _reason -> {:error, :invalid_non_negative_integer}
    end
  end

  defp optional_positive_integer(value) when value in [nil, ""], do: {:ok, nil}
  defp optional_positive_integer(value), do: positive_integer(value)

  defp schedule_sentence(%{"type" => "fixed_interval"} = schedule) do
    "Every #{div(schedule["interval_seconds"], 60)} min · #{div(schedule["window_duration_seconds"], 60)} min window"
  end

  defp schedule_sentence(%{"type" => "daily"} = schedule) do
    "Daily at #{schedule["time_utc"]} · #{div(schedule["window_duration_seconds"], 60)} min window"
  end

  defp organization_admin?(scope) do
    MapSet.member?(scope.capabilities, :organization_admin) or
      MapSet.member?(scope.capabilities, :platform_admin)
  end

  defp template_state_class(:active),
    do:
      "border border-success/35 bg-success/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-success"

  defp template_state_class(:paused),
    do:
      "border border-warning/35 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-warning"

  defp template_state_class(_state),
    do:
      "border border-base-300 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-base-content/45"

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")
  defp action_error(:forbidden), do: "Organization administrator authority is required."
  defp action_error(:invalid_requirement_template_form), do: "Review the schedule and outcome."
  defp action_error(_reason), do: "The recurring Requirement Template could not be changed."
end
