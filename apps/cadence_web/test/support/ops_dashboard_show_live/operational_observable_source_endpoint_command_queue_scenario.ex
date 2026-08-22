defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointCommandQueueScenario do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    OperationalObservableSourceEndpointCommandQueueSetup,
    ViewTestSupport
  }

  def run do
    %{views: views} = OperationalObservableSourceEndpointCommandQueueSetup.run()
    ViewTestSupport.stop_dashboard_views(views)
  end
end
