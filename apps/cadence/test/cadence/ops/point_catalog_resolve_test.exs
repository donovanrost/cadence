defmodule Cadence.Ops.PointCatalogResolveTest do
  @moduledoc """
  #73: a verifier subject resolves to the catalog point by point id (with or without
  `telemetry:`), the parameter's semantic id, or its qualified name. Compose's current value and
  the U2 verifier plot both use it.
  """
  use ExUnit.Case, async: true

  alias Cadence.Ops.PointCatalog

  @mode %{
    point_id: "HK.sc_mode",
    parameter_id: "semantic:parameter:6f1c",
    qualified_name: "/EARENDIL/HK/sc_mode",
    packet_name: "HK",
    field_name: "sc_mode",
    unit: nil,
    stale_timeout_ms: nil,
    description: nil
  }

  @temp %{
    @mode
    | point_id: "THERM.temp",
      parameter_id: nil,
      qualified_name: nil,
      field_name: "temp",
      unit: "degC"
  }

  @points [@temp, @mode]

  test "a point id, with or without telemetry:" do
    assert PointCatalog.resolve(@points, "HK.sc_mode") == @mode
    assert PointCatalog.resolve(@points, " telemetry:THERM.temp ") == @temp
  end

  test "the mission model's semantic id and the qualified name" do
    assert PointCatalog.resolve(@points, "semantic:parameter:6f1c") == @mode
    assert PointCatalog.resolve(@points, "/EARENDIL/HK/sc_mode") == @mode
  end

  test "an unknown subject, or a point without a semantic id, resolves to nil" do
    assert PointCatalog.resolve(@points, "semantic:parameter:none") == nil
    assert PointCatalog.resolve([@temp], "semantic:parameter:6f1c") == nil
  end
end
