defmodule Cadence.Management.DataBindingPlatformInvariantTest do
  @moduledoc """
  A platform-wide binding (no organization) serves every tenant that falls back to it, so the
  store keeps it platform-wide and lets it point only at a platform-shared source, whatever the
  write path (api-ops' sweep, HIGH-1, 11-15). Boot seeds a default binding only when it's missing,
  so a platform admin's switch survives a restart.
  """
  use Cadence.DataCase, async: false

  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources

  setup do
    suffix = System.unique_integer([:positive])
    persist_mission_scope("org-x-#{suffix}", "mission-x-#{suffix}")

    platform = source!("platform-a-#{suffix}", nil, nil, :shared)
    other_platform = source!("platform-b-#{suffix}", nil, nil, :shared)
    org_owned = source!("org-owned-#{suffix}", "org-x-#{suffix}", nil, :org_isolated)
    org_shared = source!("org-shared-#{suffix}", "org-x-#{suffix}", nil, :shared)

    {:ok, binding} =
      DataSources.persist_data_binding(binding("platform-binding-#{suffix}", platform))

    %{
      suffix: suffix,
      binding: binding,
      platform: platform,
      other_platform: other_platform,
      org_owned: org_owned,
      org_shared: org_shared
    }
  end

  test "a platform binding moves to another platform-shared source", c do
    assert {:ok, %DataBinding{data_source_id: id}} =
             DataSources.persist_data_binding(%{
               c.binding
               | data_source_id: c.other_platform.data_source_id
             })

    assert id == c.other_platform.data_source_id
  end

  test "a platform binding can't point at an organization's source, not even a :shared one", c do
    for source <- [c.org_owned, c.org_shared] do
      assert {:error, :platform_target_required} =
               DataSources.persist_data_binding(%{
                 c.binding
                 | data_source_id: source.data_source_id
               })
    end

    assert {:ok, %DataBinding{data_source_id: id}} =
             DataSources.fetch_data_binding(c.binding.binding_id)

    assert id == c.platform.data_source_id
  end

  test "a platform binding stays platform-wide (no organization takes it over)", c do
    assert {:error, :platform_binding_scope_change} =
             DataSources.persist_data_binding(%{
               c.binding
               | organization_id: "org-x-#{c.suffix}",
                 data_source_id: c.org_owned.data_source_id
             })
  end

  test "an organization's binding can't become platform-wide, even onto a platform source", c do
    own = %{binding("own-binding-#{c.suffix}", c.platform) | organization_id: "org-x-#{c.suffix}"}
    assert {:ok, %DataBinding{}} = DataSources.persist_data_binding(own)

    assert {:error, :platform_binding_scope_change} =
             DataSources.persist_data_binding(%{own | organization_id: nil})

    assert {:ok, %DataBinding{organization_id: "org-x-" <> _}} =
             DataSources.fetch_data_binding(own.binding_id)
  end

  test "disable, enable and supersede can't repoint it to a private source either", c do
    attrs = %{data_source_id: c.org_owned.data_source_id}

    for mutate <- [
          &DataSources.disable_data_binding/2,
          &DataSources.enable_data_binding/2,
          &DataSources.supersede_data_binding/2
        ] do
      assert {:error, :platform_target_required} = mutate.(c.binding.binding_id, attrs)
    end
  end

  test "an organization's own binding may use its own source", c do
    own = %{
      binding("own-binding-#{c.suffix}", c.org_owned)
      | organization_id: "org-x-#{c.suffix}"
    }

    assert {:ok, %DataBinding{}} = DataSources.persist_data_binding(own)
  end

  test "boot seeding doesn't revert a switched default binding", c do
    DataSources.ensure_default_managed_sources!()
    default = DataSources.default_flight_telemetry_binding()
    {:ok, current} = DataSources.fetch_data_binding(default.binding_id)

    assert {:ok, _switched} =
             DataSources.persist_data_binding(%{
               current
               | data_source_id: c.other_platform.data_source_id
             })

    DataSources.ensure_default_managed_sources!()

    assert {:ok, %DataBinding{data_source_id: id}} =
             DataSources.fetch_data_binding(default.binding_id)

    assert id == c.other_platform.data_source_id
  end

  defp source!(id, organization_id, mission_id, isolation_level) do
    {:ok, source} =
      DataSources.persist_data_source(%DataSource{
        data_source_id: id,
        owner: if(organization_id, do: :customer, else: :cadence),
        kind: :managed_tsdb,
        adapter: :telemetry,
        organization_id: organization_id,
        mission_id: mission_id,
        isolation_level: isolation_level,
        capabilities: %{range_scan?: true},
        metadata: %{}
      })

    source
  end

  defp binding(id, source) do
    %DataBinding{
      binding_id: id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: source.data_source_id,
      dataset: "flight",
      priority: 0
    }
  end
end
