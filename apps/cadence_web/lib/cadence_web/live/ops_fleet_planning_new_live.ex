defmodule CadenceWeb.OpsFleetPlanningNewLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.ContactPlanning.{FleetPlanner, FleetPlanningPolicies}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    policy =
      case FleetPlanningPolicies.fetch_active(
             socket.assigns.current_scope.organization_id,
             socket.assigns.current_mission.mission_id
           ) do
        {:ok, resource, version} -> {resource, version}
        {:error, _reason} -> nil
      end

    form_params = %{
      "horizon_start" => datetime_local(now),
      "horizon_end" => datetime_local(DateTime.add(now, 12, :hour)),
      "include_recurring" => "true"
    }

    {policy_state, preview} = policy_presentation_dtos(policy)

    {:ok,
     socket
     |> assign(:page_title, "Plan Fleet Horizon")
     |> assign(:ops_nav_item, :planning)
     |> assign(:header, header_dto())
     |> assign(:policy_state, policy_state)
     |> assign(:fleet_run_form, policy && fleet_run_form_dto(form_params))
     |> assign(:preview, preview)
     |> assign(:paths, paths_dto(socket.assigns.current_mission))}
  end

  @impl true
  def handle_event("validate-fleet-run", %{"fleet_run" => params}, socket) do
    {:noreply, assign(socket, :fleet_run_form, fleet_run_form_dto(params))}
  end

  def handle_event("create-fleet-run", %{"fleet_run" => params}, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, horizon_start} <- parse_datetime(params["horizon_start"]),
         {:ok, horizon_end} <- parse_datetime(params["horizon_end"]),
         {:ok, run, _refs} <-
           FleetPlanner.start(
             scope,
             mission.mission_id,
             %{
               horizon_start: horizon_start,
               horizon_end: horizon_end,
               trigger_kind: :manual
             },
             materialize_templates: truthy?(params["include_recurring"])
           ) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
       )}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, action_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-fleet-planning-new-component"
        v-component="OpsFleetPlanningNew"
        header={@header}
        policy_state={@policy_state}
        form={@fleet_run_form}
        preview={@preview}
        paths={@paths}
        v-on:validate-fleet-run={JS.push("validate-fleet-run")}
        v-on:create-fleet-run={JS.push("create-fleet-run")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp header_dto do
    %{
      id: "ops-fleet-planning-new-page",
      back: %{label: "Fleet planning", icon: "hero-arrow-left"},
      title: "Plan a mission horizon",
      copy:
        "Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules."
    }
  end

  defp policy_presentation_dtos(nil) do
    {%{
       active: false,
       required: %{
         id: "fleet-planning-new-policy-required",
         icon: "hero-lock-closed",
         title: "An approved policy is required",
         copy:
           "Provider searches remain stopped until an organization administrator approves the fleet boundary.",
         action_label: "Open policy"
       }
     }, nil}
  end

  defp policy_presentation_dtos({_policy, version}) do
    {%{active: true, required: nil}, policy_preview_dto(version)}
  end

  defp policy_preview_dto(version) do
    %{
      id: "fleet-run-policy-preview",
      eyebrow: "Active policy",
      version: "v#{version.version}",
      facts: [
        %{
          term: "Maximum horizon",
          value: "#{div(version.horizon_document["max_horizon_seconds"], 3_600)} hours"
        },
        %{
          term: "Requirement workers",
          value: to_string(version.horizon_document["requirement_concurrency"])
        },
        %{
          term: "Provider searches",
          value: to_string(version.horizon_document["provider_search_concurrency"])
        },
        %{
          term: "Contact ceiling",
          value: to_string(version.budget_quota_document["max_contacts"] || "none")
        },
        %{
          term: "Automation",
          value: humanize(version.automation_repair_document["mode"])
        }
      ],
      details: %{
        id: "fleet-run-policy-progressive-details",
        summary: "Why these settings?",
        copy:
          "Operators choose demand and horizon. Administrators own organizational risk: provider concurrency, cost, quotas, and unattended authority."
      }
    }
  end

  defp fleet_run_form_dto(params) do
    form = to_form(params, as: :fleet_run)

    %{
      id: "fleet-planning-run-form",
      fields: %{
        horizon_start:
          text_field_dto(
            form,
            :horizon_start,
            "fleet-run-horizon-start",
            "Horizon starts (UTC)"
          ),
        horizon_end:
          text_field_dto(
            form,
            :horizon_end,
            "fleet-run-horizon-end",
            "Horizon ends (UTC)"
          ),
        include_recurring: %{
          id: "fleet-run-include-recurring",
          name: "fleet_run[include_recurring]",
          type: "checkbox",
          label: "Materialize recurring Requirement Templates in this horizon",
          value: truthy?(Map.get(form.params, "include_recurring")),
          errors: form_errors(form, :include_recurring)
        }
      },
      snapshot: %{
        label: "Snapshot boundary",
        copy:
          "Starting the run freezes exact Requirement and policy versions. Later edits stop the run closed rather than silently changing its inputs."
      },
      submit: %{
        id: "start-fleet-planning-run",
        label: "Start durable planning run"
      }
    }
  end

  defp text_field_dto(form, field, id, label) do
    %{
      id: id,
      name: "fleet_run[#{field}]",
      type: "datetime-local",
      label: label,
      required: true,
      value: string_form_value(form, field),
      errors: form_errors(form, field)
    }
  end

  defp string_form_value(form, field) do
    case Map.get(form.params, Atom.to_string(field)) do
      value when is_binary(value) -> value
      nil -> ""
      value -> to_string(value)
    end
  end

  defp form_errors(form, field) do
    form.errors
    |> Keyword.get_values(field)
    |> Enum.map(&format_form_error/1)
  end

  defp format_form_error({message, opts}) when is_binary(message) and is_list(opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp format_form_error(message) when is_binary(message), do: message
  defp format_form_error(error), do: inspect(error)

  defp paths_dto(mission) do
    %{
      planning: ~p"/missions/#{mission.mission_id}/ops/planning",
      policy: ~p"/missions/#{mission.mission_id}/ops/planning/policy"
    }
  end

  defp parse_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      {:error, _reason} -> {:error, :fleet_planning_horizon_invalid}
    end
  end

  defp parse_datetime(_value), do: {:error, :fleet_planning_horizon_invalid}

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
  defp truthy?(value), do: value in [true, "true", "on", "1"]
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp action_error(:fleet_planning_run_has_no_requirements),
    do: "No active Contact Requirements overlap this horizon."

  defp action_error(:active_fleet_planning_policy_not_found),
    do: "Approve a fleet planning policy before starting a run."

  defp action_error(:fleet_planning_horizon_exceeds_policy),
    do: "The requested horizon exceeds the active policy boundary."

  defp action_error(_reason), do: "The fleet planning run could not be started."
end
