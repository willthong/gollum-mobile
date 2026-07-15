# encoding: UTF-8
require 'json'
require 'fileutils'

module Gollum
  # Enumerates `:tag-name:` patterns across all markdown pages in a wiki
  # and persists the aggregate as JSON under `.gollum/tags.json`.
  #
  # tag syntax:  :name:    where name is [a-zA-Z0-9][a-zA-Z0-9_-]*
  # Matched at colon boundaries only.  Case-insensitive (lowercased internally).
  module TagIndex

    TAG_RE = /:([a-zA-Z0-9][a-zA-Z0-9_-]*):/

    # File path relative to the repository root.
    TAG_FILE = ::File.join('.gollum', 'tags.json').freeze

    # -------------------------------------------------------------------
    # Extraction
    # -------------------------------------------------------------------

    # Extract tags from a single page's raw text.
    # Returns a Hash of  tag_name(string) => count(Integer).
    def self.extract_tags(text)
      counts = Hash.new(0)
      text.scan(TAG_RE) do |match|
        tag = match.first.downcase
        counts[tag] += 1 unless tag.empty?
      end
      counts
    end

    # -------------------------------------------------------------------
    # Wiki scanning
    # -------------------------------------------------------------------

    # Walk every page in the wiki and merge all tag counts.
    # Returns a Hash of  tag_name => total_count.
    def self.scan_wiki(wiki)
      total = Hash.new(0)
      wiki.pages.each do |page|
        extract_tags(page.raw_data).each { |tag, count| total[tag] += count }
      end
      total
    end

    # -------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------

    # Absolute path to the tag file inside the wiki repository.
    def self.tag_path(wiki)
      repo_path = wiki.repo.path
      ::File.join(repo_path, TAG_FILE)
    end

    # Load tag data from disk.  Returns a Hash (empty if file doesn't exist).
    def self.load(wiki)
      path = tag_path(wiki)
      return {} unless ::File.exist?(path)
      ::JSON.parse(::File.read(path))
    rescue ::JSON::ParserError
      {}
    end

    # Persist tag data to disk.
    def self.save(wiki, data)
      path = tag_path(wiki)
      dir  = ::File.dirname(path)
      ::FileUtils.mkdir_p(dir)
      ::File.write(path, ::JSON.generate(data))
    end

    # Remove the tag file entirely.
    def self.reset!(wiki)
      path = tag_path(wiki)
      ::FileUtils.rm_f(path)
    end

    # Scan the entire wiki and persist the result.
    def self.reindex!(wiki)
      data = scan_wiki(wiki)
      save(wiki, data)
      data
    end

    # -------------------------------------------------------------------
    # Sorting / presentation helpers
    # -------------------------------------------------------------------

    # Return tags as an Array of [tag, count] pairs sorted by
    # descending count (then alphabetically as a tiebreaker).
    # +limit+ caps how many pairs to return (nil = all).
    def self.tag_counts(data, limit: nil)
      pairs = data.sort_by { |tag, count| [-count, tag] }
      limit ? pairs.first(limit) : pairs
    end
  end
end
