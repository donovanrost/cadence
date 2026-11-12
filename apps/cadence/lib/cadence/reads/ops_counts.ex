defmodule Cadence.Reads.OpsCounts do
  @moduledoc """
  Small mission counts for the console shell (Ops rail, mobile on-call tabs),
  so the shell doesn't load the whole fleet read for a few numbers.

  Alarm counts come from alarm episodes (both sources). A count the server
  can't compute is `nil`, never `0`.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Control.Alarms
  alias Cadence.Control.Contacts
  alias Cadence.Reads.{Attention, CommandCounts, MissionRuntimeStatus}

  @spec load(Scope.t(), binary()) :: map()
  def load(%Scope{} = scope, mission_id) do
    organization_id = scope.organization_id

    %{
      observed_at: DateTime.utc_now(),
      alarms: alarms(scope, mission_id, Cadence.Limits.list_limit_definitions(mission_id) != []),
      commands:
        commands(
          CommandCounts.load(organization_id, mission_id, scope.user && scope.user.user_id)
        ),
      fleet: %{total: Cadence.SpacecraftStore.fleet_summary(organization_id, mission_id).total},
      contacts:
        contacts(
          Contacts.contact_summary(
            organization_id,
            mission_id,
            DateTime.utc_now()
          )
        ),
      # Open "needs acknowledgment" items (DECISIONS #54): Now's queue header and mobile badge.
      attention: Attention.counts(organization_id, mission_id),
      # Whether the runtime applied its active generation (ux U38 banner); a recorded lookup.
      runtime: MissionRuntimeStatus.status(organization_id, mission_id)
    }
  end

  @doc false
  @spec alarm_counts(map()) :: map()
  def alarm_counts(summary) do
    critical = summary.critical.new + summary.critical.acknowledged
    caution = summary.caution.new + summary.caution.acknowledged

    %{
      active: summary.active,
      critical: critical,
      caution: caution,
      unacknowledged: summary.critical.new + summary.caution.new
    }
  end

  defp alarms(scope, mission_id, limits_configured?) do
    case Alarms.summary(scope, mission_id) do
      {:ok, summary} ->
        summary |> alarm_counts() |> Map.put(:limits_configured, limits_configured?)

      {:error, _reason} ->
        nil
    end
  end

  # From booked reservations; nil when the mission has none (not tracked).
  defp contacts(%{tracked?: false}), do: nil

  defp contacts(%{by_spacecraft: by_spacecraft}),
    do: %{in_contact: Enum.count(by_spacecraft, fn {_id, facts} -> facts.in_contact end)}

  defp commands(counts) do
    %{
      open: counts.queued + counts.in_flight + counts.approval_pending,
      awaiting_viewer: counts.awaiting_viewer
    }
  end
end
