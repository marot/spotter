defmodule Spotter.Transcripts.Jobs.ComputeHeatmap do
  @moduledoc "Oban worker that computes file change heatmap for a project."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 30]

  require Logger

  alias Spotter.Services.HeatmapCalculator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    Logger.info("ComputeHeatmap: computing heatmap for project #{project_id}")

    :ok = HeatmapCalculator.compute(project_id)
    :ok
  end
end
