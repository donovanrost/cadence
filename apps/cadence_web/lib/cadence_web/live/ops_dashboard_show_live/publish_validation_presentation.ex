defmodule CadenceWeb.OpsDashboardShowLive.PublishValidationPresentation do
  @moduledoc false

  alias Cadence.Dashboards.PublishReadinessPresentation

  defdelegate build(validation, freshness \\ nil), to: PublishReadinessPresentation
  defdelegate issue_message(issue), to: PublishReadinessPresentation
  defdelegate issue_detail_rows(issue), to: PublishReadinessPresentation
end
