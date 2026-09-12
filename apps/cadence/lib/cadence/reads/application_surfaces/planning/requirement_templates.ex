defmodule Cadence.Reads.ApplicationSurfaces.Planning.RequirementTemplates do
  @moduledoc "Scoped recurring-demand ledger and administrator form for the planning surface."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.ContactRequirementTemplates
  alias Cadence.Reads.ApplicationSurfaces.Planning.Form
  alias Cadence.SpacecraftStore

  def load(%Scope{} = scope, mission) do
    admin? =
      Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) == :ok

    templates = ContactRequirementTemplates.list(scope.organization_id, mission.mission_id)

    rows =
      Enum.map(templates, fn {template, version} ->
        template_row_dto(
          %{id: template.contact_requirement_template_id, template: template, version: version},
          admin?
        )
      end)

    options =
      if admin? do
        scope.organization_id
        |> SpacecraftStore.list_spacecraft(mission.mission_id)
        |> Enum.map(&{&1.display_name, &1.spacecraft_id})
      else
        []
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params = %{
      "spacecraft_id" => "",
      "schedule_type" => "fixed_interval",
      "anchor_at" => Calendar.strftime(now, "%Y-%m-%dT%H:%M:%S"),
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
    }

    %{
      page: page_dto(mission),
      ledger: ledger_dto(length(rows), rows == []),
      authorization: authorization_dto(admin?),
      template_form: template_form_dto(Form.new("template", params), options, admin?),
      templates: rows
    }
  end

  defp page_dto(mission) do
    %{
      id: "ops-requirement-templates-page",
      back: %{
        href: "/missions/#{mission.mission_id}/ops/planning",
        icon: "hero-arrow-left",
        label: "Fleet planning"
      },
      header: %{
        eyebrow: "Recurring demand definition",
        title: "Requirement Templates",
        copy:
          "Define a UTC recurrence once. Each due occurrence materializes exactly one ordinary Contact Requirement with immutable provenance."
      }
    }
  end

  defp ledger_dto(template_count, template_empty?) do
    %{
      eyebrow: "Template ledger",
      copy: "Lifecycle and current immutable schedule version.",
      count: template_count,
      count_label: Integer.to_string(template_count),
      list_id: "requirement-templates",
      stream_empty_id: "requirement-templates-stream-empty",
      empty:
        if(template_empty?,
          do: %{
            id: "requirement-templates-empty",
            icon: "hero-arrow-path-rounded-square",
            title: "No recurring contact needs",
            copy:
              "Use a template for routine downlinks. One-off operational needs remain ordinary Requirements."
          },
          else: nil
        )
    }
  end

  defp authorization_dto(organization_admin?) do
    %{
      organization_admin: organization_admin?,
      admin_required:
        if(organization_admin?,
          do: nil,
          else: %{
            id: "requirement-template-admin-required",
            copy: "Organization administrator authority is required to manage recurring demand."
          }
        )
    }
  end

  defp template_form_dto(_form, _spacecraft_options, false), do: nil

  defp template_form_dto(form, spacecraft_options, true) do
    %{
      panel_id: "requirement-template-editor",
      id: "requirement-template-form",
      header: %{
        eyebrow: "Create recurring need",
        copy: "UTC schedule → ordinary Requirements"
      },
      fields: %{
        spacecraft_id:
          Form.field(
            form,
            :spacecraft_id,
            "template-spacecraft",
            "Spacecraft",
            "select",
            required: true,
            options: Form.options([{"Choose spacecraft", ""} | spacecraft_options])
          ),
        schedule_type:
          Form.field(
            form,
            :schedule_type,
            "template-schedule-type",
            "Schedule",
            "select",
            options: Form.options([{"Fixed interval", "fixed_interval"}, {"Daily UTC", "daily"}])
          ),
        anchor_at:
          Form.field(
            form,
            :anchor_at,
            "template-anchor-at",
            "Starts (UTC)",
            "datetime-local",
            required: true
          ),
        interval_minutes:
          Form.field(
            form,
            :interval_minutes,
            "template-interval-minutes",
            "Every minutes",
            "number",
            required: true,
            min: 1
          ),
        time_utc:
          Form.field(
            form,
            :time_utc,
            "template-time-utc",
            "Daily at UTC",
            "time",
            required: true,
            step: "1"
          ),
        window_offset_minutes:
          Form.field(
            form,
            :window_offset_minutes,
            "template-window-offset",
            "Window offset minutes",
            "number",
            required: true
          ),
        window_duration_minutes:
          Form.field(
            form,
            :window_duration_minutes,
            "template-window-duration",
            "Window duration minutes",
            "number",
            required: true,
            min: 1
          ),
        contact_intent:
          Form.field(
            form,
            :contact_intent,
            "template-contact-intent",
            "Contact intent",
            "text",
            required: true
          ),
        success_measure:
          Form.field(
            form,
            :success_measure,
            "template-success-measure",
            "Success measure",
            "select",
            options:
              Form.options([
                {"Minimum duration", "minimum_duration"},
                {"Minimum data volume", "minimum_data_volume"},
                {"Contact count", "contact_count"},
                {"Any eligible contact", "any_contact"}
              ])
          ),
        minimum_duration_seconds:
          Form.field(
            form,
            :minimum_duration_seconds,
            "template-minimum-duration",
            "Minimum seconds",
            "number",
            min: 1
          ),
        minimum_data_volume_bytes:
          Form.field(
            form,
            :minimum_data_volume_bytes,
            "template-minimum-data-volume",
            "Minimum bytes",
            "number",
            min: 1
          ),
        contact_count:
          Form.field(
            form,
            :contact_count,
            "template-contact-count",
            "Contact count",
            "number",
            required: true,
            min: 1
          ),
        priority:
          Form.field(
            form,
            :priority,
            "template-priority",
            "Priority",
            "select",
            options:
              Form.options([
                {"Critical", "critical"},
                {"High", "high"},
                {"Routine", "routine"}
              ])
          ),
        approval_mode:
          Form.field(
            form,
            :approval_mode,
            "template-approval-mode",
            "Approval",
            "select",
            options:
              Form.options([{"Manual", "manual"}, {"Bounded automatic", "bounded_automatic"}])
          ),
        preferred_duration_seconds:
          Form.field(
            form,
            :preferred_duration_seconds,
            "template-preferred-duration",
            "Preferred seconds",
            "number",
            min: 1
          ),
        minimum_separation_seconds:
          Form.field(
            form,
            :minimum_separation_seconds,
            "template-minimum-separation",
            "Separation seconds",
            "number",
            required: true,
            min: 0
          ),
        maximum_occurrences_per_run:
          Form.field(
            form,
            :maximum_occurrences_per_run,
            "template-max-occurrences",
            "Max per run",
            "number",
            required: true,
            min: 1
          ),
        maximum_lookback_hours:
          Form.field(
            form,
            :maximum_lookback_hours,
            "template-max-lookback",
            "Lookback hours",
            "number",
            required: true,
            min: 0
          ),
        rationale:
          Form.field(
            form,
            :rationale,
            "template-rationale",
            "Operational rationale",
            "textarea",
            required: true
          )
      },
      outcome_details: %{
        id: "requirement-template-outcome-details",
        summary: "Duration and separation preferences"
      },
      catchup_details: %{
        id: "requirement-template-catchup",
        summary: "Catch-up guardrails"
      },
      submit: %{id: "create-requirement-template", label: "Activate template"}
    }
  end

  defp template_row_dto(item, organization_admin?) do
    base = %{
      id: item.id,
      __dom_id: "requirement-template-#{item.id}",
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

  defp schedule_sentence(%{"type" => "fixed_interval"} = schedule) do
    "Every #{duration(schedule["interval_seconds"])} · #{duration(schedule["window_duration_seconds"])} window"
  end

  defp schedule_sentence(%{"type" => "daily"} = schedule) do
    "Daily at #{schedule["time_utc"]} · #{duration(schedule["window_duration_seconds"])} window"
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

  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")

  defp duration(seconds) when rem(seconds, 60) == 0, do: "#{div(seconds, 60)} min"
  defp duration(seconds), do: "#{seconds} sec"
end
