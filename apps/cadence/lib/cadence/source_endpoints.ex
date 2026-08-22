defmodule Cadence.SourceEndpoints do
  @moduledoc """
  Persistence and ingress-resolution boundary for mission-owned source
  endpoints.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints.{SourceEndpoint, SourceEndpointRow}
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @spec persist_source_endpoint(binary(), SourceEndpoint.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def persist_source_endpoint(organization_id, %SourceEndpoint{} = source_endpoint)
      when is_binary(organization_id) do
    with {:ok, scoped_source_endpoint} <-
           put_organization_scope(source_endpoint, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_source_endpoint.organization_id,
             scoped_source_endpoint.mission_id
           ),
         :ok <- validate_spacecraft_reference(scoped_source_endpoint),
         {:ok, _row} <-
           Repo.insert(SourceEndpointRow.changeset(scoped_source_endpoint),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :source_endpoint_id]
           ) do
      {:ok, scoped_source_endpoint}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec persist_source_endpoint(SourceEndpoint.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def persist_source_endpoint(%SourceEndpoint{} = source_endpoint) do
    with :ok <- validate_spacecraft_reference(source_endpoint) do
      case Repo.insert(SourceEndpointRow.changeset(source_endpoint),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :source_endpoint_id]
           ) do
        {:ok, %SourceEndpointRow{} = row} ->
          {:ok, SourceEndpointRow.to_domain(row)}

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec fetch_source_endpoint(binary(), binary()) :: {:ok, SourceEndpoint.t()} | {:error, term()}
  def fetch_source_endpoint(mission_id, source_endpoint_id)
      when is_binary(mission_id) and is_binary(source_endpoint_id) do
    case Repo.get_by(SourceEndpointRow,
           mission_id: mission_id,
           source_endpoint_id: source_endpoint_id
         ) do
      nil -> {:error, :source_endpoint_not_found}
      %SourceEndpointRow{} = row -> {:ok, SourceEndpointRow.to_domain(row)}
    end
  end

  @spec fetch_source_endpoint(binary(), binary(), binary()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def fetch_source_endpoint(organization_id, mission_id, source_endpoint_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(source_endpoint_id) do
    case Repo.get_by(SourceEndpointRow,
           organization_id: organization_id,
           mission_id: mission_id,
           source_endpoint_id: source_endpoint_id
         ) do
      nil -> {:error, :source_endpoint_not_found}
      %SourceEndpointRow{} = row -> {:ok, SourceEndpointRow.to_domain(row)}
    end
  end

  @spec list_source_endpoints(binary()) :: [SourceEndpoint.t()]
  def list_source_endpoints(mission_id) when is_binary(mission_id) do
    list_source_endpoints(mission_id, [])
  end

  @spec list_source_endpoints(binary(), keyword()) :: [SourceEndpoint.t()]
  def list_source_endpoints(mission_id, opts) when is_binary(mission_id) and is_list(opts) do
    SourceEndpointRow
    |> where([row], row.mission_id == ^mission_id)
    |> maybe_filter_spacecraft(Keyword.get(opts, :spacecraft_id))
    |> order_by([row], asc: row.source_endpoint_id)
    |> Repo.all()
    |> Enum.map(&SourceEndpointRow.to_domain/1)
  end

  @spec list_source_endpoints(binary(), binary()) :: [SourceEndpoint.t()]
  def list_source_endpoints(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    list_source_endpoints(organization_id, mission_id, [])
  end

  @spec list_source_endpoints(binary(), binary(), keyword()) :: [SourceEndpoint.t()]
  def list_source_endpoints(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    SourceEndpointRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_spacecraft(Keyword.get(opts, :spacecraft_id))
    |> order_by([row], asc: row.source_endpoint_id)
    |> Repo.all()
    |> Enum.map(&SourceEndpointRow.to_domain/1)
  end

  @spec ensure_managed_source_endpoint(binary(), Spacecraft.t()) ::
          {:ok, SourceEndpoint.t()} | {:error, term()}
  def ensure_managed_source_endpoint(organization_id, %Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    source_endpoint_id = managed_source_endpoint_id(spacecraft.spacecraft_id)

    case Repo.get_by(SourceEndpointRow,
           organization_id: organization_id,
           mission_id: spacecraft.mission_id,
           source_endpoint_id: source_endpoint_id
         ) do
      %SourceEndpointRow{} = row ->
        update_managed_source_endpoint(row, organization_id, spacecraft, source_endpoint_id)

      nil ->
        persist_managed_source_endpoint(organization_id, spacecraft, source_endpoint_id)
    end
  end

  @spec resolve_raw_evidence(RawEvidence.t()) :: {:ok, RawEvidence.t()} | {:error, term()}
  def resolve_raw_evidence(
        %RawEvidence{
          source_endpoint_ref: source_endpoint_ref,
          spacecraft_id: spacecraft_id
        } = raw_evidence
      )
      when is_binary(source_endpoint_ref) and source_endpoint_ref != "" and
             is_binary(spacecraft_id) and spacecraft_id != "" do
    {:ok, raw_evidence}
  end

  def resolve_raw_evidence(%RawEvidence{source_endpoint_ref: source_endpoint_ref} = raw_evidence)
      when is_binary(source_endpoint_ref) and source_endpoint_ref != "" do
    with {:ok, %SourceEndpoint{} = source_endpoint} <-
           fetch_source_endpoint(raw_evidence.mission_id, source_endpoint_ref) do
      {:ok, apply_source_endpoint(raw_evidence, source_endpoint)}
    end
  end

  def resolve_raw_evidence(%RawEvidence{} = raw_evidence) do
    case resolve_source_endpoint(raw_evidence) do
      {:ok, nil} ->
        {:ok, raw_evidence}

      {:ok, %SourceEndpoint{} = source_endpoint} ->
        {:ok, apply_source_endpoint(raw_evidence, source_endpoint)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_source_endpoint(
         %RawEvidence{
           mission_id: mission_id,
           protocol_family: protocol_family,
           raw: raw
         } = raw_evidence
       )
       when protocol_family in [:tm, :tm_transfer_frame] and is_binary(raw) and
              byte_size(raw) >= 2 do
    with {:ok, scid} <- transfer_frame_scid(raw) do
      case match_source_endpoints(mission_id, scid: scid) do
        {:ok, nil} -> resolve_source_ref_or_spacecraft(raw_evidence)
        result -> result
      end
    end
  end

  defp resolve_source_endpoint(%RawEvidence{
         mission_id: mission_id,
         source_ref: source_ref,
         spacecraft_id: spacecraft_id
       })
       when is_binary(source_ref) and source_ref != "" do
    resolve_source_ref_or_spacecraft(mission_id, source_ref, spacecraft_id)
  end

  defp resolve_source_endpoint(%RawEvidence{mission_id: mission_id, spacecraft_id: spacecraft_id})
       when is_binary(spacecraft_id) and spacecraft_id != "" do
    match_source_endpoints(mission_id, spacecraft_id: spacecraft_id)
  end

  defp resolve_source_endpoint(%RawEvidence{}), do: {:ok, nil}

  defp resolve_source_ref_or_spacecraft(%RawEvidence{
         mission_id: mission_id,
         source_ref: source_ref,
         spacecraft_id: spacecraft_id
       })
       when is_binary(source_ref) and source_ref != "" do
    resolve_source_ref_or_spacecraft(mission_id, source_ref, spacecraft_id)
  end

  defp resolve_source_ref_or_spacecraft(%RawEvidence{
         mission_id: mission_id,
         spacecraft_id: spacecraft_id
       })
       when is_binary(spacecraft_id) and spacecraft_id != "" do
    match_source_endpoints(mission_id, spacecraft_id: spacecraft_id)
  end

  defp resolve_source_ref_or_spacecraft(%RawEvidence{}), do: {:ok, nil}

  defp resolve_source_ref_or_spacecraft(mission_id, source_ref, spacecraft_id) do
    case match_source_endpoints(mission_id, source_ref: source_ref) do
      {:ok, %SourceEndpoint{} = source_endpoint} ->
        {:ok, source_endpoint}

      {:ok, nil} when is_binary(spacecraft_id) and spacecraft_id != "" ->
        match_source_endpoints(mission_id, spacecraft_id: spacecraft_id)

      {:ok, nil} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp match_source_endpoints(mission_id, criteria)
       when is_binary(mission_id) and is_list(criteria) do
    query =
      Enum.reduce(
        criteria,
        from(row in SourceEndpointRow, where: row.mission_id == ^mission_id),
        fn
          {:source_ref, source_ref}, query ->
            where(query, [row], row.source_ref == ^source_ref)

          {:spacecraft_id, spacecraft_id}, query ->
            where(query, [row], row.spacecraft_id == ^spacecraft_id)

          {:scid, scid}, query ->
            where(query, [row], row.scid == ^scid)
        end
      )

    case Repo.all(query) do
      [] ->
        {:ok, nil}

      [%SourceEndpointRow{} = row] ->
        {:ok, SourceEndpointRow.to_domain(row)}

      rows ->
        {:error,
         {:ambiguous_source_endpoint_resolution, Enum.map(rows, & &1.source_endpoint_id),
          criteria}}
    end
  end

  defp apply_source_endpoint(%RawEvidence{} = raw_evidence, %SourceEndpoint{} = source_endpoint) do
    %RawEvidence{
      raw_evidence
      | source_endpoint_ref: source_endpoint.source_endpoint_id,
        spacecraft_id: raw_evidence.spacecraft_id || source_endpoint.spacecraft_id
    }
  end

  defp transfer_frame_scid(<<_version::2, scid::10, _rest::bitstring>>), do: {:ok, scid}
  defp transfer_frame_scid(_raw), do: {:ok, nil}

  defp put_organization_scope(%SourceEndpoint{} = source_endpoint, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case source_endpoint.organization_id do
      nil ->
        {:ok, %SourceEndpoint{source_endpoint | organization_id: organization_id}}

      ^organization_id ->
        {:ok, source_endpoint}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          source_endpoint.mission_id}}
    end
  end

  defp validate_spacecraft_reference(%SourceEndpoint{spacecraft_id: nil}), do: :ok
  defp validate_spacecraft_reference(%SourceEndpoint{spacecraft_id: ""}), do: :ok

  defp validate_spacecraft_reference(%SourceEndpoint{} = source_endpoint) do
    case source_endpoint.organization_id do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        case SpacecraftStore.fetch_spacecraft(
               organization_id,
               source_endpoint.mission_id,
               source_endpoint.spacecraft_id
             ) do
          {:ok, _spacecraft} -> :ok
          {:error, :spacecraft_not_found} -> {:error, :spacecraft_not_found}
        end

      _other ->
        case SpacecraftStore.fetch_spacecraft(
               source_endpoint.mission_id,
               source_endpoint.spacecraft_id
             ) do
          {:ok, _spacecraft} -> :ok
          {:error, :spacecraft_not_found} -> {:error, :spacecraft_not_found}
        end
    end
  end

  defp managed_source_endpoint_id(spacecraft_id), do: "spacecraft_runtime:" <> spacecraft_id

  defp update_managed_source_endpoint(
         %SourceEndpointRow{} = row,
         organization_id,
         spacecraft,
         source_endpoint_id
       ) do
    source_endpoint =
      managed_source_endpoint(
        organization_id,
        spacecraft,
        source_endpoint_id,
        SourceEndpointRow.to_domain(row).metadata
      )

    case row
         |> SourceEndpointRow.update_changeset(source_endpoint)
         |> Repo.update() do
      {:ok, %SourceEndpointRow{} = updated_row} -> {:ok, SourceEndpointRow.to_domain(updated_row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_managed_source_endpoint(organization_id, spacecraft, source_endpoint_id) do
    source_endpoint =
      managed_source_endpoint(organization_id, spacecraft, source_endpoint_id, %{})

    case Repo.insert(SourceEndpointRow.changeset(source_endpoint),
           on_conflict: :nothing,
           conflict_target: [:mission_id, :source_endpoint_id]
         ) do
      {:ok, %SourceEndpointRow{} = row} -> {:ok, SourceEndpointRow.to_domain(row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp managed_source_endpoint(organization_id, spacecraft, source_endpoint_id, metadata) do
    SourceEndpoint.new(%{
      source_endpoint_id: source_endpoint_id,
      organization_id: organization_id,
      mission_id: spacecraft.mission_id,
      spacecraft_id: spacecraft.spacecraft_id,
      scid: spacecraft.scid,
      display_name: spacecraft.display_name,
      metadata: Map.put(metadata || %{}, "managed_by", "spacecraft")
    })
  end

  defp maybe_filter_spacecraft(query, nil), do: query
  defp maybe_filter_spacecraft(query, ""), do: query

  defp maybe_filter_spacecraft(query, spacecraft_id) when is_binary(spacecraft_id) do
    where(query, [row], row.spacecraft_id == ^spacecraft_id)
  end
end
