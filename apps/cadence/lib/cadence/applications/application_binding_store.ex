defmodule Cadence.Applications.ApplicationBindingStore do
  @moduledoc """
  Persistence and query helpers for spacecraft-scoped application bindings.
  """

  import Ecto.Query

  alias Cadence.Applications.ApplicationBinding
  alias Cadence.Applications.ApplicationBindingStore.BindingRow
  alias Cadence.Repo

  @type app_key :: atom() | binary()

  @spec upsert(ApplicationBinding.t()) :: {:ok, ApplicationBinding.t()} | {:error, term()}
  def upsert(%ApplicationBinding{} = binding) do
    changeset = BindingRow.changeset(binding)

    upsert_opts = [
      on_conflict:
        {:replace,
         [
           :catalog_revision_id,
           :handled_apids,
           :source_endpoint_id,
           :enabled,
           :metadata,
           :applied_binding_set_id,
           :applied_binding_set_version,
           :applied_at,
           :updated_at
         ]},
      conflict_target: [:organization_id, :mission_id, :spacecraft_id, :application_key]
    ]

    case Repo.insert(changeset, upsert_opts) do
      {:ok, row} -> {:ok, BindingRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch(binary(), binary(), binary(), app_key()) ::
          {:ok, ApplicationBinding.t()} | {:error, :application_binding_not_configured}
  def fetch(organization_id, mission_id, spacecraft_id, application_key)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    case Repo.get_by(BindingRow,
           organization_id: organization_id,
           mission_id: mission_id,
           spacecraft_id: spacecraft_id,
           application_key: normalize_application_key(application_key)
         ) do
      nil -> {:error, :application_binding_not_configured}
      row -> {:ok, BindingRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) :: [ApplicationBinding.t()]
  def list(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) do
    BindingRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter(:spacecraft_id, Keyword.get(opts, :spacecraft_id))
    |> maybe_filter(
      :application_key,
      normalize_optional_application_key(Keyword.get(opts, :application_key))
    )
    |> maybe_filter(:enabled, Keyword.get(opts, :enabled))
    |> order_by([row], asc: row.spacecraft_id, asc: row.application_key)
    |> Repo.all()
    |> Enum.map(&BindingRow.to_domain/1)
  end

  @spec list_apid_conflicts(binary(), binary(), binary(), app_key()) ::
          %{non_neg_integer() => binary()}
  def list_apid_conflicts(organization_id, mission_id, spacecraft_id, excluded_application_key)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    excluded_application_key = normalize_application_key(excluded_application_key)

    organization_id
    |> list(mission_id, spacecraft_id: spacecraft_id, enabled: true)
    |> Enum.reject(&(&1.application_key == excluded_application_key))
    |> Enum.reduce(%{}, fn %ApplicationBinding{} = binding, acc ->
      Enum.reduce(binding.handled_apids, acc, fn apid, apid_acc ->
        Map.put_new(apid_acc, apid, display_application_key(binding.application_key))
      end)
    end)
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp normalize_optional_application_key(nil), do: nil
  defp normalize_optional_application_key(value), do: normalize_application_key(value)

  defp normalize_application_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_application_key(value) when is_binary(value), do: value

  defp display_application_key(application_key) do
    application_key
    |> String.replace("_", " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
