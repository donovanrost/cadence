defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceScenario do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    RuntimeReplayTransportEvidenceSetup,
    ViewTestSupport
  }

  def run do
    %{view: view} = RuntimeReplayTransportEvidenceSetup.run()
    ViewTestSupport.stop_dashboard_view(view)
  end
end
