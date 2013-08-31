require "sublime2yas/version"
require 'nokogiri'
require 'fileutils'

module Sublime2yas


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
      # doc << "# uuid: #{self.uuid}\n" unless self.uuid.empty?
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


end
