defmodule CadenceWeb.OpsDashboardShowLive.PublishReadinessModel do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.PublishValidationPresentation

  def build(validation, freshness \\ nil) do
    case PublishValidationPresentation.build(validation, freshness) do
      nil -> nil
      readiness -> Map.put(readiness, :freshness, freshness)
    end
  end
end
