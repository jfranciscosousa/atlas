defmodule Atlas.Search.MatchTest do
  use ExUnit.Case, async: true

  alias Atlas.Search.Match

  test "normalization handles accents, Unicode forms, punctuation and case" do
    assert Match.terms("CAFÉ São’s Ｖａｕｌｔ cafe\u0301") == ["cafe", "sao", "s", "vault"]
    assert Match.matches?("Café", "cafe")
    assert Match.matches?("dragon’s", "dragon")
    assert Match.matches?("dragons", "dragon")
    assert Match.terms("✨ !!!") == []
    assert Match.normalize("ℂⒶ") == "ca"
    assert Match.normalize(Match.normalize("ℂⒶ")) == "ca"
  end

  test "short words require an exact substring" do
    refute Match.matches?("cat", "bat")
    assert Match.matches?("cats", "cat")
  end

  test "medium words accept one insertion, deletion or substitution" do
    assert Match.matches?("vault", "valt")
    assert Match.matches?("vault", "vauult")
    assert Match.matches?("vault", "vauit")
    refute Match.matches?("vault", "vxxlt")
  end

  test "long query words accept two edits, but not three" do
    assert Match.matches?("waterfall", "watrfall")
    assert Match.matches?("waterfall", "watrfoll")
    refute Match.matches?("waterfall", "wxtrfoll")
  end
end
