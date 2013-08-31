# Sublime2yas

##### SublimeText to YaSnippet / Emacs conversion

This is a script based on the old TextMate import script that
ship(ped) with YASnippet for Emacs.

This script is focussed only on `.sublime-snippet` files, and ignores
commands or macros or whatever else might exist in the SublimeText
universe (I'm largely ignorant of it TBH.)  What I do know is there's
a lot of snippets I want to harvest from it and bring into Emacs, and
I'll be hornswoggled if I'm going to do that mucky business by hand.

So instead here's a script which will take care of it, with a few
extra bells and whistles thrown in for good measure.

## Installation

    gem install sublime2yas

## Uninstall

    gem uninstall sublime2yas

## Usage

For help run `sublime2yas --help` from the command line on  a single folder of SublimeText Snippets.

    sublime2yas -d SublimeSnippetsFolder -o YasnippetsFolder

### Options

    Options:
        --snippet-dir, -d <s>:   Sublime-snippet directory
         --output-dir, -o <s>:   Output directory, use the major-mode name you are targeting as the containing folder's name, e.g.
                                 snippets/major-mode
         --major-mode, -m <s>:   Explicit setting of major-mode if the folder name is different
       --parent-modes, -p <s>:   List of Yasnippet parent modes as a quoted string eg. "cc-mode,text-mode"
               --glob, -g <s>:   Specific snippet file (or glob) inside <snippet_dir>, default is *.sublime-snippet (default:
                                 *.sublime-snippet)
      --snippet-group, -G <s>:   Yasnippet group: to use in generated snippets, eg. -G rails to add 'group: rails' to each snippet. They will
                                 appear in submenu's on the major-mode Yasnippet menu
                  --quiet, -q:   quiet output
                    --doc, -c:   generate a quick reference in markdown format, listing the shortcut and description. Stored in the
                                 --output-dir as QUICKREF.md
                   --help, -h:   Show this message


### Auto Quickref

When using the `--doc` or `-c` option a quick reference / cheatsheet
is generated in the `--output-dir` as `QUICKREF.md`. [See this example](https://gist.github.com/jasonm23/6396154)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
