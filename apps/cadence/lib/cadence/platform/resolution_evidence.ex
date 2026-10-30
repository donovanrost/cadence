defmodule Cadence.Platform.ResolutionEvidence do
  @moduledoc "Validated evidence for resolving an existing external-operation record."

  @outcomes ~w(accepted not_sent rejected unknown)
  @sources ~w(provider_receipt protocol_ack operator_evidence status_query timeout)
  @fields ~w(resolution_id basis_sha256 outcome source reference observed_at session_ref acceptance_stage provider_response note)

  def new(actor, attrs) when is_map(attrs) do
    with true <- valid_actor?(actor),
         true <- Enum.all?(Map.keys(attrs), &(&1 in @fields)),
         true <- text?(attrs["resolution_id"], 255) and text?(attrs["reference"], 1024),
         true <-
           is_binary(attrs["basis_sha256"]) and
             Regex.match?(~r/^[a-f0-9]{64}$/, attrs["basis_sha256"]),
         true <- attrs["outcome"] in @outcomes and attrs["source"] in @sources,
         true <- attrs["outcome"] == "unknown" or attrs["source"] != "timeout",
         true <-
           attrs["outcome"] != "accepted" or
             attrs["acceptance_stage"] in ~w(provider_acceptance protocol_acceptance),
         true <- is_binary(attrs["observed_at"]),
         {:ok, observed, 0} <- DateTime.from_iso8601(attrs["observed_at"] || ""),
         true <- DateTime.compare(observed, DateTime.utc_now()) != :gt,
         true <- optional_text?(attrs["note"], 2000) and optional_text?(attrs["session_ref"], 255),
         true <- is_nil(attrs["provider_response"]) or is_map(attrs["provider_response"]),
         {:ok, encoded} <- Jason.encode(attrs),
         true <- byte_size(encoded) <= 65_536 do
      {:ok,
       Jason.decode!(encoded)
       |> Map.put("actor", actor)
       |> Map.put("recorded_at", DateTime.to_iso8601(DateTime.utc_now()))}
    else
      _ -> {:error, :invalid_resolution_evidence}
    end
  rescue
    ArgumentError -> {:error, :invalid_resolution_evidence}
  end

  def new(_actor, _attrs), do: {:error, :invalid_resolution_evidence}

  def existing(log, evidence) do
    case Enum.find(
           Map.get(log, "entries", []),
           &(&1["resolution_id"] == evidence["resolution_id"])
         ) do
      nil ->
        :new

      entry ->
        if identity(entry) == identity(evidence),
          do: {:ok, entry},
          else: {:error, :resolution_id_conflict}
    end
  end

  def append(log, evidence, disposition) do
    entries = Map.get(log, "entries", [])

    if length(entries) < 200 do
      {:ok, %{"entries" => entries ++ [Map.put(evidence, "disposition", disposition)]}}
    else
      {:error, :resolution_evidence_limit}
    end
  end

  defp valid_actor?(%{"kind" => kind, "id" => id})
       when kind in ["user", "service"] and is_binary(id),
       do: true

  defp valid_actor?(_actor), do: false

  defp identity(evidence), do: Map.drop(evidence, ["recorded_at", "disposition"])

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.trim(value) != ""

  defp optional_text?(nil, _max), do: true
  defp optional_text?(value, max), do: text?(value, max)
end
