defmodule Cadence.Platform.PreparedSendEvidence do
  @moduledoc "Validated operator/provider evidence for exact prepared frame occurrences."
  alias Cadence.Platform.ResolutionEvidence

  @extra ~w(frames evidence_sha256 provider_evidence_id)
  @base ~w(resolution_id basis_sha256 source reference observed_at session_ref note)
  @outcomes ~w(not_sent rejected protocol_acknowledged outstanding unknown)

  def new(actor, attrs) when is_map(attrs) do
    with true <- Enum.all?(Map.keys(attrs), &(&1 in (@base ++ @extra))),
         true <- text?(attrs["session_ref"]),
         true <- hash?(attrs["evidence_sha256"]),
         true <- is_nil(attrs["provider_evidence_id"]) or text?(attrs["provider_evidence_id"]),
         frames when is_list(frames) <- attrs["frames"],
         true <- length(frames) in 1..256 and Enum.all?(frames, &valid_frame?/1),
         true <- length(Enum.uniq_by(frames, & &1["ordinal"])) == length(frames),
         true <- attrs["source"] != "timeout" or Enum.all?(frames, &(&1["outcome"] == "unknown")),
         {:ok, evidence} <-
           ResolutionEvidence.new(
             actor,
             attrs |> Map.take(@base) |> Map.put("outcome", "unknown")
           ),
         {:ok, encoded} <- Jason.encode(Map.take(attrs, @extra)),
         true <- byte_size(encoded) <= 65_536 do
      {:ok, Map.merge(Map.delete(evidence, "outcome"), Jason.decode!(encoded))}
    else
      _ -> {:error, :invalid_prepared_send_evidence}
    end
  end

  def new(_, _), do: {:error, :invalid_prepared_send_evidence}

  defp valid_frame?(frame) when is_map(frame) do
    Enum.all?(Map.keys(frame), &(&1 in ~w(ordinal frame_id outcome acceptance_stage))) and
      is_integer(frame["ordinal"]) and frame["ordinal"] >= 0 and hash?(frame["frame_id"]) and
      frame["outcome"] in @outcomes and valid_stage?(frame)
  end

  defp valid_frame?(_), do: false

  defp valid_stage?(%{"outcome" => "protocol_acknowledged"} = frame),
    do: frame["acceptance_stage"] == "protocol_acceptance"

  defp valid_stage?(%{"outcome" => "rejected"} = frame),
    do: frame["acceptance_stage"] in ~w(provider_acceptance protocol_acceptance)

  defp valid_stage?(frame), do: is_nil(frame["acceptance_stage"])
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/^[a-f0-9]{64}$/, value)

  defp text?(value),
    do: is_binary(value) and byte_size(value) in 1..255 and String.trim(value) != ""
end
