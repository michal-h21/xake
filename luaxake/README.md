# Luaxake

This is a reimplementation of Xake using Lua.

What it should do:

- convert all standalone TeX files in a directory tree to PDF and HTML:
  - we search for all files in subdirectories of the path
  - standalone files are files that contain `\documentclass` command
  - we detect included TeX files and recompile if any dependency is updated

# Usage:

    $ texlua luaxake [options] path/to/directory

# Options

- `-c`,`--config` -- name of TeX4ht config file. It can be full path to the
  config file, or just the name. If you pass just the filename, Luaxake will
  search first in the directory with the current TeX file, to support different
  config files for different projects, then in the current working directory,
  project root and local TEXMF tree.

- `-s`,`--script` -- Lua script that can change Luaxake configuration settings.


# Lua scripting 

You can set settings using a Lua script with the `-s` option. The script should 
only set the configuration values. For example, to change the command for HTML 
conversion, you can use the following script:

```Lua 
compilers.html.command = "make4ht -c @{config_file} @{filename} 'options'"
```
