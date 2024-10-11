#!/usr/bin/env bash

#########################
# bemenu-nb-todo
#
# Licence: GNU GPLv3
# Author: Tomasz Kapias
#
# Dependencies:
#   bemenu v0.6.23
#   bemenu-orange-wrapper
#   Nerd-Fonts
#   nb v7.14.1
#   bash
#   sed
#   grep
#   awk
#
#########################

# bemenu command
declare -a bemenu_cmd
bemenu_cmd=(bemenu)

# NB ENV: nb conf custom location
#export NBRC_PATH="$HOME"/.config/nb/nbrc
export NB_DEFAULT_EXTENSION=md
export NB_LIMIT=10000
# NB ENV: #top todos are pinned at the top of the listings
# priority for pinned items is currently broken: https://github.com/xwmx/nb/issues/341
export NB_PINNED_PATTERN="#top"

# nb command
declare -a nb_cmd
nb_cmd=(nb)

# Optional arguments $1, $2 & $3
declare notebook folder init_tag
# nb notebook's name, default is "home"
notebook="${1:-home}"
# dedicated folder, default is "todos"
folder="${2:-todos}"
# tag name for new todos, default is "bemenu-nb"
init_tag="${3:-todo}"

# to get the relative/short indicators
"${nb_cmd[@]}" use --no-color "$notebook" >/dev/null

# Variables
declare index title view state tags todo_id todo_path
index="0"
title=" NB TODO"
view="todos"
state=""
tags=""
todo_id=""
todo_path=""

header() {
  if [[ ! "$view" == "todos" ]]; then
   echo " Back to Todos"
  fi
  if [[ "$view" == "todos" ]]; then
    echo "󰣯 Filter by State$([[ -n "$state" ]] && echo ": ${state^}")"
    echo "󱤇 Filter by Tag(s)$([[ -n "$tags" ]] && echo ": $tags")"
    if [[ -n "$tags" ]] || [[ -n "$state" ]]; then
      echo "󰇾 Reset Filters"
    fi
  fi
  if [[ "$view" == "infos" ]]; then
      echo "󰗨 Delete Todo"
  fi
}

list() {
  header
  if [[ "$view" == "todos" ]]; then
    "${nb_cmd[@]}" todos --reverse --no-color "$notebook":"$folder"/ "$state" "$tags" 2>/dev/null \
      | sed -r "s/^\[$folder\/([0-9]+)\][^\[]+(\[)/\{\1\}\t\2/g" # hiding indicators & brace id
  elif [[ "$view" == "state" ]]; then
    echo -e "open\nclosed"
  elif [[ "$view" == "tags" ]]; then
    "${nb_cmd[@]}" ls --no-color "$notebook":"$folder"/ --tags 2>/dev/null | /usr/bin/grep -Eo '^#.*'
  elif [[ "$view" == "infos" ]]; then
    "${nb_cmd[@]}" todo list --excerpt 500 --no-indicator --no-color "$notebook":"$folder"/"$todo_id" 2>/dev/null \
      | sed -nr -e "s/^\[$folder\/([0-9]+)\]\s+(\[)/\{\1\} \2/" -e '2d' -e '/^##? /d;p' | awk 'NF'
  fi
}

back() {
  if [[ "$1" == " Back to Todos" ]]; then
    view="todos"
    todo_id=""
    todo_path=""
    index="0"
  else
    return 1
  fi
}

view_todo() {
  if [[ "$1" =~ ^\{[0-9] ]]; then
    view="infos"
    state=""
    tags=""
    todo_id=$(echo "$1" | sed -r -e 's/^\{([0-9]+)\}.+/\1/')
    todo_path=$("${nb_cmd[@]}" todo --no-color --no-id --no-indicator --path "$notebook":"$folder"/"$todo_id" 2>/dev/null)
    index="2"
  else
    return 1
  fi
}

view_filters() {
  if [[ "$1" =~ ^󰣯\ Filter\ by\ State ]]; then
    view="state"
    [[ "$state" == "open" ]] && index="2" || index="1"
  elif [[ "$1" =~ ^󱤇\ Filter\ by\ Tag ]]; then
    view="tags"
    index="1"
  else
    return 1
  fi
}

reset_filters() {
  if [[ "$1" == "󰇾 Reset Filters" ]]; then
    view="todos"
    state=""
    tags=""
    index="0"
  else
    return 1
  fi
}

add_todo() {
  if [[ ! "$1" =~ ^\{|^󰣯|^󱤇|^󰇾 ]]; then
    state=""
    tags=""
    todo_id=$("${nb_cmd[@]}" todo add --no-color "$notebook":"$folder"/ "$1" --tags="${init_tag}" 2>/dev/null \
      | sed -r 's/.+\[todos\/([0-9]+).+/\1/')
    todo_path=$("${nb_cmd[@]}" todo --no-color --no-id --no-indicator --path "$notebook":"$folder"/"$todo_id" 2>/dev/null)
    view="infos"
    index="2"
  else
    return 1
  fi
}

filters() {
  if [[ "$1" =~ ^open|^closed ]]; then
    view="todos"
    state="$1"
    index="0"
  elif [[ "$1" =~ ^# ]]; then
    view="todos"
    tags="$(echo "$1" | tr '\n' ' ')"
    index="0"
  else
    return 1
  fi
}

delete_todo() {
  if [[ "$1" == "󰗨 Delete Todo" ]]; then
    "${nb_cmd[@]}" todo delete --force --no-color "$notebook":"$folder"/"$todo_id" >/dev/null
    view="todos"
    todo_id=""
    todo_path=""
    index="0"
  else
    return 1
  fi
}

chstate_todo() {
  if [[ "$1" =~ ^\{[0-9]+\}\ \[\ \] ]]; then
    "${nb_cmd[@]}" todo 'do' --no-color "$notebook":"$folder"/"$todo_id" >/dev/null
  elif [[ "$1" =~ ^\{[0-9]+\}\ \[x\] ]]; then
    "${nb_cmd[@]}" todo undo --no-color "$notebook":"$folder"/"$todo_id" >/dev/null
  else
    return 1
  fi
}

mod_tasks() {
  if [[ "$1" =~ ^-\ \[[\ x]\] ]]; then
    local pattern
    pattern=$(echo "$1"| sed 's/[]\/$*.^[]/\\&/g')
    if /usr/bin/grep -Eq -- "$pattern" "$todo_path" 2>/dev/null; then
      sed -i -e "/$pattern/ s/^\-\ \[\ \]/- [x]/" "$todo_path" \
        -e "/$pattern/ s/^\-\ \[x\]/- [ ]/" "$todo_path"
    elif /usr/bin/grep -Eq -- '## Tasks' "$todo_path" 2>/dev/null; then
      sed -i -e ':a' -e 'N;$! ba' -e "s/.*\(\n\)-\ [\[][\ x]\]\ [^\n]*/&\1$1/" "$todo_path"
    else
      echo -e "\n## Tasks\n\n${1}" >> "$todo_path"
    fi
  else
    return 1
  fi
}

mod_tags() {
  if [[ "$1" =~ ^#[a-zA-Z0-9] ]]; then
    if [[ "$("${nb_cmd[@]}" ls --no-color "$notebook":"$folder"/"$todo_id" --tags 2>/dev/null)" =~ ^No ]]; then
      sed -i -e '/^##\ Tags/d' -e 's/[\ ]*$//' "$todo_path"
      echo -e "\n## Tags\n\n#${init_tag}" >> "$todo_path"
      cat -s "$todo_path"  | tee "$todo_path"
    fi
    local todo_tags
    local -a selection
    IFS=' ' read -r -a selection <<< "$1"
    for tag in "${selection[@]}"; do
      todo_tags=$(sed -n '/^#[a-zA-Z0-9]/p' "$todo_path" | tr '\n' ' ')
      if [[ "$todo_tags" =~ [\ ]*"$tag"[\ ]* ]] && [[ ! "#$init_tag" == "$tag" ]]; then
        sed -i -r -e "/^##\ Tags/{n;n;s/${tag}[\ ]*//}" -e 's/[\ ]*$//' "$todo_path"
      elif [[ ! "$todo_tags" =~ [\ ]*"$tag"[\ ]* ]] && [[ ! "#$init_tag" == "$tag" ]]; then
        sed -i "/^##\ Tags/{n;n;s/$/ ${tag}/}" "$todo_path"
      else
        return 1
      fi
    done
  else
    return 1
  fi
}

open_related() {
  if [[ "$1" =~ ^-\ \[\["$folder" ]]; then
    todo_id=$(echo "$1" | sed -r "s/.*$folder\/([0-9]+)\]\]/\1/")
    todo_path=$("${nb_cmd[@]}" todo --no-color --no-id --no-indicator --path "$notebook":"$folder"/"$todo_id" 2>/dev/null)
  elif [[ "$1" =~ ^-\ \< ]]; then
    local url
    url=$(echo "$1" | /usr/bin/grep -Eo "(((http|https|ftp|gopher)|mailto)[.:][^ >\"\]*|www\.[-a-z0-9.]+)[^ .,;\>\">\):]" 2>/dev/null)
    [[ -n "$url" ]] && open "$url"
  else
    return 1
  fi
}

while
  input=$(list | "${bemenu_cmd[@]}" --index "$index" --prompt "$title")
  [[ -n "$input" ]]
do
  back            "$input" && continue
  if [[ "$view" == "todos" ]]; then
    view_todo     "$input" && continue
    view_filters  "$input" && continue
    reset_filters "$input" && continue
    add_todo      "$input" && continue
  elif [[ "$view" =~ ^state$|^tags$ ]]; then
    filters       "$input" && continue
  elif [[ "$view" == "infos" ]]; then
    delete_todo   "$input" && continue
    chstate_todo  "$input" && continue
    mod_tasks     "$input" && continue
    mod_tags      "$input" && continue
    open_related  "$input" && continue
  fi
done

