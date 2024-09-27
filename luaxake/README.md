# Luaxake

This is a reimplementation of Xake using Lua.

What it should do:

- convert all standalone TeX files in a directory tree to PDF and HTML:
  - we search for all files in subdirectories of the path
  - standalone files are files that contain `\documentclass` command
  - we detect included TeX files and recompile if any dependency is updated

# Usage:

    $ texlua luaxake path/to/directory
