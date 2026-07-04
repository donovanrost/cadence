defmodule Cadence.Support.DashboardInvalidCapabilitiesAdapter do
  @moduledoc false

  alias Cadence.Dashboards.{PlannedSourceRequest, SourceCapabilities, SourceResult}

  def capabilities do
    %SourceCapabilities{
      logical_source: :bad_source,
      supported_sampling: [:latest, "bad-sampling"],
      supported_time_axes: [:bad_axis],
      supported_value_types: [:calibrated],
      supported_shapes: [:bad_shape],
      supports_watermarks?: "yes",
      completeness: :complete,
      metadata: "invalid"
    }
  end

  def facts(_request, _opts), do: {:error, :not_used}

  def resolve(%PlannedSourceRequest{} = request, _opts) do
    %SourceResult{request_id: request.request_id}
  end
end
