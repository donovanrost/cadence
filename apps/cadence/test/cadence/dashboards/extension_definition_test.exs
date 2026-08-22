defmodule Cadence.Dashboards.ExtensionDefinitionTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{WidgetRegistry, WidgetType}

  alias Cadence.DataSources.AdapterRegistry

  alias Cadence.DataSources.AdapterDefinition

  alias Cadence.DataSources.SourceCapabilities

  test "validates every compiled widget type and its authoring presentation identity" do
    for widget_type <- WidgetRegistry.list_types() do
      assert :ok = WidgetType.validate(widget_type)
      assert widget_type.form_value != ""
      assert widget_type.form_label != ""
    end

    assert {:error, :invalid_widget_type} =
             WidgetType.validate(%WidgetType{
               widget_type_id: "cadence.invalid",
               version: 1,
               trust: :first_party
             })
  end

  test "resolves only exact validated built-in source adapter versions" do
    for definition <- AdapterRegistry.list_definitions() do
      assert :ok = AdapterDefinition.validate(definition)

      assert %SourceCapabilities{logical_source: logical_source} =
               SourceCapabilities.normalize(definition.module.capabilities())

      assert logical_source == definition.logical_source

      assert {:ok, ^definition} =
               AdapterRegistry.fetch_definition(
                 definition.logical_source,
                 definition.version
               )
    end

    assert {:error, :unsupported_source_adapter_version} =
             AdapterRegistry.fetch_definition(:telemetry, 99)

    assert {:error, :unknown_source_adapter} =
             AdapterRegistry.fetch_definition(:unknown)
  end
end
