defmodule Spotter.Services.CommitHotspotChunker do
  @moduledoc """
  Deterministic chunking of file regions for hotspot analysis.

  Sorts regions by `{relative_path, line_start}` and accumulates them into
  chunks until adding a region would exceed the character budget.
  """

  @default_chunk_budget 60_000

  @doc """
  Splits a list of region maps into chunks that fit within the character budget.

  Each region must have `:relative_path`, `:content`, and optionally `:line_start`.
  Returns a list of chunks, where each chunk is a list of regions.

  Options:
    - `:chunk_budget` - max characters per chunk (default 60_000, env SPOTTER_AGENT_CHUNK_CHAR_BUDGET)
  """
  @spec chunk_regions([map()], keyword()) :: [[map()]]
  def chunk_regions(regions, opts \\ []) do
    budget = Keyword.get(opts, :chunk_budget, chunk_budget_setting())

    regions
    |> Enum.sort_by(&{&1.relative_path, &1[:line_start] || 0})
    |> build_chunks(budget)
  end

  defp build_chunks([], _budget), do: []

  defp build_chunks(regions, budget) do
    {chunks, current, _current_size} =
      Enum.reduce(regions, {[], [], 0}, fn region, {chunks, current, current_size} ->
        region_size = byte_size(region.content)

        cond do
          # Region alone exceeds budget - give it its own chunk
          current == [] and region_size > budget ->
            {[{:chunk, [region]} | chunks], [], 0}

          # Adding this region would exceed budget - start new chunk
          current_size + region_size > budget and current != [] ->
            {[{:chunk, Enum.reverse(current)} | chunks], [region], region_size}

          # Fits in current chunk
          true ->
            {chunks, [region | current], current_size + region_size}
        end
      end)

    final_chunks =
      if current != [] do
        [{:chunk, Enum.reverse(current)} | chunks]
      else
        chunks
      end

    final_chunks
    |> Enum.reverse()
    |> Enum.map(fn {:chunk, regions} -> regions end)
  end

  @doc """
  Returns the chunk plan metadata for transparency logging.
  """
  @spec chunk_plan([[map()]]) :: [map()]
  def chunk_plan(chunks) do
    Enum.with_index(chunks, 1)
    |> Enum.map(fn {regions, idx} ->
      total_chars = regions |> Enum.map(&byte_size(&1.content)) |> Enum.sum()

      %{
        chunk_index: idx,
        region_count: length(regions),
        approx_chars: total_chars,
        files: regions |> Enum.map(& &1.relative_path) |> Enum.uniq()
      }
    end)
  end

  defp chunk_budget_setting do
    case System.get_env("SPOTTER_AGENT_CHUNK_CHAR_BUDGET") do
      nil -> @default_chunk_budget
      val -> String.to_integer(val)
    end
  end
end
