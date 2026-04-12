#!/usr/bin/env zsh

emulate -LR zsh
setopt pipefail

RESET="\033[0m"
PINK="\033[1;35m"
CYAN="\033[38;5;51m"
YELLOW="\033[38;5;226m"
MAGENTA="\033[38;5;201m"
GREEN="\033[38;5;46m"
ORANGE="\033[38;5;208m"
BLUE="\033[1;34m"
DIM="\033[2m"
LIGHT_GREEN="\033[38;5;120m"
RED="\033[1;31m"

cecho() {
  printf '%b\n' "$1"
}

get_color() {
  local percent=${1:-0}

  if (( percent >= 80 )); then
    printf '%s' "$RED"
  elif (( percent >= 60 )); then
    printf '%s' "$ORANGE"
  elif (( percent >= 30 )); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

format_uptime_from_seconds() {
  local total_seconds=${1:-0}
  local days=$(( total_seconds / 86400 ))
  local hours=$(( (total_seconds % 86400) / 3600 ))
  local minutes=$(( (total_seconds % 3600) / 60 ))
  local parts=()

  (( days > 0 )) && parts+=("${days} day$(( days == 1 ? 0 : 1 ))")
  (( hours > 0 )) && parts+=("${hours} hour$(( hours == 1 ? 0 : 1 ))")
  (( minutes > 0 )) && parts+=("${minutes} minute$(( minutes == 1 ? 0 : 1 ))")

  if (( ${#parts[@]} == 0 )); then
    parts=("less than a minute")
  fi

  printf '%s' "${(j:, :)parts}"
}

get_uptime() {
  local uptime_text

  uptime_text="$(uptime -p 2>/dev/null)"
  if [[ -n "$uptime_text" ]]; then
    printf '%s' "${uptime_text#up }"
    return
  fi

  if [[ -r /proc/uptime ]]; then
    local seconds
    seconds=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
    if [[ -n "$seconds" ]]; then
      format_uptime_from_seconds "$seconds"
      return
    fi
  fi

  printf '%s' "N/A"
}

read_cpu_usage() {
  if [[ ! -r /proc/stat ]]; then
    printf '0'
    return
  fi

  local cpu user nice system idle iowait irq softirq steal guest guest_nice
  local total_1 total_2 idle_1 idle_2 total_delta idle_delta usage

  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle_1=$(( idle + iowait ))
  total_1=$(( user + nice + system + idle + iowait + irq + softirq + steal ))

  sleep 0.2

  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle_2=$(( idle + iowait ))
  total_2=$(( user + nice + system + idle + iowait + irq + softirq + steal ))

  total_delta=$(( total_2 - total_1 ))
  idle_delta=$(( idle_2 - idle_1 ))

  if (( total_delta <= 0 )); then
    printf '0'
    return
  fi

  usage=$(( (100 * (total_delta - idle_delta)) / total_delta ))
  (( usage < 0 )) && usage=0
  (( usage > 100 )) && usage=100
  printf '%s' "$usage"
}

get_primary_ip() {
  local ip_addr

  ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
  [[ -n "$ip_addr" ]] || ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -n "$ip_addr" ]] || ip_addr=$(awk '/32 host/ {print $4; exit}' /proc/net/fib_trie 2>/dev/null)
  [[ -n "$ip_addr" ]] || ip_addr="N/A"

  printf '%s' "$ip_addr"
}

get_battery_percentage() {
  local battery_path

  for battery_path in /sys/class/power_supply/BAT*/capacity(N); do
    local capacity
    capacity=$(<"$battery_path")
    [[ -n "$capacity" ]] && printf '%s%%' "$capacity" && return
  done

  printf '%s' ""
}

draw_bar() {
  local percent=${1:-0}
  local width=20
  local fill empty bar=""
  integer i

  (( percent > 100 )) && percent=100
  (( percent < 0 )) && percent=0

  fill=$(( percent * width / 100 ))
  empty=$(( width - fill ))

  for (( i = 0; i < fill; i++ )); do
    bar+="█"
  done

  for (( i = 0; i < empty; i++ )); do
    bar+="░"
  done

  printf '%s' "$bar"
}

color_line() {
  local line="$1"
  local index=${2:-0}
  local -a rainbow_colors=(31 33 32 36 34 35)
  local color=${rainbow_colors[$(( (index % ${#rainbow_colors[@]}) + 1 ))]}

  printf '\033[%sm%s\033[0m' "$color" "$line"
}

probe_gpu_utils() {
  typeset -ga GPU_UTILS
  local util
  integer local_card=0

  GPU_UTILS=()

  if command -v nvidia-smi >/dev/null 2>&1; then
    while IFS= read -r util; do
      util=${util//[[:space:]]/}
      [[ "$util" == <-> ]] && GPU_UTILS+=("$util")
    done < <(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
  fi

  if (( ${#GPU_UTILS[@]} == 0 )); then
    while [[ -f "/sys/class/drm/card${local_card}/device/gpu_busy_percent" ]]; do
      util="$(< "/sys/class/drm/card${local_card}/device/gpu_busy_percent" 2>/dev/null)"
      util=${util//[[:space:]]/}
      [[ "$util" == <-> ]] && GPU_UTILS+=("$util")
      (( local_card++ ))
    done
  fi
}

HOST_NAME="$(hostname 2>/dev/null)"
[[ -n "$HOST_NAME" ]] || HOST_NAME="unknown-host"

ARCH="$(uname -m 2>/dev/null)"
[[ -n "$ARCH" ]] || ARCH="unknown-arch"

if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
  MODEL_NAME="$(< /sys/devices/virtual/dmi/id/product_name)"
else
  MODEL_NAME="Linux Machine"
fi

CHIP="$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
[[ -n "$CHIP" ]] || CHIP="$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null)"
[[ -n "$CHIP" ]] || CHIP="Unknown CPU"

IP_ADDR="$(get_primary_ip)"
UP_TIME="$(get_uptime)"
BATTERY="$(get_battery_percentage)"
CPU_USAGE="$(read_cpu_usage)"

if command -v free >/dev/null 2>&1; then
  VM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
  VM_USED=$(free -m | awk '/Mem:/ {print $3}')
  SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
  SWAP_USED=$(free -m | awk '/Swap:/ {print $3}')
else
  VM_TOTAL=0
  VM_USED=0
  SWAP_TOTAL=0
  SWAP_USED=0
fi

if (( VM_TOTAL > 0 )); then
  RAM_PERCENT=$(( VM_USED * 100 / VM_TOTAL ))
else
  RAM_PERCENT=0
fi

DISK_TOTAL=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $2}')
DISK_USED=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $3}')
[[ -n "$DISK_TOTAL" ]] || DISK_TOTAL=1
[[ -n "$DISK_USED" ]] || DISK_USED=0
DISK_PERCENT=$(( DISK_USED * 100 / DISK_TOTAL ))

if (( SWAP_TOTAL > 0 )); then
  SWAP_PERCENT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
else
  SWAP_PERCENT=0
fi

probe_gpu_utils

WELCOMES=(
"Welcome back!"
"Hello human!"
"Kawaii typing detected!"
"Cat says great!"
"Have a purrfect day!"
"Meow meow!"
"You look comfy!"
"Let's code!"
"Paws activated!"
"Cuteness overload!"
"Enjoy your terminal!"
"Feline power!"
"Stay cozy!"
"Time to hack!"
"Cat inspected!"
"All systems purrfect!"
"Hello world, meow!"
"Cat mode on!"
"Stay pawsitive!"
"Kitty approves your change!"
"Make meow changes!"
"Git commit approved by cat!"
"Deploying cuteness..."
"Terminal purrformance optimal!"
"Cat detected hacker energy!"
"Linting your code with paws..."
"Compiling meowdule..."
"Debugging with whiskers..."
"Running pawcess..."
"Cat watching your commits."
"Code review by kitty complete!"
"System check: purrfect!"
"Whiskers calibrated."
"Claws ready for coding!"
"Keyboard warmed by paws."
"Terminal smells like productivity."
"Coffee detected. Coding likely."
"Cat supervising development."
"Boot sequence approved by cat."
"Purrmission granted!"
"Terminal ready. Meow!"
"Cat scanned the system."
"No bugs detected (cat hopes lol)."
"Whiskers sense good code."
"Purrcess initialized."
"Shell opened successfully."
"Cat guarding the terminal."
"Keep coding, human."
"Terminal looks cozy today."
"Meowgic detected!"
"Your code smells interesting."
"Another day, another commit."
"Cat recommends more snacks."
"Human detected at keyboard."
"Stay focused, stay pawsitive."
"Whisker-driven development."
"Code like a feline."
"System uptime approved."
"Cat believes in your code."
"Meow is a good time to code."
"Paws on keyboard!"
)

WELCOME="${WELCOMES[$(( (RANDOM % ${#WELCOMES[@]}) + 1 ))]}"

cecho ""
cecho "${BLUE}Welcome to Meow-Meow Terminal!${RESET}"
cecho "${CYAN}Cat says:${RESET} ${ORANGE}${WELCOME}${RESET}"
cecho ""

if [[ "$USER" == "root" ]]; then
  CAT_1=$'   /\\_/\\\\\n  ( ⊙ʌ⊙ )'
  CAT_2=$'    /\\_/\\\\\n   ( ⊙ʌ⊙ )'
  CAT_1_TAIL=' ʔ/ づ づ'
  CAT_2_TAIL='   づ づ  \ʃ'
  CAT_1_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
  CAT_2_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
else
  CAT_1=$'   /\\_/\\\\\n  ( ≧ω≦ )'
  CAT_2=$'    /\\_/\\\\\n   ( OωO )'
  CAT_1_TAIL=' ʔ/ づ づ'
  CAT_2_TAIL='   づ づ  \ʃ'
  CAT_1_TEXT="${PINK} Kimochiii!${RESET}"
  CAT_2_TEXT="${BLUE}  Kawayiii!${RESET}"
fi

paste <(print -r -- "$CAT_1"; print -r -- "$CAT_1_TAIL"; print -r -- "$CAT_1_TEXT") \
      <(print -r -- "$CAT_2"; print -r -- "$CAT_2_TAIL"; print -r -- "$CAT_2_TEXT") |
while IFS=$'\t' read -r left right; do
  printf '%b\t%b\n' "$left" "$right"
done

cecho ""

if [[ "$USER" == "root" ]]; then
  USER_NAME="${RED}powerful master${RESET}"
  cecho "${CYAN}Cat whispers: your username is ${USER_NAME}${CYAN}... oh no!${RESET}"
  cecho "${RED}Cat is scared!${RESET}"
  cecho "${YELLOW}Please do not delete the system, ${RED}powerful master${YELLOW}...${RESET}"
  cecho "${YELLOW}rm -rf / is not a toy. That is not fun!${RESET}"
  cecho "${CYAN}Cat hides behind the keyboard... ${RED}please do not delete meow.${RESET}"
else
  USER_NAME="${YELLOW}${USER}${RESET}"
  cecho "${CYAN}Cat whispers: your username is ${USER_NAME}${CYAN}, noted!${RESET}"
fi

cecho "${CYAN}Cat sniffed the machine: hostname ${YELLOW}${HOST_NAME}${RESET}"
cecho "${CYAN}Cat checked your primary IP: ${YELLOW}${IP_ADDR}${RESET}"
cecho "${CYAN}Cat checked the uptime: ${YELLOW}${UP_TIME}${RESET}"

if [[ -n "$BATTERY" ]]; then
  BAT_VAL=${BATTERY%\%}

  if (( BAT_VAL < 20 )); then
    BAT_COLOR=$RED
    BAT_TEXT="Battery is low. Time to plug in soon."
  elif (( BAT_VAL < 50 )); then
    BAT_COLOR=$ORANGE
    BAT_TEXT="Battery is halfway there. Still okay for now."
  else
    BAT_COLOR=$GREEN
    BAT_TEXT="Battery looks healthy. Have a nice meowing day!"
  fi

  cecho "${CYAN}Battery level: ${BAT_COLOR}${BATTERY}${CYAN}, ${BAT_TEXT}${RESET}"
fi

cecho ""

CPU_BAR="$(draw_bar "$CPU_USAGE")"
RAM_BAR="$(draw_bar "$RAM_PERCENT")"
DISK_BAR="$(draw_bar "$DISK_PERCENT")"
CPU_COLOR="$(get_color "$CPU_USAGE")"
RAM_COLOR="$(get_color "$RAM_PERCENT")"
DISK_COLOR="$(get_color "$DISK_PERCENT")"

RAW_ART=(
"               ..               "
"      ;........,,........;      "
"      x................::l      "
"      x..................K      "
"      0..................0      "
"      K..................0      "
"      N..................O      "
"      0..................O      "
"    'oxxxxxdddbbdbdddxxxxxl'    "
"                                "
)

typeset -a DEVICE_ART INFO_LINES
integer art_index=0

for line in "${RAW_ART[@]}"; do
  DEVICE_ART+=("$(color_line "$line" "$art_index")")
  (( art_index++ ))
done

INFO_LINES+=("${BLUE}${MODEL_NAME} (${CHIP}/${ARCH})${RESET} ${DIM}-${RESET} ${LIGHT_GREEN}${USER}${RESET}@${LIGHT_GREEN}${HOST_NAME}${RESET}")
INFO_LINES+=("${DIM}========================================${RESET}")
INFO_LINES+=("${CYAN}CPU Usage: ${CPU_COLOR}${CPU_BAR} ${CPU_USAGE}%${RESET}")
INFO_LINES+=("${CYAN}RAM Usage: ${RAM_COLOR}${RAM_BAR} ${RAM_PERCENT}% (${VM_USED}/${VM_TOTAL} MB)${RESET}")
INFO_LINES+=("${CYAN}Disk Usage: ${DISK_COLOR}${DISK_BAR} ${DISK_PERCENT}% (${DISK_USED}/${DISK_TOTAL} MB)${RESET}")

if (( SWAP_TOTAL > 0 )); then
  SWAP_BAR="$(draw_bar "$SWAP_PERCENT")"
  SWAP_COLOR="$(get_color "$SWAP_PERCENT")"
  INFO_LINES+=("${CYAN}Swap Usage: ${SWAP_COLOR}${SWAP_BAR} ${SWAP_PERCENT}% (${SWAP_USED}/${SWAP_TOTAL} MB)${RESET}")
fi

if (( ${#GPU_UTILS[@]} == 1 )); then
  GPU_BAR="$(draw_bar "${GPU_UTILS[1]}")"
  GPU_COLOR="$(get_color "${GPU_UTILS[1]}")"
  INFO_LINES+=("${CYAN}GPU Usage: ${GPU_COLOR}${GPU_BAR} ${GPU_UTILS[1]}%${RESET}")
elif (( ${#GPU_UTILS[@]} > 1 )); then
  GPU_INDEX=0
  for util in "${GPU_UTILS[@]}"; do
    GPU_BAR="$(draw_bar "$util")"
    GPU_COLOR="$(get_color "$util")"
    INFO_LINES+=("${CYAN}GPU${GPU_INDEX}: ${GPU_COLOR}${GPU_BAR} ${util}%${RESET}")
    (( GPU_INDEX++ ))
  done
fi

integer row_index
for (( row_index = 1; row_index <= ${#DEVICE_ART[@]}; row_index++ )); do
  printf '%-35b %b\n' "${DEVICE_ART[$row_index]}" "${INFO_LINES[$row_index]:-}"
done

cecho ""
cecho "${DIM}============================================================${RESET}"
cecho ""

if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
else
  cecho "${MAGENTA}fastfetch not installed${RESET}"
fi