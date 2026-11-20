defmodule CadenceWeb.Console.SpacecraftWorkspaceJSON do
  @moduledoc """
  (B) a spacecraft's configuration workspace, as the console reads it. Contract:
  docs/apogee/api/setup.md §Spacecraft configuration workspace.

  The editable `document` never carries the Telemetry and Commanding switches: change sets are
  their only writer (DECISIONS #109), so they come read-only in `switches`. The host's links and
  hrefs are left out (the console has its own routes).
  """

  @document_keys ~w(catalog_revision_id telemetry_source_endpoint_id handled_apids protocol)
  @switch_keys ~w(telemetry_enabled commanding_enabled)

  @doc "The switch keys a draft may not carry."
  def switch_keys, do: @switch_keys

  def snapshot(s) do
    %{
      spacecraft_id: s.spacecraft_id,
      name: s.name,
      scid: s.scid,
      # #595: the craft's own profile {id, name}, or nil.
      profile: s.profile,
      section: s.section,
      token: s.token,
      saved_version: s.saved_version,
      document: document(s.document),
      # D2 (#543): the composition behind the document's catalog revision, or nil.
      composition: s.composition,
      external_changes: s.external_changes,
      switches: s.switches,
      active: active(s.active),
      review: review(s.review),
      approval: approval(s.approval),
      catalogs: Enum.map(s.catalogs, &catalog/1),
      fleet:
        Enum.map(s.fleet, &Map.take(&1, [:id, :name, :scid, :active_catalog_id, :has_changes])),
      fleet_total: s.fleet_total,
      sources: s.sources,
      presets: s.presets
    }
  end

  @doc "The submit answer: approval_pending (with the request), active, or needs_review."
  def submit_result(%{state: "approval_pending", request_id: id}),
    do: %{state: "approval_pending", request_id: id}

  def submit_result(%{state: "active"} = result),
    do: %{state: "active", execution_id: Map.get(result, :execution_id)}

  # Approved, but the application couldn't be confirmed (the host's 'application_needs_review').
  def submit_result(%{"outcome" => "application_needs_review"}), do: %{state: "needs_review"}

  def packets(%{catalog_id: id, packets: packets}), do: %{catalog_id: id, packets: packets}

  # A stored document predating a key reads it as the empty document does.
  defp document(nil), do: document(%{})

  defp document(doc) do
    %{"catalog_revision_id" => nil, "telemetry_source_endpoint_id" => nil}
    |> Map.merge(%{"handled_apids" => [], "protocol" => nil})
    |> Map.merge(Map.take(doc, @document_keys))
  end

  defp active(nil), do: nil

  defp active(active),
    do: %{
      version: active.version,
      generation: active.generation,
      document: document(active.document),
      composition: active.composition
    }

  # The decision record's fields (subject, separated_from, admin_mode, applied_by) join `review`
  # at the dev reset (DECISIONS #112); readers take them as optional until then.
  defp review(nil), do: nil
  defp review(r), do: Map.take(r, [:id, :state, :requester_id, :version])

  defp approval(a) do
    %{
      requirement: a.requirement,
      policy_token: a.token,
      source: a.source,
      can_request: a.can_request,
      can_review: a.can_review,
      # #595: gates editing (Drafts.save's check); can_request gates Request activation.
      can_save: a.can_save
    }
  end

  defp catalog(c),
    do: Map.take(c, [:id, :name, :label, :number, :declarations, :packets, :commands])
end
