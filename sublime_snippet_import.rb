#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# sublie_snippet_import.rb --- import sublime snippets
#
# generate YASnippets from Sublime Text Snippets.
# Use sublime_snippet_import).rb --help to get usage information.
#
# Copyright ©2013 Jason Milkins
# based on original work Copyright ©2009 Rob Christie, ©2010 João Távora
# which was in turn based on a python script by Jeff Wheeler: http://nokrev.com
# http://code.nokrev.com/?p=snippet-copier.git;a=blob_plain;f=snippet_copier.py
#
# Released under MIT licence.
#
require 'rubygems'
require 'nokogiri'
require 'trollop'
require 'fileutils'
require 'ruby-debug' if $DEBUG

Encoding.default_external = Encoding::UTF_8 if RUBY_VERSION > '1.8.7'

snippet_doc = []

opts = Trollop::options do
  opt :snippet_dir,   %q(Sublime-snippet directory),

      :short => '-d', :type => :string

  opt :output_dir,    %(Output directory, use the major-mode name you are targeting as the containing folder's name, e.g. snippets/major-mode),

      :short => '-o', :type => :string

  opt :major_mode,    %(Explicit setting of major-mode if the folder name is different),

      :short => '-m', :type => :string

  opt :parent_modes,  %q(List of Yasnippet parent modes as a quoted string eg. "cc-mode,text-mode"),

      :short => '-p', :type => :string

  opt :glob,          %q(Specific snippet file (or glob) inside <snippet_dir>, default is *.sublime-snippet),

      :short => '-g', :default => '*.sublime-snippet'

  opt :snippet_group, %q(Yasnippet group: to use in generated snippets, eg. -G rails to add 'group: rails' to each snippet. They will appear in submenu's on the major-mode Yasnippet menu),

      :short => '-G', :type => :string

  opt :quiet,         %(quiet output),

      :short => '-q'

  opt :doc,          %(generate a quick reference in markdown format, listing the shortcut and description. Stored in the --output-dir as QUICKREF.md)

end

Trollop::die :snippet_dir, "'must be provided" unless opts.snippet_dir
Trollop::die :snippet_dir, "must exist" unless File.directory? opts.snippet_dir

Trollop::die :output_dir, "must be provided" unless opts.output_dir
Trollop::die :output_dir, "must exist" unless File.directory? opts.output_dir

class SublimeSubmenu

  @@excluded_items = [];
  def self.excluded_items; @@excluded_items; end

  attr_reader :items, :name
  def initialize(name, hash)
    @items = hash["items"]
    @name = name
  end

  def to_lisp(allsubmenus,
              deleteditems,
              indent = 0,
              thingy = ["(", ")"])

    first = true;

    string = ""
    separator_useless = true;
    items.each do |uuid|
      if deleteditems && deleteditems.index(uuid)
        $stderr.puts "#{uuid} has been deleted!"
        next
      end
      string += "\n"
      string += " " * indent
      string += (first ? thingy[0] : (" " * thingy[0].length))

      submenu = allsubmenus[uuid]
      snippet = SublimeSnippet::snippets_by_uid[uuid]
      unimplemented = SublimeSnippet::unknown_substitutions["content"][uuid]
      if submenu
        str = "(yas-submenu "
        string += str + "\"" + submenu.name + "\""
        string += submenu.to_lisp(allsubmenus, deleteditems,
                                  indent + str.length + thingy[0].length)
      elsif snippet and not unimplemented
        string += ";; " + snippet.name + "\n"
        string += " " * (indent + thingy[0].length)
        string += "(yas-item \"" + uuid + "\")"
        separator_useless = false;
      elsif snippet and unimplemented
        string += ";; Ignoring " + snippet.name + "\n"
        string += " " * (indent + thingy[0].length)
        string += "(yas-ignore-item \"" + uuid + "\")"
        separator_useless = true;
      elsif (uuid =~ /---------------------/)
        string += "(yas-separator)" unless separator_useless
      end
      first = false;
    end
    string += ")"
    string += thingy[1]

    return string
  end

  def self.main_menu_to_lisp (parsed_plist, modename)
    mainmenu = parsed_plist["mainMenu"]
    deleted  = parsed_plist["deleted"]

    root = SublimeSubmenu.new("__main_menu__", mainmenu)
    all = {}

    mainmenu["submenus"].each_pair do |k,v|
      all[k] = SublimeSubmenu.new(v["name"], v)
    end

    excluded = (mainmenu["excludedItems"] || []) + SublimeSubmenu::excluded_items
    closing = "\n                    '("
    closing+= excluded.collect do |uuid|
      "\"" + uuid + "\""
    end.join(  "\n                       ") + "))"

    str = "(yas-define-menu "
    return str + "'#{modename}" + root.to_lisp(all,
                                               deleted,
                                               str.length,
                                               ["'(" , closing])
  end
end


# Represents a sublime snippet
#
# - @file is the .sublime-snippet file path relative to cwd
#
# - @@snippets_by_uid is where one can find all the snippets parsed so
#   far.
#
#
class SkipSnippet < RuntimeError; end

class SublimeSnippet

  @@known_substitutions = {
    "content"   => {
      "${TM_RAILS_TEMPLATE_START_RUBY_EXPR}"   => "<%= ",
      "${TM_RAILS_TEMPLATE_END_RUBY_EXPR}"     => " %>",
      "${TM_RAILS_TEMPLATE_START_RUBY_INLINE}" => "<% ",
      "${TM_RAILS_TEMPLATE_END_RUBY_INLINE}"   => " -%>",
      "${TM_RAILS_TEMPLATE_END_RUBY_BLOCK}"    => "end" ,
      "${0:$TM_SELECTED_TEXT}"                 => "${0:`yas-selected-text`}",
      /\$\{(\d+)\}/                            => "$\\1",
      "${1:$TM_SELECTED_TEXT}"                 => "${1:`yas-selected-text`}",
      "${2:$TM_SELECTED_TEXT}"                 => "${2:`yas-selected-text`}",
      '$TM_SELECTED_TEXT'                     => "`yas-selected-text`",
      %r'\$\{TM_SELECTED_TEXT:([^\}]*)\}'       => "`(or (yas-selected-text) \"\\1\")`",
      %r'`[^`]+\n[^`]`'                        => Proc.new {|uuid, match| "(yas-multi-line-unknown " + uuid + ")"}},
    "condition" => {
      /^source\..*$/ => "" },
    "binding"   => {},
    "type"      => {}
  }

  def self.extra_substitutions; @@extra_substitutions; end
  @@extra_substitutions = {
    "content"   => {},
    "condition" => {},
    "binding"   => {},
    "type"      => {}
  }

  def self.unknown_substitutions; @@unknown_substitutions; end
  @@unknown_substitutions = {
    "content"   => {},
    "condition" => {},
    "binding"   => {},
    "type"      => {}
  }

  @@snippets_by_uid={}
  def self.snippets_by_uid; @@snippets_by_uid; end

  def initialize(file)
    @file    = file
    @snippet = SublimeSnippet::read_snippet(open(file))
    @@snippets_by_uid[self.uuid] = self;
    raise SkipSnippet.new "This is not a sublime-snippet, I just do sublime-snippets." unless (@snippet.xpath "//scope")
    raise RuntimeError.new("Cannot convert this snippet #{file}!") unless @snippet;
  end

  def name
    (@snippet.xpath "//description").text
  end

  def uuid
    (@snippet.xpath "//uuid").text
  end

  def key
    (@snippet.xpath "//tabTrigger").text
  end

  def condition
    yas_directive "condition"
  end

  def type
    override = yas_directive "type"
    if override
      return override
    end
  end

  def binding
    yas_directive "binding"
  end

  def content
    known = @@known_substitutions["content"]
    extra = @@extra_substitutions["content"]
    if direct = extra[uuid]
      return direct
    else
      ct = (@snippet.xpath "//content").text
      if ct
        known.each_pair do |k,v|
          if v.respond_to? :call
            ct.gsub!(k) {|match| v.call(uuid, match)}
          else
            ct.gsub!(k,v)
          end
        end
        extra.each_pair do |k,v|
          ct.gsub!(k,v)
        end
        # the remaining stuff is an unknown substitution
        #
        [ %r'\$\{ [^/\}\{:]* / [^/]* / [^/]* / [^\}]*\}'x ,
          %r'\$\{[^\d][^}]+\}',
          %r'`[^`]+`',
          %r'\$TM_[\w_]+',
          %r'\(yas-multi-line-unknown [^\)]*\)'
        ].each do |reg|
          ct.scan(reg) do |match|
            @@unknown_substitutions["content"][match] = self
          end
        end
        return ct
      else
        @@unknown_substitutions["content"][uuid] = self
        SublimeSubmenu::excluded_items.push(uuid)
        return "(yas-unimplemented)"
      end
    end
  end

  def to_yas opts
    doc = "# -*- mode: snippet -*-\n"
    doc << "# contributor: Translated to yasnippet by sublime-snippet import\n"
    doc << (self.type || "")
    doc << "# uuid: #{self.uuid}\n"
    doc << "# key: #{self.key}\n" if self.key
    doc << "# group: #{opts.snippet_group}\n" if opts.snippet_group
    doc << "# name: #{self.name}\n"
    doc << (self.binding || "")
    doc << (self.condition || "")
    doc << "# --\n"
    doc << (self.content || "(yas-unimplemented)")
    doc
  end

  def self.canonicalize(filename)
    invalid_char = /[^ a-z_0-9.+=~(){}\/'`&#,-]/i

    filename.
      gsub(invalid_char, '').  # remove invalid characters
      gsub(/ {2,}/,' ').       # squeeze repeated spaces into a single one
      rstrip                   # remove trailing whitespaces
  end

  def yas_file()
    File.join(SublimeSnippet::canonicalize(@file[0, @file.length-File.extname(@file).length]) + ".yasnippet")
  end

  def self.read_snippet(xml)
    begin
      parsed = Nokogiri::XML(xml)
      return parsed if parsed
      raise ArgumentError.new "Format not recognised as sublime-snippet..."
    rescue StandardError => e
      raise RuntimeError.new "Failed to read sublime-snippet - Nokogiri gem is required, make sure it's installed"
    end
  end

  private

  @@yas_to_tm_directives = {"condition" => "scope", "binding" => "keyEquivalent", "key" => "tabTrigger"}
  def yas_directive(yas_directive)
    #
    # Merge "known" hardcoded substitution with "extra" substitutions
    # provided in the .yas-setup.el file.
    #
    merged = @@known_substitutions[yas_directive].
      merge(@@extra_substitutions[yas_directive])
    #
    # First look for an uuid-based direct substitution for this
    # directive.
    #
    if direct = merged[uuid]
      return "# #{yas_directive}: "+ direct + "\n" unless direct.empty?
    else
      tm_directive = @@yas_to_tm_directives[yas_directive]
      val = tm_directive && @snippet[tm_directive]
      if val and !val.delete(" ").empty? then
        #
        # Sort merged substitutions by length (bigger ones first,
        # regexps last), and apply them to the value gotten for plist.
        #
        allsubs = merged.sort_by do |what, with|
          if what.respond_to? :length then -what.length else 0 end
        end
        allsubs.each do |sub|
          if val.gsub!(sub[0],sub[1])
            return "# #{yas_directive}: "+ val + "\n" unless val.empty?
          end
        end
        #
        # If we get here, no substitution matched, so mark this an
        # unknown substitution.
        #
        @@unknown_substitutions[yas_directive][val] = self
        return "## #{yas_directive}: \""+ val + "\n"
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME

  modename = opts.major_mode or File.basename opts.output_dir or "major-mode-name"
  original_dir = Dir.pwd

  if opts.parent_modes
    yas_parents_file = File.join(opts.output_dir, ".yas-parents")
    File.open yas_parents_file, 'w' do |yp|
      yp.puts opts.parent_modes
    end
  end

  yas_setup_el_file = File.join(original_dir, opts.output_dir, ".yas-setup.el")
  separator = ";; --**--"
  whole, head, tail = "", "", ""

  if File::exists? yas_setup_el_file
    File.open yas_setup_el_file, '"r' do |file|
      whole = file.read
      head, tail = whole.split(separator)
    end
  else
    head = ";; .yas-setup.el for #{modename}\n" + ";; \n"
  end

  tail    ||= ""
  head    ||= ""
  directive = nil
  head.each_line do |line|
    case line
    when /^;; Substitutions for:(.*)$/
      directive = $~[1].strip
    when /^;;(.*)[ ]+=yyas>(.*)$/
      replacewith = $~[2].strip
      lookfor = $~[1]
      lookfor.gsub!(/^[ ]*/, "")
      lookfor.gsub!(/[ ]*$/, "")
      unless !directive or replacewith =~ /yas-unknown/ then
        SublimeSnippet.extra_substitutions[directive][lookfor] = replacewith
      end
    end
  end

  Dir.chdir opts.snippet_dir
  snippet_files_glob = File.join("**", opts.glob)
  snippet_files = Dir.glob(snippet_files_glob)
  puts "Attempting to convert #{snippet_files.length} snippets...\n" unless opts.quiet
  snippet_files.each do |file|
    begin
      $stdout.print "Processing \"#{File.join(opts.snippet_dir,file)}\"..." unless opts.quiet
      snippet = SublimeSnippet.new(file)
      file_to_create = File.join(original_dir, opts.output_dir, snippet.yas_file)
      FileUtils.mkdir_p(File.dirname(file_to_create))
      File.open(file_to_create, 'w') do |f|
        f.write(snippet.to_yas opts)
      end

      snippet_doc << {keys: snippet.key, name: snippet.name} if opts.doc

      $stdout.print "done\n" unless opts.quiet
    rescue SkipSnippet => e
      $stdout.print "skipped! #{e.message}\n" unless opts.quiet
    rescue RuntimeError => e
      $stderr.print "failed! #{e.message}\n"
      $strerr.print "#{e.backtrace.join("\n")}" unless opts.quiet
    end
  end

  # TODO: Perhaps do this as a slim template so we can use tables, flex-boxes and what-not.
  if opts.doc
    doc_file = File.join opts.output_dir, "QUICKREF.md"
    File.open(doc_file, "w") do |f|
      f.puts "# #{modename.capitalize} - Snippets Quick Reference"
      snippet_doc.each do |doc|
        f.puts "\n`#{doc[:keys]}` ➔ "
        f.puts "\n>#### `#{doc[:name]}`"
      end
      f.puts "\n\n<sub>Generated by Sublime Snippet Import to Yasnippet, <sup>Powered by tea, figs and ruby</sup></sub>"
    end
    puts "#{modename.capitalize} - Snippets Quick Reference created."
  end

end
