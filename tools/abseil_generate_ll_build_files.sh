#!/bin/bash
# This script clones the latest version of abseil, rewrites the build files to
# be compatible with rules_ll and adds a MODULE.bazel file.
# It returns a diff which can then be used to create a package in a bzlmod
# registry.

git clone git@github.com:abseil/abseil-cpp.git && cd abseil-cpp

# It is faster invoke buildozer on a file when using the same targets for all
# commands. This way buildozer only needs to manipulate each file once.

# https://unix.stackexchange.com/questions/181937/how-create-a-temporary-file-in-shell-script
tmpfile=$(mktemp /tmp/buildozer-rewrite-abseil-to-rules_ll.XXXXXX)
exec 3>"$tmpfile"
exec 4<"$tmpfile"
rm "$tmpfile"

# Import ll_library.
echo 'fix movePackageToTop
new_load @rules_ll//ll:defs.bzl ll_library|//absl/...:*' >&3

# Remove and rewrite easy-to-fix attributes.
echo '
remove copts
|remove linkopts
|remove alwayslink
|set compile_flags ["-std=c++20"]
|set_if_absent srcs
|set_if_absent hdrs
|set_if_absent textual_hdrs
|set transitive_relative_includes [""]
|rename hdrs transitive_hdrs
|move textual_hdrs transitive_hdrs *
|set kind ll_library
|//absl/...:%cc_library
' | tr -d '\n' >&3

# Clean up redundant imports.
echo '
fix unusedLoads' >&3

# Run buildozer.
buildozer -f - <&4

# The hdrs attribute in rules_ll is private and headers are not allowed in srcs.
# Usually we would want to move all these sources to the private hdrs
# attribute, but it turns out that they are sometimes required by downstream
# targets. So we move the headers to transitive_hdrs instead.
#
# 1. Print all srcs.
# 2. Strip brackets.
# 3. Remove all lines containing *.cc files. Only *.h and *.inc files remain
# 4. Remove all blank lines.
# 5. Merge all lines to a space-delimited line.
# 6. Move all occurences of values in the string to hdrs.
buildozer 'print srcs'  //absl/...:%ll_library \
    | tr -d '[]' \
    | tr ' ' '\n' \
    | sed 's/.*\.cc//g' \
    | sed '\/^$/d' \
    | tr '\n' ' ' \
    | xargs -I{} buildozer 'move srcs transitive_hdrs {}' //absl/...:%ll_library



version=0.0.0-$(date '+%Y%m%d')-$(git rev-parse --short HEAD)
printf 'module(
    name="abseil-cpp",
    version="%s",
    compatibility_level = 1,
)
bazel_dep(name = "rules_ll", version = "20220905.0")' $version >> MODULE.bazel

git add MODULE.bazel absl/*
git diff --staged >> ../abseil_rules_ll_patch.diff
