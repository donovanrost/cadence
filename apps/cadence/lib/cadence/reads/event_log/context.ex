defmodule Cadence.Reads.EventLog.Context do
  @moduledoc """
  The names a Timeline page's sentences use (`Cadence.Reads.EventLog`): spacecraft always, and
  people, dashboards and stations only when the page's entries mention them.
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Comms.StationRefs
  alias Cadence.Control.ActorRef
  alias Cadence.Dashboards.DocumentStore
  alias Cadence.Reads.EventSentences

  # Names the sentences use: spacecraft always, people and dashboards only when the page has them.
  @spec load(binary(), binary(), list()) :: map()
  def load(organization_id, mission_id, entries) do
    # #472 (#146 C1): a person is named only while an active member of this organization,
    # checked now; anyone else has no entry, and the sentence drops "by" (ux U25).
    users =
      MemberNames.display_names(
        organization_id,
        entries |> Enum.map(&EventSentences.actor_id(&1.actor)) |> Enum.reject(&is_nil/1)
      )

    dashboards =
      if Enum.any?(entries, &String.starts_with?(to_string(&1.kind), "dashboard_")),
        do:
          organization_id
          |> DocumentStore.list_dashboard_summaries(mission_id)
          |> Map.new(&{&1.dashboard_id, &1.name}),
        else: %{}

    # ux U81 §2: a contact_scid_mismatch title names the pass's station by its code.
    stations =
      if Enum.any?(entries, &(to_string(&1.kind) == "contact_scid_mismatch")),
        do: StationRefs.index(organization_id, mission_id),
        else: %{}

    %{
      spacecraft: spacecraft_names(organization_id, mission_id),
      users: users,
      # #488: every actor on the page (people, services, Cadence) through ActorRef, once.
      actors: ActorRef.names(organization_id, Enum.map(entries, &actor_document(&1.actor))),
      dashboards: dashboards,
      stations: stations
    }
  end

  defp actor_document(%{"value" => value}), do: value
  defp actor_document(value), do: value

  defp spacecraft_names(organization_id, mission_id) do
    organization_id
    # Archived craft keep their name (L22): their past events still name them, and a Timeline row
    # never goes out with a known craft unnamed.
    |> Cadence.SpacecraftStore.list_spacecraft(mission_id, include_archived: true)
    |> Map.new(&{&1.spacecraft_id, {&1.display_name, &1.scid}})
  end
end
