# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), "helper"))
require 'gollum/tag_index'

context "TagIndex" do
  setup do
    @path = cloned_testpath("examples/lotr.git")
    @wiki = Gollum::Wiki.new(@path)
    Gollum::TagIndex.reset!(@wiki)
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  # ── extraction ──────────────────────────────────────────────────────

  test "extract_tags returns empty hash for tag-free content" do
    result = Gollum::TagIndex.extract_tags("Just some plain text.")
    assert_equal({}, result)
  end

  test "extract_tags parses colon-delimited tag line" do
    # A tag line starts and ends with a colon
    content = <<~MD
      # My Page

      This page has some tags on a dedicated line.

      :rust:api:deployment:
    MD
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "rust" => 1, "api" => 1, "deployment" => 1 }, result)
  end

  test "extract_tags counts multiple occurrences across lines" do
    content = <<~MD
      :rust:api:
      :rust:deployment:
    MD
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "rust" => 2, "api" => 1, "deployment" => 1 }, result)
  end

  test "extract_tags is case-insensitive" do
    content = ":Rust:rust:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "rust" => 2 }, result)
  end

  test "extract_tags handles multi-word hyphenated tags" do
    content = ":rate-limiting:ci-cd:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "rate-limiting" => 1, "ci-cd" => 1 }, result)
  end

  test "extract_tags ignores lines that don't start and end with colon" do
    # Inline tags in prose are NOT extracted — only dedicated tag lines
    content = "This page is about :rust: and :api:."
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({}, result)
  end

  test "extract_tags ignores standalone colons and colons without letter start" do
    content = "::just colons::\n:-starts-with-hyphen:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({}, result)
  end

  test "extract_tags with underscores works" do
    content = ":hello_world:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "hello_world" => 1 }, result)
  end

  test "extract_tags ignores MAC addresses on prose lines" do
    # MAC on a non-tag line — ignored because line doesn't start with :
    content = "Device MAC is :aa:bb:cc:dd:ee:ff:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({}, result)
  end

  test "extract_tags ignores bare MAC without surrounding colons" do
    content = "ResistanceIsCharacterForming (2C:F0:5D:74:09:65): 192.168.0.58/24"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({}, result)
  end

  test "extract_tags still scans proper tag lines even when MACs exist nearby" do
    content = <<~MD
      :rust:api:
      Device MAC is aa:bb:cc:dd:ee:ff
      :deployment:
    MD
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "rust" => 1, "api" => 1, "deployment" => 1 }, result)
  end

  test "extract_tags accepts alphanumeric tags starting with a letter" do
    content = ":node-js:v2-api:"
    result = Gollum::TagIndex.extract_tags(content)
    assert_equal({ "node-js" => 1, "v2-api" => 1 }, result)
  end

  # ── scanning the wiki ───────────────────────────────────────────────

  test "scan_wiki extracts tags from all pages" do
    # Write pages with proper tag lines
    @wiki.write_page("tagpage1", :markdown, ":rust:api:rust:", commit_details)
    @wiki.write_page("tagpage2", :markdown, ":api:deployment:", commit_details)
    @wiki.write_page("tagpage3", :markdown, "no tags here", commit_details)

    result = Gollum::TagIndex.scan_wiki(@wiki)
    assert_equal({ "rust" => 2, "api" => 2, "deployment" => 1 }, result)
  end

  test "scan_wiki skips pages with no tag lines" do
    @wiki.write_page("notes", :markdown, ":rust:api:", commit_details)
    result = Gollum::TagIndex.scan_wiki(@wiki)
    assert result.key?("rust")
    assert result.key?("api")
  end

  test "scan_wiki returns empty hash when no tags exist" do
    @wiki.write_page("plain", :markdown, "Just words.", commit_details)
    result = Gollum::TagIndex.scan_wiki(@wiki)
    assert_equal({}, result)
  end

  # ── persistence (JSON) ──────────────────────────────────────────────

  test "save and load round-trips correctly" do
    data = { "rust" => 5, "api" => 3 }
    Gollum::TagIndex.save(@wiki, data)
    loaded = Gollum::TagIndex.load(@wiki)
    assert_equal data, loaded
  end

  test "load returns empty hash when no tag file exists" do
    result = Gollum::TagIndex.load(@wiki)
    assert_equal({}, result)
  end

  test "save writes to .gollum/tags.json inside the repo" do
    data = { "foo" => 1 }
    Gollum::TagIndex.save(@wiki, data)
    tag_file  = Gollum::TagIndex.tag_path(@wiki)
    assert tag_file, "tag_path should return a path"
    assert File.exist?(tag_file), "tags.json should exist at #{tag_file}"
    parsed = JSON.parse(File.read(tag_file))
    assert_equal data, parsed
  end

  # ── full reindex ────────────────────────────────────────────────────

  test "reindex! scans and saves" do
    @wiki.write_page("reindextest", :markdown, ":golang:golang:ruby:", commit_details)
    Gollum::TagIndex.reindex!(@wiki)
    loaded = Gollum::TagIndex.load(@wiki)
    assert_equal({ "golang" => 2, "ruby" => 1 }, loaded)
  end

  test "reindex! after page update refreshes tags" do
    page = @wiki.page("Bilbo Baggins")
    original = Gollum::TagIndex.scan_wiki(@wiki)

    Gollum::TagIndex.reindex!(@wiki)

    loaded = Gollum::TagIndex.load(@wiki)
    assert_equal original, loaded
  end

  # ── helper ──────────────────────────────────────────────────────────

  test "tag_counts returns sorted descending" do
    data = { "a" => 1, "b" => 5, "c" => 3 }
    sorted = Gollum::TagIndex.tag_counts(data)
    assert_equal ["b", 5], sorted[0]
    assert_equal ["c", 3], sorted[1]
    assert_equal ["a", 1], sorted[2]
  end

  test "tag_counts limits to top N when specified" do
    data = { "a" => 1, "b" => 5, "c" => 3, "d" => 2 }
    sorted = Gollum::TagIndex.tag_counts(data, limit: 2)
    assert_equal 2, sorted.length
    assert_equal ["b", 5], sorted[0]
    assert_equal ["c", 3], sorted[1]
  end
end
