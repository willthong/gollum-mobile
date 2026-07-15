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

    TAG_RE = /:([a-zA-Z][a-zA-Z0-9_-]*):/

    # File path relative to the repository root.
    TAG_FILE = ::File.join('.gollum', 'tags.json').freeze

    # -------------------------------------------------------------------
    # Extraction
    # -------------------------------------------------------------------

    # Pattern for MAC addresses: :xx:xx:xx:xx:xx:xx:
    # (6 groups of 2 hex digits, colon-separated, bracketed by colons)
    MAC_RE = /:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:/i

    # Extract tags from a single page's raw text.
    # Returns a Hash of  tag_name(string) => count(Integer).
    # +text+ may be nil or a String.
    # MAC addresses (e.g. :aa:bb:cc:dd:ee:ff:) are stripped first
    # so their hex pairs are never counted as tags.
    def self.extract_tags(text)
      return {} unless text.is_a?(::String)

      # Remove MAC addresses before tag scanning
      clean = text.gsub(MAC_RE, '')

      counts = Hash.new(0)
      clean.scan(TAG_RE) do |match|
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
      pages = wiki.pages rescue []
      pages.each do |page|
        raw = page.raw_data rescue nil
        next unless raw
        extract_tags(raw).each { |tag, count| total[tag] += count }
      end
      total
    end

    # -------------------------------------------------------------------
    # Persistence
    # -------------------------------------------------------------------

    # Absolute path to the tag file inside the wiki repository.
    # Uses wiki.path (the filesystem root) rather than wiki.repo.path
    # (which points at .git/ or equivalent).
    def self.tag_path(wiki)
      repo_root = wiki.path rescue nil
      return nil unless repo_root
      ::File.join(repo_root, TAG_FILE)
    end

    # Load tag data from disk.  Returns a Hash (empty if file doesn't exist).
    def self.load(wiki)
      path = tag_path(wiki)
      return {} unless path && ::File.exist?(path)
      ::JSON.parse(::File.read(path))
    rescue ::JSON::ParserError
      {}
    end

    # Persist tag data to disk.  Silently no-ops if the wiki path
    # is unavailable (e.g., bare repo without a writable working tree).
    def self.save(wiki, data)
      path = tag_path(wiki)
      return unless path

      dir = ::File.dirname(path)
      ::FileUtils.mkdir_p(dir)
      ::File.write(path, ::JSON.generate(data))
    end

    # Remove the tag file entirely.
    def self.reset!(wiki)
      path = tag_path(wiki)
      ::FileUtils.rm_f(path) if path
    end

    # Scan the entire wiki and persist the result.
    # Returns the tag data hash on success, or an empty hash on failure.
    def self.reindex!(wiki)
      data = scan_wiki(wiki)
      save(wiki, data)
      data
    rescue => err
      $stderr.puts "[gollum tag_index] reindex! failed: #{err.class}: #{err.message}"
      {}
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
