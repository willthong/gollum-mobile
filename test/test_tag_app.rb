# ~*~ encoding: utf-8 ~*~
require File.expand_path(File.join(File.dirname(__FILE__), "helper"))

context "TagCloud on search page" do
  include Rack::Test::Methods

  setup do
    @path = cloned_testpath("examples/lotr.git")
    @wiki = Gollum::Wiki.new(@path)
    Precious::App.set(:gollum_path, @path)
    Precious::App.set(:wiki_options, {allow_editing: true})
    Gollum::TagIndex.reset!(@wiki)

    # Seed some tagged pages with proper tag lines (start/end with :)
    @wiki.write_page("tagp1", :markdown, ":rust:api:rust:", commit_details)
    @wiki.write_page("tagp2", :markdown, ":rust:deployment:", commit_details)
    @wiki.write_page("tagp3", :markdown, ":api:api:testing:", commit_details)
    Gollum::TagIndex.reindex!(@wiki)
  end

  teardown do
    FileUtils.rm_rf(@path)
  end

  def app
    Precious::App
  end

  test "search page renders tag cloud section when tags exist" do
    get '/search'
    assert last_response.ok?
    assert_match /Browse by tag/, last_response.body
  end

  test "search page renders individual tag pills" do
    get '/search'
    assert last_response.ok?
    assert_match /class="tag-pill"/, last_response.body
  end

  test "tags are rendered in descending frequency order" do
    get '/search'
    body = last_response.body
    # rust appears twice (2), api appears 3 times (2 in tagp3 + 1 in tagp1)
    # deployment appears once (1)
    # testing appears once (1)
    # So order should be: api(3), rust(2), then deployment(1), testing(1)

    # Find all data-tag attributes in order
    tags_in_order = body.scan(/data-tag="([^"]+)"/).flatten
    assert_equal "api",   tags_in_order[0], "api should be first (freq=3)"
    assert_equal "rust",  tags_in_order[1], "rust should be second (freq=2)"
  end

  test "search page shows counts on each pill" do
    get '/search'
    assert_match /class="pill-count">3</, last_response.body  # api has 3
    assert_match /class="pill-count">2</, last_response.body  # rust has 2
  end

  test "search page tag section is absent when no tags exist" do
    # Use the empty repo instead
    empty_path = cloned_testpath("examples/empty.git")
    begin
      Precious::App.set(:gollum_path, empty_path)
      empty_wiki = Gollum::Wiki.new(empty_path)
      Gollum::TagIndex.reset!(empty_wiki)

      get '/search'
      refute_match /tag-pill/, last_response.body
      refute_match /Browse by tag/, last_response.body
    ensure
      FileUtils.rm_rf(empty_path)
      Precious::App.set(:gollum_path, @path)
    end
  end

  test "search page includes the toggle JavaScript" do
    get '/search'
    assert_match /Tag pill toggle/, last_response.body
  end

  test "search page works without tags (no crash)" do
    Gollum::TagIndex.reset!(@wiki)  # clear tags
    get '/search?q=bilbo'
    assert last_response.ok?
  end
end
