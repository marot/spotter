defmodule Spotter.Services.ProductCommitTimeline do
  @moduledoc """
  Provides a project-scoped commit timeline with attached product spec run information.
  """

  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Services.CommitHistory

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Lists commits for a project with their associated spec runs.

  ## Filters
  - `:project_id` (required) - UUID string
  - `:branch` - optional branch filter

  ## Page options
  - `:limit` - max results per page (default/max 50)
  - `:after` - cursor string for next page

  ## Return shape
      %{
        rows: [%{commit: %Commit{}, spec_run: %RollingSpecRun{} | nil}],
        cursor: cursor | nil,
        has_more: boolean
      }
  """
  @spec list(map(), map()) :: map()
  def list(filters \\ %{}, page_opts \\ %{}) do
    Tracer.with_span "spotter.product_commit_timeline.list" do
      project_id = Map.fetch!(filters, :project_id)
      Tracer.set_attribute("spotter.project_id", project_id)

      result = CommitHistory.list_commits_with_sessions(filters, page_opts)

      commit_hashes = Enum.map(result.rows, & &1.commit.commit_hash)
      runs_by_hash = load_spec_runs(project_id, commit_hashes)

      rows =
        Enum.map(result.rows, fn row ->
          %{
            commit: row.commit,
            spec_run: Map.get(runs_by_hash, row.commit.commit_hash)
          }
        end)

      %{rows: rows, cursor: result.cursor, has_more: result.has_more}
    end
  end

  defp load_spec_runs(_project_id, []), do: %{}

  defp load_spec_runs(project_id, commit_hashes) do
    RollingSpecRun
    |> Ash.Query.filter(project_id == ^project_id and commit_hash in ^commit_hashes)
    |> Ash.read!()
    |> Map.new(&{&1.commit_hash, &1})
  end
end
