#!/bin/bash

# ANSI 颜色代码
BLUE="\033[34m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
DIM="\033[2m"
RESET="\033[0m"

# 读取 JSON 输入
input=$(cat)
if [ -z "$input" ]; then
    printf "Claude Code"
    exit 0
fi

# 单次 jq 提取所有字段
eval "$(echo "$input" | jq -r '
    @sh "model_id=\(.model.display_name // .model.id // "unknown")"
    + @sh " current_dir=\(.workspace.current_dir // "/")"
    + @sh " used_pct=\(.context_window.used_percentage // 0)"
    + @sh " context_size=\(.context_window.context_window_size // 200000)"
    + @sh " total_tokens=\(
              (.context_window.current_usage.input_tokens // 0)
            + (.context_window.current_usage.cache_creation_input_tokens // 0)
            + (.context_window.current_usage.cache_read_input_tokens // 0)
            + (.context_window.current_usage.output_tokens // 0))"
    + @sh " effort=\(.effort.level // "")"
')"

# 科学计数法防护
context_size=$(printf "%.0f" "${context_size:-200000}" 2>/dev/null || echo 200000)
total_tokens=$(printf "%.0f" "${total_tokens:-0}" 2>/dev/null || echo 0)
used_pct=$(printf "%.0f" "${used_pct:-0}" 2>/dev/null || echo 0)

[ "${context_size:-0}" -eq 0 ] && context_size=200000

# 项目目录名
project_name=$(basename "${current_dir:-/}")

# Git 分支 + 未提交变更统计
git_branch=""
git_changes=""
if git -C "${current_dir:-.}" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
    [ -n "$branch" ] && git_branch="$branch"
    diff_stat=$(git -C "$current_dir" --no-optional-locks diff --numstat HEAD 2>/dev/null \
        || git -C "$current_dir" --no-optional-locks diff --numstat 2>/dev/null)
    if [ -n "$diff_stat" ]; then
        lines_added=$(echo "$diff_stat" | awk '{s+=$1} END {print s+0}')
        lines_removed=$(echo "$diff_stat" | awk '{s+=$2} END {print s+0}')
        [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ] && git_changes="yes"
    fi
fi

# 转换为 K
total_k=$(( (total_tokens + 500) / 1000 ))
size_k=$(( (context_size + 500) / 1000 ))

# 百分比（服务端预计算值优先，fallback 手动计算）
percentage=$used_pct
[ "$percentage" -eq 0 ] && [ "$total_tokens" -gt 0 ] && percentage=$(( (total_tokens * 100) / context_size ))

# 颜色
if [ "$percentage" -lt 60 ]; then
    BAR_COLOR=$GREEN
elif [ "$percentage" -lt 80 ]; then
    BAR_COLOR=$YELLOW
else
    BAR_COLOR=$RED
fi

# 进度条
bar_width=13
filled=$(( (percentage * bar_width) / 100 ))
[ "$filled" -gt "$bar_width" ] && filled=$bar_width
[ "$filled" -eq 0 ] && [ "$percentage" -gt 0 ] && filled=1
empty=$(( bar_width - filled ))

bar_filled=""
bar_empty=""
for ((i=0; i<filled; i++)); do bar_filled+="█"; done
for ((i=0; i<empty; i++)); do bar_empty+="░"; done

context_text="${total_k}K/${size_k}K(${percentage}%)"

# effort 显示标记（非默认时显示）
show_effort=""
if [ -n "$effort" ] && [ "$effort" != "medium" ]; then
    show_effort="yes"
fi

# 输出
printf "Working Directory: ${BLUE}%s${RESET} | " "$project_name"
printf "Model: ${CYAN}%s${RESET}" "$model_id"

if [ -n "$git_branch" ]; then
    printf " | GIT Branch: ${GREEN}%s${RESET}" "$git_branch"
fi
if [ -n "$git_changes" ]; then
    printf " | Changes: ${GREEN}+%s ${RED}-%s${RESET}" "$lines_added" "$lines_removed"
fi

printf " | Context: ${BAR_COLOR}%s${DIM}%s${RESET} %s" "$bar_filled" "$bar_empty" "$context_text"

if [ -n "$show_effort" ]; then
    printf " | Effort: ${CYAN}%s${RESET}" "$effort"
fi
