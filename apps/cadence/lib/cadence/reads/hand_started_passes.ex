defmodule Cadence.Reads.HandStartedPasses do
  @moduledoc """
  Hand-started contacts as rows of the passes read (U78, `booked: false`): a realized contact with
  no scheduled contact (#84). It's a contact, not a pass: there's no reservation, provider, plan or
  AOS/LOS, so those keys are null, `releasable` is false and no pass action applies.

    * `id` and `realized_contact_id`: the contact's id;
    * `state`: its own lifecycle word, `defined | active | stopped | completed`;
    * `starts_at`: when it went live (when it was realized if it never did); `ends_at`: when it
      closed, null while open;
    * `spacecraft`: from its source endpoints, null when they name none or several;
    * `station`: from its `ground_station_ref`;
    * `started_by`: `{kind: user | service | system, id, name}` or null;
    * `not_started` (ux U78): true when it never went live, still `defined` or closed by the
      never-started sweep (`stopped` with `not_started` metadata; `ends_at` is the close).
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{PassWindows, RealizedContact}
  alias Cadence.Control.UplinkReadiness.Groups
  alias Cadence.Reads.ContactStart

  @states ~w(defined active stopped completed)

  @doc "The lifecycle words a hand-started row can carry (the `states` filter accepts them)."
  @spec states() :: [binary()]
  def states, do: @states

  @doc """
  The rows overlapping `[from, to)`: `{rows, truncated?}`. Filters as the passes read's
  (`spacecraft_id`, `states`, `station_refs`, `order`, `limit`, `after`).
  """
  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), map()) :: {[map()], boolean()}
  def load(org, mission, from, to, filters) do
    owners = Groups.spacecraft_by_endpoint(org, mission)

    with {:ok, refs} <- endpoint_refs(owners, Map.get(filters, :spacecraft_id)),
         {:ok, states} <- own_states(Map.get(filters, :states)) do
      {contacts, truncated?} =
        PassWindows.hand_started(org, mission, from, to, window_opts(filters, refs, states))

      {rows(org, mission, contacts, owners), truncated?}
    else
      :none -> {[], false}
    end
  end

  @doc "The matching hand-started contacts in the whole filtered window."
  def count(org, mission, from, to, filters) do
    spacecraft_id = Map.get(filters, :spacecraft_id)
    owners = if spacecraft_id, do: Groups.spacecraft_by_endpoint(org, mission), else: %{}

    with {:ok, refs} <- endpoint_refs(owners, spacecraft_id),
         {:ok, states} <- own_states(Map.get(filters, :states)) do
      PassWindows.hand_count(org, mission, from, to, window_opts(filters, refs, states))
    else
      :none -> 0
    end
  end

  defp window_opts(filters, refs, states) do
    [
      endpoint_refs: refs,
      states: states,
      station_refs: Map.get(filters, :station_refs),
      after: Map.get(filters, :after),
      order: Map.get(filters, :order, :asc),
      limit: Map.get(filters, :limit, 500)
    ]
  end

  @doc "One hand-started contact's row."
  @spec row(binary(), binary(), RealizedContact.t()) :: map()
  def row(org, mission, %RealizedContact{} = contact) do
    [row] = rows(org, mission, [contact], Groups.spacecraft_by_endpoint(org, mission))
    row
  end

  defp rows(_org, _mission, [], _owners), do: []

  defp rows(org, mission, contacts, owners) do
    index = StationRefs.index(org, mission)

    ids = for contact <- contacts, ref <- contact.source_endpoint_refs, id = owners[ref], do: id
    {:ok, crafts} = Cadence.SpacecraftStore.fetch_spacecrafts_in_batches(org, mission, ids)

    people = ContactStart.people(org, contacts)
    Enum.map(contacts, &build(&1, owners, crafts, index, people))
  end

  defp build(%RealizedContact{} = contact, owners, crafts, index, people) do
    spacecraft = spacecraft(contact, owners, crafts)

    %{
      id: contact.realized_contact_id,
      kind: "contact",
      booked: false,
      realized_contact_id: contact.realized_contact_id,
      state: to_string(contact.lifecycle_state),
      pass_phase: nil,
      delivery_state: nil,
      spacecraft_id: spacecraft && spacecraft.id,
      spacecraft: spacecraft,
      station: StationRefs.resolve(text(contact.metadata["ground_station_ref"]), index),
      antenna: nil,
      starts_at: ContactStart.went_live_at(contact),
      ends_at: ContactStart.ended_at(contact),
      started_by: ContactStart.started_by(contact, people),
      not_started: not_started?(contact),
      uplink_capable: nil,
      source: nil,
      max_elevation_deg: nil,
      elevation_source: nil,
      predicted_pass_id: nil,
      cost: nil,
      plan: nil,
      requirement: nil,
      reservation_id: nil,
      scheduled_contact_id: nil,
      booking_evidence: nil,
      attested_by: nil,
      uplink_confirmed: nil,
      attention: nil,
      uplink_readiness: nil,
      provider_revision: nil,
      releasable: false,
      off_plan: nil,
      ended_by: nil
    }
  end

  defp not_started?(%RealizedContact{lifecycle_state: :defined}), do: true

  defp not_started?(%RealizedContact{
         lifecycle_state: :stopped,
         metadata: %{"not_started" => %{}}
       }),
       do: true

  defp not_started?(_contact), do: false

  defp spacecraft(contact, owners, crafts) do
    case contact.source_endpoint_refs |> Enum.map(&owners[&1]) |> Enum.uniq() do
      [id] when is_binary(id) ->
        case Map.get(crafts, id) do
          nil ->
            %{id: id, name: nil, scid: nil}

          %{lifecycle_state: :active} = craft ->
            %{id: id, name: craft.display_name, scid: craft.scid}

          _archived ->
            %{id: id, name: nil, scid: nil}
        end

      _none_or_several ->
        nil
    end
  end

  defp endpoint_refs(_owners, nil), do: {:ok, nil}

  defp endpoint_refs(owners, spacecraft_id) do
    case for({ref, ^spacecraft_id} <- owners, do: ref) do
      [] -> :none
      refs -> {:ok, refs}
    end
  end

  defp own_states(nil), do: {:ok, nil}

  defp own_states(states) do
    case Enum.filter(states, &(&1 in @states)) do
      [] -> :none
      own -> {:ok, own}
    end
  end

  defp text(value) when is_binary(value) and value != "", do: value
  defp text(_value), do: nil
end
