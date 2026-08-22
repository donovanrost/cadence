defmodule Cadence.Adapters.Contacts.ActionClaimer do
  @moduledoc """
  Production adapter for claiming contact actions via recordables.
  """

  @behaviour Cadence.Ports.Contacts.ActionClaimer

  alias Cadence.Buckets
  alias Cadence.Contacts.ContactCommandAction
  alias Cadence.Recordings
  alias Cadence.Recordings.Recordables.ContactActionDispatched
  alias Cadence.Time, as: CadenceTime

  @impl true
  def claim(%ContactCommandAction{} = action, context) do
    organization_id = Map.get(context, :organization_id)
    mission_id = Map.get(context, :mission_id)
    actor_id = Map.get(context, :actor_id)

    bucket_id =
      Map.get(context, :bucket_id) ||
        Buckets.get_or_create_mission_bucket!(organization_id, mission_id).id

    recordable_attrs = %{
      mission_id: mission_id,
      contact_id: action.contact_id,
      contact_action_id: action.id,
      gate: to_string(action.gate),
      command_ref: action.command_ref || %{},
      details: Map.get(action, :metadata, %{})
    }

    recording_attrs = %{
      organization_id: organization_id,
      mission_id: mission_id,
      bucket_id: bucket_id,
      aggregate_id: action.id,
      actor_id: actor_id,
      timestamp: CadenceTime.now()
    }

    case Recordings.create(ContactActionDispatched, recordable_attrs, recording_attrs) do
      {:ok, _} ->
        :ok

      {:error, :recordable, changeset, _changes} ->
        if already_claimed?(changeset) do
          {:error, :already_claimed}
        else
          {:error, changeset}
        end

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp already_claimed?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
      field == :contact_action_id and opts[:constraint] == :unique
    end)
  end
end
