defmodule SpotterWeb.ReviewsChannel do
  @moduledoc "Phoenix Channel for live review-count updates."

  use Phoenix.Channel

  alias Spotter.Services.ReviewCounts

  @impl true
  def join("reviews:counts", _params, socket) do
    project_counts = ReviewCounts.list_project_open_counts()

    total =
      project_counts
      |> Enum.map(& &1.open_count)
      |> Enum.sum()

    payload = %{
      total_open_count: total,
      project_counts: project_counts
    }

    {:ok, payload, socket}
  end
end
