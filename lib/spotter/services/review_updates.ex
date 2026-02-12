defmodule Spotter.Services.ReviewUpdates do
  @moduledoc "Broadcasts review-count snapshots over Phoenix Channels after annotation mutations."

  alias Spotter.Services.ReviewCounts

  @doc """
  Computes a review-count snapshot and broadcasts it to the `reviews:counts` topic.

  Returns `:ok` on success. Fails silently (returns `:ok`) if the broadcast errors,
  so callers are never crashed by broadcast failures.
  """
  def broadcast_counts do
    project_counts = ReviewCounts.list_project_open_counts()

    total =
      project_counts
      |> Enum.map(& &1.open_count)
      |> Enum.sum()

    payload = %{
      total_open_count: total,
      project_counts: project_counts
    }

    SpotterWeb.Endpoint.broadcast("reviews:counts", "counts_updated", payload)
    :ok
  rescue
    _ -> :ok
  end
end
