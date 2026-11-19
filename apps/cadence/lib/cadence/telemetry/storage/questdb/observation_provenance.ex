defmodule Cadence.Telemetry.Storage.QuestDB.ObservationProvenance do
  @moduledoc """
  How an observation's provenance is stored on a `telemetry_observations` row, and rebuilt on read
  (DECISIONS #103; docs/apogee/domain/provenance-storage.md, option B).

  The provenance keys that are constants of the mission model, the point or the packet type are
  stored as their own columns (`SYMBOL`s), and the per-packet identity ref as a small text column.
  Copies of the row's own `packet_id` / `evidence_id` columns, and a binding rule id that the model
  rebuilds exactly, aren't stored again: a flag says to rebuild them. Everything else stays in
  `provenance_json` as a residual, which is null when nothing is left.

  Columns are filled only from keys present in the provenance map, and a key is only promoted when
  its value has the column's type; any other value stays in the residual. Reading merges the
  columns back over the decoded residual, so the rebuilt map equals what the JSON held before.
  Rows written before the columns existed have them null (flags false) and decode as before.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope

  @symbol_keys [
    "mission_model_revision_id",
    "runtime_plan_id",
    "producer_kind",
    "producer_id",
    "semantic_id",
    "qualified_name"
  ]

  @columns [
    :mission_model_revision_id,
    :runtime_plan_id,
    :producer_kind,
    :producer_id,
    :semantic_id,
    :qualified_name,
    :identity_ref,
    :binding_rule_derived,
    :packet_refs_derived
  ]

  @doc "The row columns this module fills, in `params/1` order (`provenance_json` is separate)."
  @spec columns() :: [atom()]
  def columns, do: @columns

  @doc "The column names a reader selects to rebuild provenance."
  @spec select_columns() :: [binary()]
  def select_columns, do: Enum.map(@columns, &Atom.to_string/1)

  @doc """
  The values for `columns/0` and the residual `provenance_json` for an envelope:
  `{values, residual_json_or_nil}`.
  """
  @spec params(ObservationEnvelope.t()) :: {[term()], binary() | nil}
  def params(%ObservationEnvelope{} = envelope) do
    provenance = json_term(envelope.provenance || %{})
    {symbols, provenance} = take_symbols(provenance)
    {identity_ref, provenance} = take_identity_ref(provenance)
    {binding_rule_derived, provenance} = take_binding_rule(provenance, symbols, envelope)
    {packet_refs_derived, provenance} = take_packet_refs(provenance, envelope)

    values =
      Enum.map(@symbol_keys, &Map.get(symbols, &1)) ++
        [identity_ref, binding_rule_derived, packet_refs_derived]

    {values, residual_json(provenance)}
  end

  @doc """
  The provenance map for a row read back: the decoded residual with the columns merged over it.
  `get` reads a column's value from the row.
  """
  @spec rebuild(map(), (binary() -> term())) :: map()
  def rebuild(row, get) when is_map(row) and is_function(get, 1) do
    provenance = decode_json_map(get.("provenance_json"))

    symbols =
      for key <- @symbol_keys,
          value <- [get.(key)],
          is_binary(value),
          into: %{},
          do: {key, value}

    provenance
    |> Map.merge(symbols)
    |> put_identity_ref(get.("identity_ref"))
    |> put_packet_refs(get.("packet_refs_derived"), get.("packet_id"), get.("evidence_id"))
    |> put_binding_rule(get.("binding_rule_derived"), symbols, get.("spacecraft_id"))
  end

  @doc """
  The binding rule id the mission model gives a spacecraft's managed runtime endpoint for one
  producer (packet type) in one revision.
  """
  # Stand-in for domain's Cadence.Catalog.binding_rule_id/3 (same format: TelemetryDecom's
  # capability instance id + ":rule" for a `spacecraft_runtime:` source); B swaps to it before
  # hand-off.
  @spec binding_rule_id(binary(), binary(), binary()) :: binary()
  def binding_rule_id(revision_id, spacecraft_id, producer_id)
      when is_binary(revision_id) and is_binary(spacecraft_id) and is_binary(producer_id) do
    "mission_model_telemetry:#{revision_id}:spacecraft_runtime:#{spacecraft_id}:#{producer_id}:rule"
  end

  @doc """
  A term in the form a row stores as JSON: string keys, atoms as strings, timestamps as ISO 8601,
  tuples as lists.
  """
  @spec json_term(term()) :: term()
  def json_term(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def json_term(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  def json_term(%Date{} = date), do: Date.to_iso8601(date)
  def json_term(%Time{} = time), do: Time.to_iso8601(time)
  def json_term(nil), do: nil
  def json_term(atom) when is_atom(atom), do: Atom.to_string(atom)

  def json_term(%{} = map),
    do: Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)

  def json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  def json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> json_term()

  def json_term(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: value

  def json_term(value), do: inspect(value)

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: to_string(key)

  defp take_symbols(provenance) do
    symbols =
      for key <- @symbol_keys,
          value <- [Map.get(provenance, key)],
          is_binary(value),
          into: %{},
          do: {key, value}

    {symbols, Map.drop(provenance, Map.keys(symbols))}
  end

  defp take_identity_ref(%{"identity_ref" => ref} = provenance) when not is_nil(ref),
    do: {Jason.encode!(ref), Map.delete(provenance, "identity_ref")}

  defp take_identity_ref(provenance), do: {nil, provenance}

  # Stored only when it differs from the model's id for this row (a decom config that names another
  # source endpoint), so nothing is ever lost.
  defp take_binding_rule(
         %{"binding_rule_id" => rule_id} = provenance,
         %{"mission_model_revision_id" => revision_id, "producer_id" => producer_id},
         %ObservationEnvelope{spacecraft_id: spacecraft_id}
       )
       when is_binary(rule_id) and is_binary(spacecraft_id) do
    if rule_id == binding_rule_id(revision_id, spacecraft_id, producer_id) do
      {true, Map.delete(provenance, "binding_rule_id")}
    else
      {false, provenance}
    end
  end

  defp take_binding_rule(provenance, _symbols, _envelope), do: {false, provenance}

  defp take_packet_refs(
         %{"packet_id" => packet_id, "evidence_id" => evidence_id} = provenance,
         %ObservationEnvelope{packet_id: packet_id, evidence_id: evidence_id}
       )
       when is_binary(packet_id) and is_binary(evidence_id),
       do: {true, Map.drop(provenance, ["packet_id", "evidence_id"])}

  defp take_packet_refs(provenance, _envelope), do: {false, provenance}

  defp residual_json(provenance) when map_size(provenance) == 0, do: nil
  defp residual_json(provenance), do: Jason.encode!(provenance)

  defp put_identity_ref(provenance, ref) when is_binary(ref) do
    case Jason.decode(ref) do
      {:ok, decoded} -> Map.put(provenance, "identity_ref", decoded)
      {:error, _reason} -> Map.put(provenance, "identity_ref", ref)
    end
  end

  defp put_identity_ref(provenance, _ref), do: provenance

  defp put_packet_refs(provenance, true, packet_id, evidence_id),
    do: Map.merge(provenance, %{"packet_id" => packet_id, "evidence_id" => evidence_id})

  defp put_packet_refs(provenance, _derived, _packet_id, _evidence_id), do: provenance

  defp put_binding_rule(
         provenance,
         true,
         %{"mission_model_revision_id" => revision_id, "producer_id" => producer_id},
         spacecraft_id
       )
       when is_binary(spacecraft_id) do
    Map.put(
      provenance,
      "binding_rule_id",
      binding_rule_id(revision_id, spacecraft_id, producer_id)
    )
  end

  defp put_binding_rule(provenance, _derived, _symbols, _spacecraft_id), do: provenance

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(_value), do: %{}
end
