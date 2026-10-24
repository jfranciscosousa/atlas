defmodule Atlas.Search.MatchTest do
  use ExUnit.Case, async: true

  alias Atlas.Search.Match

  test "normalization handles accents, Unicode forms, punctuation and case" do
    assert Match.terms("CAFÉ São’s Ｖａｕｌｔ cafe\u0301") == ["cafe", "sao", "s", "saos", "vault"]
    assert Match.matches?("Café", "cafe")
    assert Match.matches?("dragon’s", "dragon")
    assert Match.matches?("dragons", "dragon")
    assert Match.terms("✨ !!!") == []
    assert Match.normalize("ℂⒶ") == "ca"
    assert Match.normalize(Match.normalize("ℂⒶ")) == "ca"
  end

  test "punctuation inside a chunk splits it into words and also joins it into one" do
    assert Match.terms("M.A.77 in-world, done.") ==
             ["m", "a", "77", "ma77", "in", "world", "inworld", "done"]

    assert Match.terms("M A 77") == ["m", "a", "77"]
  end

  test "a query chunk asks for its joined word only" do
    assert Match.query_terms("M.A.77") == ["ma77"]
    assert Match.query_terms("MA77 m.a.77") == ["ma77"]
    assert Match.query_terms("in-world Date, dragon’s") == ["inworld", "date", "dragons"]
    assert Match.query_terms("✨ !!!") == []
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
