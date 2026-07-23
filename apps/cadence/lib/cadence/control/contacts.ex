defmodule Cadence.Control.Contacts do
  @moduledoc "Control-plane executor for exact realized Contact runtime handoffs."

  alias Cadence.Contacts.RealizedContact
  alias Cadence.Runtime.Contacts, as: RuntimeContacts
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  @spec start_realized_contact(RealizedContact.t()) :: {:ok, pid()} | {:error, term()}
  def start_realized_contact(%RealizedContact{} = realized_contact) do
    with {:ok, %RealizedContactRuntimeSpec{} = spec} <- runtime_spec(realized_contact) do
      RuntimeContacts.start(spec)
    end
  end

  @spec stop_realized_contact(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact(mission_id, realized_contact_id),
    do: RuntimeContacts.stop(mission_id, realized_contact_id)

  @spec stop_realized_contact_sync(binary(), binary()) :: :ok | {:error, term()}
  def stop_realized_contact_sync(mission_id, realized_contact_id),
    do: RuntimeContacts.stop_sync(mission_id, realized_contact_id)

  @spec realized_contact_running?(binary(), binary()) :: boolean()
  def realized_contact_running?(mission_id, realized_contact_id),
    do: RuntimeContacts.running?(mission_id, realized_contact_id)

  @spec realized_contact_snapshot(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def realized_contact_snapshot(mission_id, realized_contact_id),
    do: RuntimeContacts.snapshot(mission_id, realized_contact_id)

  defp runtime_spec(realized_contact) do
    RealizedContactRuntimeSpec.new(%{
      runtime_spec_id: "realized_contact_runtime:#{realized_contact.realized_contact_id}",
      generation: 1,
      realized_contact_id: realized_contact.realized_contact_id,
      organization_id: realized_contact.organization_id,
      mission_id: realized_contact.mission_id,
      scheduled_contact_id: realized_contact.scheduled_contact_id,
      source_endpoint_refs: realized_contact.source_endpoint_refs,
      contact_intents: realized_contact.contact_intents,
      paths: realized_contact.paths,
      clock_mode: realized_contact.clock_mode,
      initial_time: realized_contact.initial_time,
      metadata: realized_contact.metadata
    })
  end
end
