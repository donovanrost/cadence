defmodule Cadence.Reads.SpacecraftDirectory do
  @moduledoc """
  The Setup spacecraft directory: identity, profile binding, routing coverage
  and readiness per spacecraft, a page at a time (#796).

  `ready` means the spacecraft has a SCID, a profile and at least one active,
  enabled routing rule. Fleet geometry and `norad_id` come from spacecraft
  metadata until they become first-class fields. Callers authorize first.
  """

  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Control.WithdrawnPins
  alias Cadence.Reads.FleetStatus
  alias Cadence.Reads.SpacecraftCursor
  alias Cadence.Reads.SpacecraftMetadata
  alias Cadence.Spacecraft
  alias Cadence.Spacecraft.StagedScids
  alias Cadence.SpacecraftStore.Directory
  alias Cadence.SpacecraftType
  alias Cadence.SpacecraftTypeStore

  @default_limit 200
  @max_limit 500
  @max_text 100

  @doc """
  One page of the directory, by name then id after an opaque `cursor`, `limit` 1..#{@max_limit}
  (default #{@default_limit}), optionally narrowed by `q` (name or profile name contains it, or the
  SCID starts with it).

  Returns the rows plus `next_cursor` (nil on the last page) and `telemetry: :ok | :degraded`
  (degraded when the durable history store didn't answer in time, so `last_received_at` comes from
  live values only, api-ops 17deb3c1, and may be missing for spacecraft not heard since the last
  restart). The **first page** (no cursor) also carries the mission's `summary` (counted over the
  whole mission whatever the filter) and the SCID fields; later pages leave them out (#933).
  """
  @spec page(binary(), binary(), keyword()) :: {:ok, map()} | {:error, :invalid_cursor}
  def page(organization_id, mission_id, opts \\ []) do
    size = page_size(Keyword.get(opts, :limit))

    with {:ok, after_key} <- SpacecraftCursor.decode(Keyword.get(opts, :cursor)) do
      profiles = SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id)
      filter = filter(Keyword.get(opts, :q), profiles)

      # One row more than the page says whether another page follows.
      {craft, more} =
        organization_id
        |> Directory.page(mission_id, after_key, size + 1, filter)
        |> Enum.split(size)

      {last_received, telemetry} =
        FleetStatus.last_received_with_status(organization_id, mission_id)

      rules =
        RoutingRuleStore.usable_rule_counts(
          organization_id,
          mission_id,
          Enum.map(craft, & &1.spacecraft_id)
        )

      {:ok,
       %{
         spacecraft:
           build(%{
             spacecraft: craft,
             profiles: profiles,
             rule_counts: rules,
             last_received: last_received,
             # E2 (#546; U109's row badge): one batched read for the page's craft.
             withdrawn:
               WithdrawnPins.for_spacecraft(
                 organization_id,
                 mission_id,
                 Enum.map(craft, & &1.spacecraft_id)
               )
           }),
         next_cursor: if(more != [], do: craft |> List.last() |> cursor_key()),
         telemetry: telemetry
       }
       |> Map.merge(first_page_only(after_key, organization_id, mission_id, last_received))}
    end
  end

  # The whole mission's counts and SCIDs are read once, with the first page (no cursor): a Load
  # more costs the page's own queries, not the mission's counts again (#933).
  defp first_page_only(nil, organization_id, mission_id, last_received),
    do:
      Map.put(
        scids(organization_id, mission_id),
        :summary,
        summary(organization_id, mission_id, last_received)
      )

  defp first_page_only(_after_key, _organization_id, _mission_id, _last_received), do: %{}

  defp page_size(limit) when is_integer(limit) and limit in 1..@max_limit, do: limit
  defp page_size(_limit), do: @default_limit

  defp cursor_key(%Spacecraft{display_name: name, spacecraft_id: id}),
    do: SpacecraftCursor.encode({name, id})

  defp filter(text, profiles) when is_binary(text) do
    text = text |> String.trim() |> String.slice(0, @max_text)
    needle = String.downcase(text)

    %{
      text: text,
      profile_ids:
        for(
          %SpacecraftType{spacecraft_type_id: id, display_name: name} <- profiles,
          needle != "" and String.contains?(String.downcase(name || ""), needle),
          do: id
        )
    }
  end

  defp filter(_text, _profiles), do: %{text: nil, profile_ids: []}

  # The mission's counts for the subtitle, whatever page or filter is shown. "Awaiting first AOS"
  # is the active craft not among those with a telemetry receipt (the cached last-received map).
  defp summary(organization_id, mission_id, last_received) do
    routed = RoutingRuleStore.spacecraft_ids_with_usable_rule(organization_id, mission_id)

    counts =
      Directory.counts(organization_id, mission_id, Map.keys(last_received), routed)

    %{
      total: counts.total,
      profiles: counts.profiles,
      without_profile: counts.without_profile,
      without_scid: counts.without_scid,
      without_routing_rule: counts.without_routing_rule,
      awaiting_first_aos: counts.total - counts.heard
    }
  end

  # S9 (#313, U20): the SCIDs a new spacecraft can't take, and the one to suggest.
  defp scids(organization_id, mission_id) do
    in_use = StagedScids.in_use(organization_id, mission_id, active_staged_ops(mission_id))
    %{scids_in_use: in_use, next_free_scid: StagedScids.next_free(in_use)}
  end

  # The mission's open change set's staged ops, by any author (the read composes configuration;
  # StagedScids stays in the identity context).
  defp active_staged_ops(mission_id) do
    case ChangeSetStore.active(mission_id) do
      nil -> []
      set -> ChangeSetStore.staged_ops(set.change_set_id)
    end
  end

  @doc "Pure builder of one page's rows: `spacecraft`, `profiles`, `rule_counts` (id => usable rules), `last_received`."
  @spec build(map()) :: [map()]
  def build(%{spacecraft: spacecraft} = input) do
    profiles = Map.new(Map.get(input, :profiles, []), &{&1.spacecraft_type_id, &1})
    last_received = Map.get(input, :last_received, %{})

    rule_counts = Map.get(input, :rule_counts, %{})
    withdrawn = Map.get(input, :withdrawn, %{})

    spacecraft
    |> Enum.map(fn %Spacecraft{} = craft ->
      metadata = craft.metadata || %{}
      rule_count = Map.get(rule_counts, craft.spacecraft_id, 0)
      profile = profile(craft, profiles)

      %{
        id: craft.spacecraft_id,
        name: craft.display_name,
        scid: craft.scid,
        norad_id: SpacecraftMetadata.integer(metadata, "norad_id"),
        plane: SpacecraftMetadata.integer(metadata, "plane"),
        slot: SpacecraftMetadata.integer(metadata, "slot"),
        profile: profile,
        routing_rule_count: rule_count,
        ready: not is_nil(craft.scid) and not is_nil(profile) and rule_count > 0,
        last_received_at: Map.get(last_received, craft.spacecraft_id),
        approval_withdrawn: approval_withdrawn(Map.get(withdrawn, craft.spacecraft_id))
      }
    end)
  end

  # The workspace read's shape (`active.approval_withdrawn`), or nil.
  defp approval_withdrawn(nil), do: nil

  defp approval_withdrawn(pin),
    do: %{
      revision_id: pin.revision_id,
      decision: Map.take(pin.decision, [:kind, :by, :at, :reason])
    }

  defp profile(%Spacecraft{spacecraft_type_id: nil}, _profiles), do: nil

  defp profile(%Spacecraft{} = craft, profiles) do
    name =
      case Map.get(profiles, craft.spacecraft_type_id) do
        %SpacecraftType{display_name: name} -> name
        nil -> nil
      end

    %{id: craft.spacecraft_type_id, name: name, version: craft.spacecraft_type_version}
  end
end
