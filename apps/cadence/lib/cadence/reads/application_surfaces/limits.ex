defmodule Cadence.Reads.ApplicationSurfaces.Limits do
  @moduledoc "Declarative mission-assurance surface for Limits and Alarming."

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  alias Cadence.Applications.{HostContext, SurfaceDocument, SurfaceQueryRequest}

  alias Cadence.Applications.SurfaceElements.{
    Activity,
    ActivityItem,
    Diagnostic,
    Diagnostics,
    GeneratedForm,
    Stat,
    Table
  }

  alias Cadence.Auth.Scope
  alias Cadence.Extensions.Presentation.FieldDefinition
  alias Cadence.Limits
  alias Cadence.Limits.Event
  alias Cadence.Reads.ApplicationSurfaces.TablePagination
  alias Cadence.Reads.Limits, as: LimitReads

  @impl true
  def load(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: "limits",
          application_version: 1,
          query_id: "cadence.limits.manage",
          query_version: 1,
          params: params
        }
      )
      when is_binary(organization_id) do
    definitions = Limits.list_limit_definitions(mission_id)
    latest_states = LimitReads.latest_states_for_mission(organization_id, mission_id, [])

    with {:ok, page} <- TablePagination.paginate(definitions, params) do
      {:ok,
       %SurfaceDocument{
         title: "Limit definitions",
         description: "Govern mission limit sets as immutable threshold versions.",
         stats: stats(definitions, latest_states),
         form: definition_form(),
         table: definitions_table(page)
       }}
    end
  end

  def load(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id},
        %SurfaceQueryRequest{
          application_key: "limits",
          application_version: 1,
          query_id: "cadence.limits.activity",
          query_version: 1
        }
      )
      when is_binary(organization_id) do
    definitions = Limits.list_limit_definitions(mission_id)
    latest_states = LimitReads.latest_states_for_mission(organization_id, mission_id, [])

    {:ok,
     %SurfaceDocument{
       title: "Current posture",
       description:
         "Inspect the latest evaluated limit state for each mission point, ordered by severity.",
       stats: stats(definitions, latest_states),
       diagnostics: current_departures(latest_states),
       activity: current_posture(latest_states)
     }}
  end

  def load(%Scope{}, %HostContext{}, %SurfaceQueryRequest{}),
    do: {:error, :unsupported_application_surface_query}

  defp stats(definitions, latest_states) do
    red_count = count_states(latest_states, :red)
    yellow_count = count_states(latest_states, :yellow)

    [
      %Stat{
        id: "definition_count",
        label: "Governed definitions",
        value: Integer.to_string(length(definitions)),
        tone: if(definitions == [], do: :attention, else: :ready)
      },
      %Stat{
        id: "red_count",
        label: "Red",
        value: Integer.to_string(red_count),
        tone: if(red_count > 0, do: :blocked, else: :ready)
      },
      %Stat{
        id: "yellow_count",
        label: "Yellow",
        value: Integer.to_string(yellow_count),
        tone: if(yellow_count > 0, do: :attention, else: :ready)
      }
    ]
  end

  defp definition_form do
    %GeneratedForm{
      id: "limit-definition-form",
      title: "Establish a limit set",
      description:
        "Saving the same point and set name creates the next immutable governed version.",
      action_id: "save_limit_definition",
      submit_label: "Save limit definition",
      success_message: "Limit definition saved.",
      fields: [
        %FieldDefinition{
          field: :point_id,
          label: "Canonical point ID",
          type: :reference,
          required: true,
          placeholder: "Select an active or derived telemetry point",
          help: "Resolved from the mission's active decom basis and governed derived telemetry."
        },
        %FieldDefinition{
          field: :limit_set_name,
          label: "Limit set",
          type: :text,
          placeholder: "DEFAULT",
          default: "DEFAULT"
        },
        threshold_field(:red_low, "Red low"),
        threshold_field(:yellow_low, "Yellow low"),
        threshold_field(:yellow_high, "Yellow high"),
        threshold_field(:red_high, "Red high")
      ]
    }
  end

  defp threshold_field(field, label) do
    %FieldDefinition{
      field: field,
      label: label,
      type: :number,
      placeholder: "Optional",
      step: "any"
    }
  end

  defp definitions_table(page) do
    %Table{
      id: "limit-definitions",
      title: "Active definition set",
      description: "The latest immutable version for each governed limit identity.",
      columns: [
        %{key: :point, label: "Point", mono: true},
        %{key: :set, label: "Set", mono: false},
        %{key: :thresholds, label: "Threshold envelope", mono: true},
        %{key: :version, label: "Version", mono: false}
      ],
      page: %{page | items: Enum.map(page.items, &definition_row/1)},
      empty_title: "No limit definitions",
      empty_description: "Establish the first governed threshold envelope above."
    }
  end

  defp definition_row(definition) do
    %{
      id: definition.limit_definition_id,
      point: definition.point_id,
      set: definition.limit_set_name,
      thresholds: format_thresholds(definition.thresholds),
      version: "v#{definition.version}"
    }
  end

  defp format_thresholds(thresholds) do
    [
      {"RL", Map.get(thresholds, "red_low")},
      {"YL", Map.get(thresholds, "yellow_low")},
      {"YH", Map.get(thresholds, "yellow_high")},
      {"RH", Map.get(thresholds, "red_high")}
    ]
    |> Enum.reject(fn {_label, value} -> is_nil(value) end)
    |> Enum.map_join(" · ", fn {label, value} -> "#{label} #{value}" end)
  end

  defp current_posture(latest_states) do
    %Activity{
      id: "limit-current-posture",
      title: "Current mission posture",
      description: "Latest evaluated state per point, ordered by operational severity.",
      items:
        latest_states
        |> Enum.sort_by(&activity_sort_key/1)
        |> Enum.take(12)
        |> Enum.map(&activity_item/1),
      empty_title: "No evaluated limit states",
      empty_description:
        "Current posture appears after canonical or derived telemetry is evaluated."
    }
  end

  defp current_departures(latest_states) do
    items =
      [
        departure_diagnostic(latest_states, :red, :error),
        departure_diagnostic(latest_states, :yellow, :warning)
      ]
      |> Enum.reject(&is_nil/1)

    case items do
      [] ->
        nil

      items ->
        %Diagnostics{
          id: "limit-current-diagnostics",
          title: "Current departures",
          description: "Exceptional mission states summarized before the full point ledger.",
          items: items,
          total_count: length(items)
        }
    end
  end

  defp departure_diagnostic(latest_states, state, severity) do
    count = Enum.count(latest_states, &(&1.normalized_state == state))

    if count > 0 do
      label = state |> Atom.to_string() |> String.upcase()

      %Diagnostic{
        id: "#{state}-departures",
        code: "limits.current.#{state}",
        severity: severity,
        title: "#{String.capitalize(Atom.to_string(state))} limit departures",
        detail:
          "#{count} current #{pluralize(count, "point state", "point states")} require operator review.",
        value: "#{count} #{label}"
      }
    end
  end

  defp activity_item(%Event{} = event) do
    %ActivityItem{
      id: event.limit_event_id,
      title: event.point_name || event.point_id,
      detail:
        Enum.join(
          Enum.reject(
            [event.spacecraft_id || "Mission", event.limit_set_name, state_label(event)],
            &is_nil/1
          ),
          " · "
        ),
      value: format_value(event.evaluated_value),
      timestamp: event.receipt_time && DateTime.to_iso8601(event.receipt_time),
      tone: state_tone(event.normalized_state)
    }
  end

  defp activity_sort_key(%Event{} = event) do
    {-severity(event.normalized_state),
     event.receipt_time && -DateTime.to_unix(event.receipt_time, :microsecond), event.point_id}
  end

  defp severity(:red), do: 3
  defp severity(:yellow), do: 2
  defp severity(:blue), do: 1
  defp severity(:green), do: 0

  defp state_tone(:red), do: :blocked
  defp state_tone(:yellow), do: :attention
  defp state_tone(:green), do: :ready
  defp state_tone(:blue), do: :info

  defp state_label(%Event{limit_state: state}) do
    state |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value), do: inspect(value, limit: 5, printable_limit: 80)

  defp count_states(states, normalized_state) do
    Enum.count(states, &(&1.normalized_state == normalized_state))
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
