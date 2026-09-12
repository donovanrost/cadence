defmodule Cadence.MissionModels.CommandAuthoringBasis do
  @moduledoc "Bounded immutable command artifacts admitted by an exact active model manifest."

  import Ecto.Query

  alias Cadence.Ids
  alias Cadence.MissionModels.{RevisionRow, RuntimePlanRow}
  alias Cadence.Repo

  @targets ["telemetry", "algorithm", "monitoring", "command"]
  @max_command_document_bytes 8_388_608

  # The caller holds the active-generation lock across this read and any eventual
  # request insert. No revision document or non-command plan document is selected.
  def load(organization_id, mission_id, manifest) when is_map(manifest) do
    with true <- Repo.in_transaction?(),
         {:ok, revision_id} <- Ids.path_segment(value(manifest, :revision_id)),
         true <- hash?(value(manifest, :content_sha256)),
         {:ok, revision} <- revision_identity(organization_id, mission_id, revision_id),
         true <- revision.content_sha256 == value(manifest, :content_sha256),
         {:ok, identities} <- plan_identities(organization_id, mission_id, revision_id),
         true <- exact_manifest?(identities, value(manifest, :plans)),
         {:ok, command_plan} <-
           command_document(organization_id, mission_id, revision_id, identities) do
      {:ok,
       %{
         mission_model_revision_id: revision.revision_id,
         mission_model_content_sha256: revision.content_sha256,
         runtime_plans: %{command: command_plan},
         admitted_plan_identities: identities,
         max_command_document_bytes: @max_command_document_bytes
       }}
    else
      _ -> {:error, :command_authoring_basis_unavailable}
    end
  end

  def load(_, _, _), do: {:error, :command_authoring_basis_unavailable}

  defp revision_identity(organization_id, mission_id, revision_id) do
    RevisionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.revision_id == ^revision_id and row.status == "approved"
    )
    |> select([row], %{revision_id: row.revision_id, content_sha256: row.content_sha256})
    |> lock("FOR SHARE")
    |> Repo.one()
    |> found()
  end

  defp plan_identities(organization_id, mission_id, revision_id) do
    identities =
      RuntimePlanRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> order_by([row], asc: row.target)
      |> limit(5)
      |> select([row], %{
        plan_id: row.plan_id,
        target: row.target,
        status: row.status,
        content_sha256: row.content_sha256,
        target_contract_version: row.target_contract_version
      })
      |> lock("FOR SHARE")
      |> Repo.all()

    if length(identities) == 4 and
         Enum.sort(Enum.map(identities, & &1.target)) == Enum.sort(@targets),
       do: {:ok, identities},
       else: {:error, :incomplete_runtime_manifest}
  end

  defp exact_manifest?(identities, expected) when is_map(expected) do
    Enum.all?(identities, fn identity ->
      case Map.get(expected, identity.target) do
        recorded when is_map(recorded) ->
          identity.status == "ready" and hash?(identity.content_sha256) and
            identity.plan_id == value(recorded, :plan_id) and
            identity.content_sha256 == value(recorded, :content_sha256) and
            identity.target_contract_version == value(recorded, :target_contract_version)

        _ ->
          false
      end
    end)
  end

  defp exact_manifest?(_, _), do: false

  defp command_document(organization_id, mission_id, revision_id, identities) do
    identity = Enum.find(identities, &(&1.target == "command"))

    RuntimePlanRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.revision_id == ^revision_id and row.target == "command" and
        row.plan_id == ^identity.plan_id and
        row.content_sha256 == ^identity.content_sha256 and row.status == "ready"
    )
    |> where(
      [row],
      fragment("octet_length(?::text)", row.plan_document) <= ^@max_command_document_bytes
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :command_plan_missing_or_oversized}
      row -> {:ok, RuntimePlanRow.to_domain(row)}
    end
  end

  defp found(nil), do: {:error, :model_revision_unavailable}
  defp found(value), do: {:ok, value}
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
