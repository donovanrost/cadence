defmodule Cadence.Notifications.NotificationBuilder do
  @moduledoc """
  Builds notification attributes from outbox events.

  Handles recipient discovery, message templating, and URL generation.
  """

  alias Cadence.Notifications
  alias Cadence.Procedures
  alias Cadence.Repo

  @doc """
  Builds notification attributes from an outbox event.

  Returns `{:ok, [notification_attrs]}` or `{:error, reason}`.
  """
  def build_from_event(event) do
    case event.event_type do
      "procedure_submitted" -> build_procedure_submitted(event)
      "procedure_approved" -> build_procedure_approved(event)
      "procedure_rejected" -> build_procedure_rejected(event)
      "procedure_finalized" -> build_procedure_finalized(event)
      _ -> {:error, :unknown_event_type}
    end
  end

  defp build_procedure_submitted(event) do
    with {:ok, version} <- get_procedure_version(event.aggregate_id) do
      version = Repo.preload(version, [:submitted_by, procedure: :mission])

      recipients =
        Notifications.find_procedure_recipients(
          :submitted,
          version,
          exclude_actor_id: event.actor_id
        )

      procedure = version.procedure
      submitter_name = get_user_display_name(version.submitted_by)

      notifications =
        Enum.map(recipients, fn user_id ->
          %{
            user_id: user_id,
            organization_id: event.organization_id,
            mission_id: event.mission_id,
            type: "procedure_submitted",
            title: "Procedure submitted for review",
            body:
              "#{submitter_name} submitted \"#{procedure.name}\" v#{version.version_number} for review.",
            severity: "info",
            resource_type: "procedure_version",
            resource_id: version.id,
            action_url: "/missions/#{procedure.mission_id}/procedures/#{procedure.id}",
            metadata: %{
              procedure_name: procedure.name,
              version_number: version.version_number,
              submitter_id: version.submitted_by_id
            },
            actor_id: event.actor_id,
            outbox_event_id: event.id
          }
        end)

      {:ok, notifications}
    end
  end

  defp build_procedure_approved(event) do
    with {:ok, version} <- get_procedure_version(event.aggregate_id) do
      version = Repo.preload(version, procedure: :mission)

      recipients = Notifications.find_procedure_recipients(:approved, version)
      procedure = version.procedure
      approver_name = get_actor_name(event.actor_id)

      notifications =
        Enum.map(recipients, fn user_id ->
          %{
            user_id: user_id,
            organization_id: event.organization_id,
            mission_id: event.mission_id,
            type: "procedure_approved",
            title: "Your procedure was approved",
            body: "#{approver_name} approved \"#{procedure.name}\" v#{version.version_number}.",
            severity: "info",
            resource_type: "procedure_version",
            resource_id: version.id,
            action_url: "/missions/#{procedure.mission_id}/procedures/#{procedure.id}",
            metadata: %{
              procedure_name: procedure.name,
              version_number: version.version_number,
              approver_id: event.actor_id
            },
            actor_id: event.actor_id,
            outbox_event_id: event.id
          }
        end)

      {:ok, notifications}
    end
  end

  defp build_procedure_rejected(event) do
    with {:ok, version} <- get_procedure_version(event.aggregate_id) do
      version = Repo.preload(version, procedure: :mission)

      recipients = Notifications.find_procedure_recipients(:rejected, version)
      procedure = version.procedure
      rejector_name = get_actor_name(event.actor_id)
      reason = event.payload["reason"]

      body =
        "#{rejector_name} rejected \"#{procedure.name}\" v#{version.version_number}." <>
          if(reason, do: " Reason: #{reason}", else: "")

      notifications =
        Enum.map(recipients, fn user_id ->
          %{
            user_id: user_id,
            organization_id: event.organization_id,
            mission_id: event.mission_id,
            type: "procedure_rejected",
            title: "Your procedure was rejected",
            body: body,
            severity: "warning",
            resource_type: "procedure_version",
            resource_id: version.id,
            action_url: "/missions/#{procedure.mission_id}/procedures/#{procedure.id}",
            metadata: %{
              procedure_name: procedure.name,
              version_number: version.version_number,
              rejector_id: event.actor_id,
              reason: reason
            },
            actor_id: event.actor_id,
            outbox_event_id: event.id
          }
        end)

      {:ok, notifications}
    end
  end

  defp build_procedure_finalized(event) do
    with {:ok, version} <- get_procedure_version(event.aggregate_id) do
      version = Repo.preload(version, [:approvals, procedure: :mission])

      recipients = Notifications.find_procedure_recipients(:finalized, version)
      procedure = version.procedure

      notifications =
        Enum.map(recipients, fn user_id ->
          %{
            user_id: user_id,
            organization_id: event.organization_id,
            mission_id: event.mission_id,
            type: "procedure_finalized",
            title: "Procedure finalized",
            body:
              "\"#{procedure.name}\" v#{version.version_number} has been approved and is now active.",
            severity: "info",
            resource_type: "procedure_version",
            resource_id: version.id,
            action_url: "/missions/#{procedure.mission_id}/procedures/#{procedure.id}",
            metadata: %{
              procedure_name: procedure.name,
              version_number: version.version_number
            },
            actor_id: event.actor_id,
            outbox_event_id: event.id
          }
        end)

      {:ok, notifications}
    end
  end

  defp get_procedure_version(version_id) do
    case Procedures.get_version(version_id) do
      nil -> {:error, :version_not_found}
      version -> {:ok, version}
    end
  end

  defp get_user_display_name(nil), do: "Someone"
  defp get_user_display_name(%{email: email}), do: email

  defp get_actor_name(nil), do: "Someone"

  defp get_actor_name(actor_id) do
    case Repo.get(Cadence.Accounts.User, actor_id) do
      nil -> "Someone"
      user -> user.email
    end
  end
end
