#!/bin/sh
#
# Copyright(c) 2019 Intel Corporation
# SPDX - License - Identifier: BSD - 2 - Clause - Patent
#
set -e

script_dir="$(cd "$(dirname "$0")" > /dev/null 2>&1 && pwd)"
if ! cd "$script_dir"; then
    printf '%s\n' "Failed to cd into root directory!" >&2
    exit
fi

call_help() {
    cat << EOF
Usage: ./.cleanup.sh [OPTION] .. -- [FILES|DIRECTORIES]
    -a, --all       Runs cleanup on all files in tree
    -b <branch>, --branch=<branch>  Use a different branch as origin [master]
    -c, --commit    Commits changes as "Cleanup: Remove trailing whitespace"
    -d, --dry-run   Prints out the files that would have been modified.
                        Does not apply if FILES or DIRECTORIES are present
    -f, --force     Cleans up files regardles of commit status
    -h, --help      This text
    -s, --spaces    Squashes multiple blank lines into one line (cat -s)

    All files and directories are relative to the root of the repository
EOF
}

strip_tabs() {
    if test -t 0; then
        printf %s\\n "$*" | strip_tabs
    else
        sed -e 's/^[ \t]*//'
    fi
}

print_mesage() {
    # Remove leading tabs from the message, if tabs are desired, use cat
    case "$1" in
    stdout)
        shift
        printf %s\\n "$(strip_tabs "${1:-Unknown Message}")"
        ;;
    *) printf %s\\n "$(strip_tabs "${1:-Unknown Message}")" >&2 ;;
    esac
}

die() {
    print_mesage "$(strip_tabs "${1:-Unknown error}")"
    exit "${2:-1}"
}

while true; do
    case $1 in
    --help | -h)
        call_help
        exit
        ;;
    --all | -a)
        clean_all=true
        shift
        ;;
    --branch=*)
        branch="${1#*=}"
        print_mesage "Using $branch as origin"
        shift
        ;;
    -b)
        test -z "$2" && die "No branch specified"
        branch="$2"
        print_mesage "Using $branch as origin"
        shift
        ;;
    --commit | -c)
        commit_cleanup=true
        shift
        ;;
    --force | -f)
        force=true
        shift
        ;;
    --dry-run | -d)
        dry_run=true
        shift
        ;;
    --spaces | -s)
        squash_space=true
        shift
        ;;
    --)
        shift
        break
        ;;
    -*)
        print_mesage "Error, unknown option: '$1'."
        exit 1
        ;;
    *)
        break
        ;;
    esac
done

get_git_folder() {
    if [ -d .git ]; then
        echo "$PWD"
    elif [ -d ../.git ]; then
        echo "${PWD%$(basename "$PWD")}"
    else
        die "Can't find .git in current folder nor in parent directory"
    fi
}

get_diff_files() (
    origin=$(git remote -v | grep -i openvisualcloud | head -n1 | cut -f1)
    origin=${origin:=origin}
    git diff --name-only --diff-filter=d "$origin/${branch:-master}" | grep -iE ".sh|.bat" | grep -v .cleanup.sh
    for file in $(git diff --name-only --diff-filter=d "${branch:-master}" -- \
        ':!*.png' ':!*.git' ':!*.vs*' ':!Build' ':!Bin*' ':!.cleanup.sh' \
        ':!third_party' ':!test/e2e_test/test_vector_list.txt' ':!test/vectors/smoking_test.cfg' \
        ':!test/vectors/video_src.cfg'); do
        [ -f "$file" ] && echo "$file"
    done
)

get_git_files() {
    git ls-tree -r master --name-only | grep -vE '.png|.git|.vs|Build|Bin|.cleanup.sh|third_party|test'
}

get_files_need_cleaning() {
    get_diff_files
    git grep -InP --files-with-matches "\t|\r| $" ':!third_party/**/*'
}

if ! type find > /dev/null 2>&1; then
    die "find not found in PATH. This is required for this script"
fi

if test -n "$(git status --porcelain -uno)" &&
    ! ${force:=false}; then
    die "Please commit any uncommitted changes before running this script
    If you want to run this command, use --force
    However, if you do use --force, there is no guarentee if sed fails"
fi

if test -n "$(find . -name "*.bak")" &&
    ! ${force:=false}; then
    die "Old sed backup files (*.bak) found. Please either delete them
    or properly clean them up. To have the script clean these up, use --force"
fi

check_directories=""
check_files=""

do_find() (
    find="find $1"
    shift
    $find -type f \( -name '*.sh' -or -name '*.bat' -or ! -path '*.git/*' \
        ! -path '*.vs/*' ! -path '*.vscode/*' ! -path '*Bin/*' ! -path '*Build/*' \
        ! -name '*.exe' ! -name '*.dll' ! -name '*.a' ! -name '*.so' ! -name '*.lib' \
        ! -name '*.png' ! -name '*.o' ! -name ".cleanup.sh" \) "$@"
)

delete_bak() {
    find . -type f -name "*.bak" -delete
}

if test $# -ne 0; then
    while test $# -ne 1; do
        for ford in; do
            if test -d "$ford"; then
                check_directories="${check_directories:+$check_directories }$ford"
            elif test -f "$ford"; then
                check_files="${check_files:+$check_files }$ford"
            else
                print_mesage "$ford was not found"
            fi
        done
        shift
    done
    if test -n "$check_directories"; then
        for dir in $check_directories; do
            do_find "$dir" -exec sed -i.bak 's/[[:space:]]*$//' {} +
            # shellcheck disable=SC2016
            ${squash_space:=false} &&
                do_find "$dir" -exec sh -c 'cat -s "$0" | tee "$0" > /dev/null 2>&1' '{}' \;
            delete_bak
        done
    fi
    if test -n "$check_files"; then
        sed -i.bak 's/[[:space:]]*$//' "$check_files"
        for file in $check_files; do
            cat -s "$file" | tee "$file" > /dev/null 2>&1
        done
        delete_bak
    fi
else
    if ${clean_all:=false}; then
        if ${dry_run:=false}; then
            do_find . -exec grep -l '[[:blank:]]$' {} +
        else
            # shellcheck disable=SC2016
            do_find . -exec sed -i.bak 's/[[:space:]]*$//' {} + \
                -exec sh -c 'cat -s "$0" | tee "$0" > /dev/null 2>&1 && echo >> "$0"' '{}' \;
            delete_bak
        fi
    elif test -n "$(get_diff_files)" || $force; then
        if ${dry_run:=false}; then
            grep -l '[[:blank:]]$' -- $(get_diff_files)
        else
            delete_bak
            if ! sed -i.bak 's/[[:space:]]*$//' -- $(get_git_files); then
                find . -type f -name "*.bak" -exec sh -c 'mv $0 $(basename "$0" .bak)' '{}' \;
                die "Failed to modify the changed files, please make sure none of them opened
                and you have permission to modify them"
            else
                delete_bak
                for file in $(get_git_files); do
                    cat -s "$file" | tee "$file" > /dev/null 2>&1
                done
            fi
        fi
    else
        print_mesage "Nothing to do"
    fi
fi

if ${commit_cleanup:=false}; then
    if test -n "$(git status --porcelain -uno)"; then
        git commit -am "Cleanup: Remove trailing whitespace"
    else
        print_mesage "Nothing to commit"
    fi
fi

# git merge-base --is-ancestor $(git log --follow -1 --format=%H -- "$file") HEAD
# For potential --fixup option
