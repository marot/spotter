defmodule Spotter.Services.GitCommitReaderTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.GitCommitReader

  describe "parse_output/1" do
    test "parses standard commit output" do
      output = """
      abc1234567890123456789012345678901234567
      def1234567890123456789012345678901234567
      Add new feature
      This is the body of the commit.
      John Doe
      john@example.com
      2026-02-13T10:00:00+00:00
      2026-02-13T10:00:00+00:00
      COMMIT_END
      """

      result = GitCommitReader.parse_output(output)
      assert length(result) == 1

      commit = hd(result)
      assert commit.commit_hash == "abc1234567890123456789012345678901234567"
      assert commit.parent_hashes == ["def1234567890123456789012345678901234567"]
      assert commit.subject == "Add new feature"
      assert commit.body == "This is the body of the commit."
      assert commit.author_name == "John Doe"
      assert commit.author_email == "john@example.com"
      assert commit.authored_at != nil
      assert commit.committed_at != nil
    end

    test "parses commit with no body" do
      output = """
      abc1234567890123456789012345678901234567

      Fix typo

      Alice
      alice@example.com
      2026-02-13T10:00:00+00:00
      2026-02-13T10:00:00+00:00
      COMMIT_END
      """

      result = GitCommitReader.parse_output(output)
      assert length(result) == 1
      assert hd(result).subject == "Fix typo"
    end

    test "parses multiple commits" do
      output = """
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

      First commit

      Author1
      a@b.com
      2026-02-13T10:00:00+00:00
      2026-02-13T10:00:00+00:00
      COMMIT_END
      bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      Second commit

      Author2
      b@c.com
      2026-02-13T11:00:00+00:00
      2026-02-13T11:00:00+00:00
      COMMIT_END
      """

      result = GitCommitReader.parse_output(output)
      assert length(result) == 2
      assert Enum.at(result, 0).subject == "First commit"
      assert Enum.at(result, 1).subject == "Second commit"
      assert Enum.at(result, 1).parent_hashes == ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    end

    test "handles empty output" do
      assert GitCommitReader.parse_output("") == []
    end
  end
end
