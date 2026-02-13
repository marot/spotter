defmodule Spotter.Services.CommitHotspotChunkerTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotChunker

  defp region(path, line_start, content) do
    %{
      relative_path: path,
      line_start: line_start,
      line_end: line_start + 10,
      content: content
    }
  end

  describe "chunk_regions/2" do
    test "puts all regions in one chunk when under budget" do
      regions = [
        region("a.ex", 1, String.duplicate("x", 100)),
        region("b.ex", 1, String.duplicate("y", 100))
      ]

      chunks = CommitHotspotChunker.chunk_regions(regions, chunk_budget: 1000)
      assert length(chunks) == 1
      assert length(hd(chunks)) == 2
    end

    test "splits regions across chunks when exceeding budget" do
      regions = [
        region("a.ex", 1, String.duplicate("x", 200)),
        region("b.ex", 1, String.duplicate("y", 200)),
        region("c.ex", 1, String.duplicate("z", 500))
      ]

      chunks = CommitHotspotChunker.chunk_regions(regions, chunk_budget: 500)
      assert length(chunks) == 2
      assert length(Enum.at(chunks, 0)) == 2
      assert length(Enum.at(chunks, 1)) == 1
    end

    test "handles oversized single region" do
      regions = [region("big.ex", 1, String.duplicate("x", 2000))]

      chunks = CommitHotspotChunker.chunk_regions(regions, chunk_budget: 500)
      assert length(chunks) == 1
      assert length(hd(chunks)) == 1
    end

    test "sorts regions by path then line_start" do
      regions = [
        region("z.ex", 50, "late"),
        region("a.ex", 100, "early-high"),
        region("a.ex", 1, "early-low")
      ]

      chunks = CommitHotspotChunker.chunk_regions(regions, chunk_budget: 100_000)
      flat = List.flatten(chunks)

      assert Enum.at(flat, 0).relative_path == "a.ex"
      assert Enum.at(flat, 0).line_start == 1
      assert Enum.at(flat, 1).relative_path == "a.ex"
      assert Enum.at(flat, 1).line_start == 100
      assert Enum.at(flat, 2).relative_path == "z.ex"
    end

    test "returns empty list for empty input" do
      assert CommitHotspotChunker.chunk_regions([]) == []
    end
  end

  describe "chunk_plan/1" do
    test "generates plan metadata for each chunk" do
      chunks = [
        [
          region("a.ex", 1, String.duplicate("x", 100)),
          region("a.ex", 50, String.duplicate("y", 200))
        ],
        [
          region("b.ex", 1, String.duplicate("z", 300))
        ]
      ]

      plan = CommitHotspotChunker.chunk_plan(chunks)
      assert length(plan) == 2

      first = Enum.at(plan, 0)
      assert first.chunk_index == 1
      assert first.region_count == 2
      assert first.approx_chars == 300
      assert first.files == ["a.ex"]

      second = Enum.at(plan, 1)
      assert second.chunk_index == 2
      assert second.region_count == 1
      assert second.approx_chars == 300
      assert second.files == ["b.ex"]
    end
  end
end
