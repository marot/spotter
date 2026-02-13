defmodule Spotter.Services.CommitHotspotAgentTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitHotspotAgent

  describe "choose_strategy/2" do
    test "returns :single_run for small diffs" do
      ctx = %{
        diff_stats: %{files_changed: 3, insertions: 50, deletions: 10, binary_files: []},
        patch_files: [],
        context_windows: %{"a.ex" => [%{content: String.duplicate("x", 100)}]}
      }

      assert CommitHotspotAgent.choose_strategy(ctx) == :single_run
    end

    test "returns :explore_then_chunked when files exceed threshold" do
      ctx = %{
        diff_stats: %{files_changed: 300, insertions: 50, deletions: 10, binary_files: []},
        patch_files: [],
        context_windows: %{"a.ex" => [%{content: "x"}]}
      }

      assert CommitHotspotAgent.choose_strategy(ctx) == :explore_then_chunked
    end

    test "returns :explore_then_chunked when lines exceed threshold" do
      ctx = %{
        diff_stats: %{files_changed: 3, insertions: 3000, deletions: 500, binary_files: []},
        patch_files: [],
        context_windows: %{"a.ex" => [%{content: "x"}]}
      }

      assert CommitHotspotAgent.choose_strategy(ctx) == :explore_then_chunked
    end

    test "respects custom thresholds via opts" do
      ctx = %{
        diff_stats: %{files_changed: 5, insertions: 10, deletions: 5, binary_files: []},
        patch_files: [],
        context_windows: %{"a.ex" => [%{content: "x"}]}
      }

      assert CommitHotspotAgent.choose_strategy(ctx, max_files: 3) == :explore_then_chunked
      assert CommitHotspotAgent.choose_strategy(ctx, max_files: 10) == :single_run
    end
  end

  describe "parse_explore_response/1" do
    test "parses valid explore response" do
      json =
        ~s({"selected":[{"relative_path":"lib/foo.ex","ranges":[{"line_start":1,"line_end":20}],"reason":"complex"}],"skipped":[]})

      assert {:ok, selected} = CommitHotspotAgent.parse_explore_response(json)
      assert length(selected) == 1
      assert hd(selected)["relative_path"] == "lib/foo.ex"
    end

    test "returns error for missing selected key" do
      assert {:error, :invalid_explore_response} =
               CommitHotspotAgent.parse_explore_response(~s({"files":[]}))
    end

    test "handles markdown-fenced JSON" do
      json = "```json\n{\"selected\":[],\"skipped\":[]}\n```"
      assert {:ok, []} = CommitHotspotAgent.parse_explore_response(json)
    end
  end

  describe "parse_main_response/1" do
    test "parses valid main response" do
      json =
        ~s({"hotspots":[{"relative_path":"lib/foo.ex","symbol_name":"run/2","line_start":10,"line_end":25,"snippet":"def run do","reason":"complex logic","overall_score":78.5,"rubric":{"complexity":80,"change_risk":85}}]})

      assert {:ok, hotspots} = CommitHotspotAgent.parse_main_response(json)
      assert length(hotspots) == 1

      h = hd(hotspots)
      assert h.relative_path == "lib/foo.ex"
      assert h.symbol_name == "run/2"
      assert h.overall_score == 78.5
      assert h.rubric["complexity"] == 80.0
    end

    test "clamps scores to 0-100" do
      json =
        ~s({"hotspots":[{"relative_path":"a.ex","line_start":1,"line_end":5,"overall_score":150,"rubric":{"x":-10}}]})

      assert {:ok, [h]} = CommitHotspotAgent.parse_main_response(json)
      assert h.overall_score == 100.0
      assert h.rubric["x"] == 0.0
    end

    test "returns error for missing hotspots key" do
      assert {:error, :invalid_main_response} =
               CommitHotspotAgent.parse_main_response(~s({"results":[]}))
    end
  end

  describe "dedupe_hotspots/1" do
    test "keeps hotspot with highest score when duplicated" do
      hotspots = [
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 70.0
        },
        %{
          relative_path: "a.ex",
          line_start: 1,
          line_end: 10,
          symbol_name: "foo",
          overall_score: 85.0
        },
        %{
          relative_path: "b.ex",
          line_start: 1,
          line_end: 5,
          symbol_name: nil,
          overall_score: 60.0
        }
      ]

      result = CommitHotspotAgent.dedupe_hotspots(hotspots)
      assert length(result) == 2
      a_hotspot = Enum.find(result, &(&1.relative_path == "a.ex"))
      assert a_hotspot.overall_score == 85.0
    end

    test "returns empty list for empty input" do
      assert CommitHotspotAgent.dedupe_hotspots([]) == []
    end
  end
end
