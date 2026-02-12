defmodule Spotter.Services.GitLogReaderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.GitLogReader

  describe "parse_output/1" do
    test "parses standard git log output" do
      output = """
      COMMIT:abc123:1700000000
      lib/foo.ex
      lib/bar.ex
      COMMIT:def456:1700086400
      README.md
      """

      result = GitLogReader.parse_output(output)
      assert length(result) == 2

      [first, second] = result
      assert first.hash == "abc123"
      assert first.timestamp == ~U[2023-11-14 22:13:20Z]
      assert first.files == ["lib/foo.ex", "lib/bar.ex"]

      assert second.hash == "def456"
      assert second.files == ["README.md"]
    end

    test "handles empty output" do
      assert GitLogReader.parse_output("") == []
    end

    test "handles output with no files" do
      output = "COMMIT:abc123:1700000000\n"
      result = GitLogReader.parse_output(output)
      assert length(result) == 1
      assert hd(result).files == []
    end

    test "handles malformed commit header" do
      output = "COMMIT:badformat\nfile.ex\n"
      # Should still parse - badformat becomes hash, no unix timestamp
      result = GitLogReader.parse_output(output)
      assert result == []
    end
  end

  describe "resolve_branch/2" do
    test "returns provided branch when given" do
      assert {:ok, "develop"} = GitLogReader.resolve_branch("/tmp", "develop")
    end

    test "skips empty string branch" do
      # Empty string falls through to auto-detect which will fail on /tmp
      assert {:error, _} = GitLogReader.resolve_branch("/tmp/nonexistent-repo", "")
    end
  end

  describe "changed_files_by_commit/2" do
    test "returns error for nonexistent repo" do
      assert {:error, _} =
               GitLogReader.changed_files_by_commit(
                 "/tmp/nonexistent-repo-#{System.unique_integer()}",
                 since_days: 1
               )
    end
  end
end
