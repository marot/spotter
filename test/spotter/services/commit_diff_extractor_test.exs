defmodule Spotter.Services.CommitDiffExtractorTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CommitDiffExtractor

  describe "parse_numstat/1" do
    test "parses text file changes" do
      output = "10\t5\tlib/foo.ex\n3\t1\tlib/bar.ex\n"

      result = CommitDiffExtractor.parse_numstat(output)

      assert result.files_changed == 2
      assert result.insertions == 13
      assert result.deletions == 6
      assert result.binary_files == []
      assert length(result.file_stats) == 2
    end

    test "detects binary files" do
      output = "-\t-\tassets/logo.png\n5\t2\tlib/foo.ex\n"

      result = CommitDiffExtractor.parse_numstat(output)

      assert result.files_changed == 2
      assert result.insertions == 5
      assert result.deletions == 2
      assert result.binary_files == ["assets/logo.png"]
    end

    test "handles all binary files" do
      output = "-\t-\ta.png\n-\t-\tb.jpg\n"

      result = CommitDiffExtractor.parse_numstat(output)

      assert result.files_changed == 2
      assert result.insertions == 0
      assert result.deletions == 0
      assert result.binary_files == ["a.png", "b.jpg"]
    end

    test "handles empty output" do
      result = CommitDiffExtractor.parse_numstat("")

      assert result.files_changed == 0
      assert result.insertions == 0
      assert result.deletions == 0
      assert result.binary_files == []
    end
  end
end
