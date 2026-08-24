defmodule CadenceWeb.OpsNavTestSupport do
  @moduledoc false

  import ExUnit.Assertions

  def ops_nav_vue(renderable) do
    vue = LiveVue.Test.get_vue(renderable, id: "ops-nav-rail-component")
    prop_keys = vue.props |> Map.keys() |> Enum.sort()

    assert vue.component == "OpsNavRail"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}
    assert prop_keys == ~w(dashboard_groups empty_state groups new_dashboard)
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue
  end

  def ops_nav_group(vue, key) do
    Enum.find(vue.props["groups"], &(&1["key"] == key))
  end

  def ops_nav_item(vue, key) do
    vue.props["groups"]
    |> Enum.flat_map(& &1["items"])
    |> Enum.find(&(&1["key"] == key))
  end

  def ops_dashboard_nav_group(vue, key) do
    Enum.find(vue.props["dashboard_groups"], &(&1["key"] == key))
  end

  def ops_dashboard_nav_item(vue, group_key, dashboard_id) do
    case ops_dashboard_nav_group(vue, group_key) do
      nil -> nil
      group -> Enum.find(group["items"], &(&1["dashboard_id"] == dashboard_id))
    end
  end
end
