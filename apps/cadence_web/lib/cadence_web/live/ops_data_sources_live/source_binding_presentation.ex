defmodule CadenceWeb.OpsDataSourcesLive.SourceBindingPresentation do
  @moduledoc """
  Binding-group and readiness presentation for the data sources inventory.
  """

  alias Cadence.Dashboards.SourceReadiness

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.DataSources.{DataBinding, DataSource}

  @spec groups([DataBinding.t()], [DataSource.t()], [map()], [map()], map()) :: [map()]
  def groups(bindings, sources, credentials, health_statuses, readiness_policy) do
    sources_by_id = Map.new(sources, &{&1.data_source_id, &1})
    credentials_by_ref = Map.new(credentials, &{&1.credentials_ref, &1})

    bindings
    |> Enum.map(
      &binding_row(&1, sources_by_id, credentials_by_ref, health_statuses, readiness_policy)
    )
    |> Enum.group_by(&{&1.logical_source_text, &1.realm_text})
    |> Enum.map(fn {{logical_source, realm}, rows} ->
      rows = Enum.sort_by(rows, &{status_sort_key(&1.binding_status), &1.binding.binding_id})

      %{
        id: dom_id("#{logical_source}-#{realm}"),
        logical_source_text: logical_source,
        realm_text: realm,
        group_status: group_status(rows),
        rows: rows
      }
    end)
    |> Enum.sort_by(&{&1.logical_source_text, &1.realm_text})
  end

  @spec readiness_policy_row(map()) :: map()
  def readiness_policy_row(readiness_policy) do
    %{
      policy_id: text(readiness_policy.policy_id),
      block_source_health: joined_text(readiness_policy.block_source_health),
      block_freshness: joined_text(readiness_policy.block_freshness),
      block_connection_test: joined_text(readiness_policy.block_connection_test)
    }
  end

  defp binding_row(
         %DataBinding{} = binding,
         sources_by_id,
         credentials_by_ref,
         health_statuses,
         readiness_policy
       ) do
    source = Map.get(sources_by_id, binding.data_source_id)
    credential = source && Map.get(credentials_by_ref, source.credentials_ref)

    health =
      health_statuses
      |> matching_health_status(binding)
      |> SourceHealth.classify_status(source)

    %{
      binding: binding,
      logical_source_text: text(binding.logical_source),
      realm_text: text(binding.realm),
      binding_status: text(binding.status),
      data_source_id: binding.data_source_id,
      dataset_text: text(binding.dataset),
      priority_text: text(binding.priority),
      version_text: text(binding.binding_version),
      active_from_text: text(binding.active_from),
      active_to_text: text(binding.active_to),
      current_event_id_text: text(binding.current_event_id)
    }
    |> Map.merge(binding_source_fields(source, credential))
    |> Map.merge(binding_health_fields(health))
    |> Map.merge(source_readiness_fields(health, readiness_policy))
  end

  defp binding_source_fields(nil, _credential) do
    %{
      source_status_text: "missing",
      source_kind_text: "missing",
      source_owner_text: "missing",
      source_isolation_text: "missing",
      source_adapter_text: "missing",
      credential_ref_text: "missing"
    }
  end

  defp binding_source_fields(%DataSource{} = source, credential) do
    %{
      source_status_text: text(source.status),
      source_kind_text: text(source.kind),
      source_owner_text: text(source.owner),
      source_isolation_text: text(source.isolation_level),
      source_adapter_text: module_text(source.adapter),
      credential_ref_text: credential_text(source, credential)
    }
  end

  defp binding_health_fields(health) do
    status = Map.get(health, :status)

    %{
      health_status: text(health.source_health),
      health_reason_text: text(health.reason),
      health_observed_at_text: text(health.observed_at),
      health_event_type_text: (status && text(status.event_type)) || text(health.freshness)
    }
  end

  defp source_readiness_fields(health, readiness_policy) do
    readiness = SourceReadiness.classify(health, readiness_policy)

    %{
      source_readiness_status: readiness_status(readiness),
      source_readiness_policy_id: text(readiness.policy_id),
      source_readiness_reason_text: readiness_reason_text(readiness)
    }
  end

  defp matching_health_status(statuses, %DataBinding{} = binding) do
    Enum.find(statuses, fn status ->
      status.logical_source == binding.logical_source and
        status.data_source_id == binding.data_source_id and
        status.source_binding_id == binding.binding_id and
        text(status.realm) == text(binding.realm) and
        status.dataset == binding.dataset
    end)
  end

  defp group_status(rows) do
    statuses = Enum.map(rows, & &1.binding_status)

    cond do
      "active" in statuses -> "active"
      "disabled" in statuses -> "disabled"
      "superseded" in statuses -> "superseded"
      true -> "unknown"
    end
  end

  defp readiness_status(%{blocked?: true}), do: "blocked"
  defp readiness_status(%{blocked?: false}), do: "ready"

  defp readiness_reason_text(%{reasons: []}), do: "none"
  defp readiness_reason_text(%{reasons: reasons}), do: joined_text(reasons)

  defp joined_text(values) when is_list(values), do: Enum.map_join(values, " ", &text/1)

  defp credential_text(%DataSource{credentials_ref: nil}, _credential), do: "none"
  defp credential_text(%DataSource{credentials_ref: ref}, nil), do: "#{ref} (unresolved)"

  defp credential_text(%DataSource{credentials_ref: ref}, credential) do
    "#{ref} / #{text(credential.status)} v#{credential.credential_version}"
  end

  defp status_sort_key("active"), do: 0
  defp status_sort_key("healthy"), do: 0
  defp status_sort_key("degraded"), do: 1
  defp status_sort_key("unknown"), do: 2
  defp status_sort_key("disabled"), do: 3
  defp status_sort_key("superseded"), do: 4
  defp status_sort_key(_status), do: 5

  defp module_text(nil), do: "none"

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp module_text(value), do: text(value)

  defp text(nil), do: "none"
  defp text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)

  defp dom_id(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
