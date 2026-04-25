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

convert_to_mb() {
  local val="${1:-0M}"

  if [[ "$val" == *G ]]; then
    awk "BEGIN {printf \"%d\", ${val%G} * 1024}"
  elif [[ "$val" == *M ]]; then
    awk "BEGIN {printf \"%d\", ${val%M}}"
  elif [[ "$val" == *K ]]; then
    awk "BEGIN {printf \"%d\", ${val%K} / 1024}"
  else
    printf '0'
  fi
}

draw_bar() {
  local percent=${1:-0}
  local width=18
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

get_primary_ip() {
  local default_if ip_addr

  default_if="$(route get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ -n "$default_if" ]]; then
    ip_addr="$(ipconfig getifaddr "$default_if" 2>/dev/null)"
  fi

  [[ -n "$ip_addr" ]] || ip_addr="$(ipconfig getifaddr en0 2>/dev/null)"
  [[ -n "$ip_addr" ]] || ip_addr="$(ipconfig getifaddr en1 2>/dev/null)"
  [[ -n "$ip_addr" ]] || ip_addr="N/A"

  printf '%s' "$ip_addr"
}

get_uptime() {
  local boot_line boot_month boot_day boot_time current_year boot_epoch now_epoch delta
  local days hours minutes parts=()

  boot_line="$(who -b 2>/dev/null | awk '{print $3, $4, $5}')"
  if [[ -n "$boot_line" ]]; then
    boot_month="$(printf '%s\n' "$boot_line" | awk '{print $1}')"
    boot_day="$(printf '%s\n' "$boot_line" | awk '{print $2}')"
    boot_time="$(printf '%s\n' "$boot_line" | awk '{print $3}')"
    current_year="$(date '+%Y' 2>/dev/null)"
    boot_epoch="$(date -j -f '%b %e %H:%M %Y' "${boot_month} ${boot_day} ${boot_time} ${current_year}" '+%s' 2>/dev/null)"
    now_epoch="$(date '+%s' 2>/dev/null)"

    if [[ -n "$boot_epoch" && -n "$now_epoch" && "$boot_epoch" == <-> && "$now_epoch" == <-> && "$now_epoch" -ge "$boot_epoch" ]]; then
      delta=$(( now_epoch - boot_epoch ))
      days=$(( delta / 86400 ))
      hours=$(( (delta % 86400) / 3600 ))
      minutes=$(( (delta % 3600) / 60 ))

      (( days > 0 )) && parts+=("${days}d")
      (( hours > 0 )) && parts+=("${hours}h")
      (( minutes > 0 )) && parts+=("${minutes}m")
      (( ${#parts[@]} == 0 )) && parts=("less than a minute")

      printf '%s' "${(j: :)parts}"
      return
    fi
  fi

  printf '%s' "N/A"
}

get_battery_percentage() {
  local battery_raw battery

  battery_raw="$(pmset -g batt 2>/dev/null)"
  battery="$(printf '%s\n' "$battery_raw" | grep -Eo '[0-9]+%' | head -n1)"
  printf '%s' "$battery"
}

get_cpu_usage() {
  local cpu_line user sys

  cpu_line="$(top -l 1 -n 0 2>/dev/null | awk -F'[:,% ]+' '/CPU usage/ {print $3, $5; exit}')"
  user="${cpu_line%% *}"
  sys="${cpu_line##* }"

  [[ "$user" == <->.<-> || "$user" == <-> ]] || user=0
  [[ "$sys" == <->.<-> || "$sys" == <-> ]] || sys=0

  awk "BEGIN {printf \"%d\", $user + $sys}"
}

get_memory_stats() {
  local vm_stat_output memory_pressure_output page_size pages_active pages_wired pages_compressed pages_speculative
  local ram_total_bytes ram_total_mb ram_used_mb ram_percent

  vm_stat_output="$(vm_stat 2>/dev/null)"
  memory_pressure_output="$(memory_pressure 2>/dev/null)"
  page_size="$(printf '%s\n' "$vm_stat_output" | awk '/page size of/ {gsub("\\.","",$8); print $8; exit}')"
  pages_active="$(printf '%s\n' "$vm_stat_output" | awk '/Pages active/ {gsub("\\.","",$3); print $3; exit}')"
  pages_wired="$(printf '%s\n' "$vm_stat_output" | awk '/Pages wired down/ {gsub("\\.","",$4); print $4; exit}')"
  pages_compressed="$(printf '%s\n' "$vm_stat_output" | awk '/Pages occupied by compressor/ {gsub("\\.","",$5); print $5; exit}')"
  pages_speculative="$(printf '%s\n' "$vm_stat_output" | awk '/Pages speculative/ {gsub("\\.","",$3); print $3; exit}')"

  [[ -n "$page_size" ]] || page_size=4096
  [[ -n "$pages_active" ]] || pages_active=0
  [[ -n "$pages_wired" ]] || pages_wired=0
  [[ -n "$pages_compressed" ]] || pages_compressed=0
  [[ -n "$pages_speculative" ]] || pages_speculative=0

  ram_total_bytes="$(printf '%s\n' "$memory_pressure_output" | awk 'NR==1 {gsub(/[^0-9]/,"",$3); print $3; exit}')"
  if [[ -n "$ram_total_bytes" && "$ram_total_bytes" == <-> ]]; then
    :
  else
    ram_total_bytes="$(hostinfo 2>/dev/null | awk '/Primary memory available/ {print $4 * 1024 * 1024 * 1024; exit}')"
  fi
  [[ -n "$ram_total_bytes" ]] || ram_total_bytes=0

  ram_total_mb=$(( ram_total_bytes / 1024 / 1024 ))
  ram_used_mb=$(( (pages_active + pages_wired + pages_compressed - pages_speculative) * page_size / 1024 / 1024 ))
  (( ram_used_mb < 0 )) && ram_used_mb=0

  if (( ram_total_mb > 0 )); then
    ram_percent=$(( ram_used_mb * 100 / ram_total_mb ))
  else
    ram_percent=0
  fi

  printf '%s %s %s\n' "$ram_used_mb" "$ram_total_mb" "$ram_percent"
}

get_memory_pressure() {
  local free_percent

  if command -v memory_pressure >/dev/null 2>&1; then
    free_percent="$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/ {gsub("%","",$5); print $5; exit}')"
  fi

  [[ "$free_percent" == <-> ]] || free_percent=0
  printf '%s' $(( 100 - free_percent ))
}

get_swap_stats() {
  local swapusage swap_used_raw swap_total_raw swap_used_mb swap_total_mb swap_percent

  swapusage="$(sysctl vm.swapusage 2>/dev/null)"
  swap_used_raw="$(printf '%s\n' "$swapusage" | sed -E 's/.*used = ([0-9.]+[KMG]).*/\1/')"
  swap_total_raw="$(printf '%s\n' "$swapusage" | sed -E 's/.*total = ([0-9.]+[KMG]).*/\1/')"
  [[ -n "$swap_used_raw" ]] || swap_used_raw="0M"
  [[ -n "$swap_total_raw" ]] || swap_total_raw="0M"

  swap_used_mb="$(convert_to_mb "$swap_used_raw")"
  swap_total_mb="$(convert_to_mb "$swap_total_raw")"

  if (( swap_total_mb > 0 )); then
    swap_percent=$(( swap_used_mb * 100 / swap_total_mb ))
  else
    swap_percent=0
  fi

  printf '%s %s %s\n' "$swap_used_mb" "$swap_total_mb" "$swap_percent"
}

get_disk_stats() {
  local target disk_total disk_used disk_percent

  if [[ -d /System/Volumes/Data ]]; then
    target="/System/Volumes/Data"
  else
    target="/"
  fi

  disk_total="$(df -Pm "$target" 2>/dev/null | awk 'NR==2 {print $2}')"
  disk_used="$(df -Pm "$target" 2>/dev/null | awk 'NR==2 {print $3}')"

  [[ -n "$disk_total" ]] || disk_total=1
  [[ -n "$disk_used" ]] || disk_used=0
  disk_percent=$(( disk_used * 100 / disk_total ))

  printf '%s %s %s\n' "$disk_used" "$disk_total" "$disk_percent"
}

get_mac_hardware_profile() {
  local hardware_data model_name chip_name

  hardware_data="$(system_profiler SPHardwareDataType 2>/dev/null)"
  model_name="$(printf '%s\n' "$hardware_data" | awk -F': ' '/Model Name/ {print $2; exit}')"
  chip_name="$(printf '%s\n' "$hardware_data" | awk -F': ' '/Chip/ {print $2; exit}')"

  if [[ -z "$chip_name" ]]; then
    chip_name="$(printf '%s\n' "$hardware_data" | awk -F': ' '/Processor Name/ {print $2; exit}')"
  fi

  [[ -n "$model_name" ]] || model_name="Mac"
  [[ -n "$chip_name" ]] || chip_name="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  [[ -n "$chip_name" ]] || chip_name="Unknown CPU"

  printf '%s\n%s\n' "$model_name" "$chip_name"
}

get_gpu_lines() {
  local display_data line
  local -a gpu_names
  integer gpu_index=0

  display_data="$(system_profiler SPDisplaysDataType 2>/dev/null)"
  while IFS= read -r line; do
    [[ -n "$line" ]] && gpu_names+=("$line")
  done < <(printf '%s\n' "$display_data" | awk -F': ' '/Chipset Model/ {print $2}')

  if (( ${#gpu_names[@]} == 1 )); then
    printf '%s\n' "${CYAN}GPU: ${YELLOW}${gpu_names[1]}${RESET}"
  elif (( ${#gpu_names[@]} > 1 )); then
    for line in "${gpu_names[@]}"; do
      printf '%s\n' "${CYAN}GPU${gpu_index}: ${YELLOW}${line}${RESET}"
      (( gpu_index++ ))
    done
  fi
}

HOST_NAME="$(hostname 2>/dev/null)"
[[ -n "$HOST_NAME" ]] || HOST_NAME="unknown-host"

ARCH="$(uname -m 2>/dev/null)"
[[ -n "$ARCH" ]] || ARCH="unknown-arch"

typeset -a HARDWARE_PROFILE
HARDWARE_PROFILE=("${(@f)$(get_mac_hardware_profile)}")
MODEL_NAME="${HARDWARE_PROFILE[1]}"
CHIP="${HARDWARE_PROFILE[2]}"

IP_ADDR="$(get_primary_ip)"
UP_TIME="$(get_uptime)"
BATTERY="$(get_battery_percentage)"
CPU_USAGE="$(get_cpu_usage)"

typeset -a MEMORY_STATS
MEMORY_STATS=("${(@s: :)$(get_memory_stats)}")
RAM_USED="${MEMORY_STATS[1]}"
RAM_TOTAL="${MEMORY_STATS[2]}"
RAM_PERCENT="${MEMORY_STATS[3]}"

MEM_PRESSURE="$(get_memory_pressure)"

typeset -a SWAP_STATS
SWAP_STATS=("${(@s: :)$(get_swap_stats)}")
SWAP_USED="${SWAP_STATS[1]}"
SWAP_TOTAL="${SWAP_STATS[2]}"
SWAP_PERCENT="${SWAP_STATS[3]}"

typeset -a DISK_STATS
DISK_STATS=("${(@s: :)$(get_disk_stats)}")
DISK_USED="${DISK_STATS[1]}"
DISK_TOTAL="${DISK_STATS[2]}"
DISK_PERCENT="${DISK_STATS[3]}"

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

CONNECTION_TYPE=""
LOGIN_IP=""

if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
  CONNECTION_TYPE="SSH"
  LOGIN_IP="$(echo "$SSH_CONNECTION" | awk '{print $1}')"
  [[ -z "$LOGIN_IP" ]] && LOGIN_IP="$(echo "$SSH_CLIENT" | awk '{print $1}')"
elif [[ "$(ps -o comm= -p $PPID 2>/dev/null)" =~ (telnet|rlogin) ]]; then
  CONNECTION_TYPE="telnet"
  LOGIN_IP="$(who am i 2>/dev/null | awk '{print $NF}' | tr -d '()')"
  [[ -z "$LOGIN_IP" ]] && LOGIN_IP="$(netstat -tn 2>/dev/null | awk '/ESTABLISHED/ && /:23 / {gsub(/:[0-9]+$/, "", $5); print $5; exit}')"
fi

if [[ -n "$CONNECTION_TYPE" ]]; then
  if [[ -n "$LOGIN_IP" ]]; then
    cecho "${CYAN}Cat noticed: you connected via ${MAGENTA}${CONNECTION_TYPE}${CYAN} from ${YELLOW}${LOGIN_IP}${CYAN}, is this you?${RESET}"
  else
    cecho "${CYAN}Cat noticed: you connected via ${MAGENTA}${CONNECTION_TYPE}${CYAN} from ${YELLOW}somewhere mysterious${CYAN}...${RESET}"
  fi
else
  TTY_INFO="$(tty 2>/dev/null)"
  [[ -n "$TTY_INFO" ]] && TTY_INFO="${YELLOW}${TTY_INFO}${RESET}" || TTY_INFO="${YELLOW}unknown${RESET}"
  cecho "${CYAN}Cat noticed: you're on local terminal ${TTY_INFO}${RESET}"
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
MEM_BAR="$(draw_bar "$MEM_PRESSURE")"

CPU_COLOR="$(get_color "$CPU_USAGE")"
RAM_COLOR="$(get_color "$RAM_PERCENT")"
DISK_COLOR="$(get_color "$DISK_PERCENT")"
MEM_COLOR="$(get_color "$MEM_PRESSURE")"

CAT_ART_1=(
"       I'm hungry!  "
"              ノ    "
"   ／l、 _․         "
"  /  l._/. フ       "
" ( ﾟ⩊ ｡  . ).       "
"  l     ~ヽ         "
"   l      -.\   /)  "
"   じしf_  , .)ノ/  "
"                    "
"                    "
)

CAT_ART_2=(
"       touch me!    "
"              ノ    "
"   ／l、 _․         "
"  /  l._/. フ       "
" (.˃ ᵕ ˂. ).        "
"  l     ~ヽ         "
"   l      -.\   /)  "
"   じしf_  , .)ノ/  "
"                    "
"                    "
)

typeset -a ALL_CAT_ARTS
ALL_CAT_ARTS=(CAT_ART_1 CAT_ART_2)

RANDOM_INDEX=$(( (RANDOM % ${#ALL_CAT_ARTS[@]}) + 1 ))
SELECTED_CAT_NAME="${ALL_CAT_ARTS[$RANDOM_INDEX]}"

typeset -a RAW_ART
eval "RAW_ART=(\"\${${SELECTED_CAT_NAME}[@]}\")"

typeset -a DEVICE_ART INFO_LINES GPU_LINES
integer art_index=0

for line in "${RAW_ART[@]}"; do
  DEVICE_ART+=("$(color_line "$line" "$art_index")")
  (( art_index++ ))
done

INFO_LINES+=("${BLUE}${MODEL_NAME}${RESET}")
INFO_LINES+=("${DIM}CPU:${RESET} ${YELLOW}${CHIP}${RESET} ${DIM}(${ARCH})${RESET}")
INFO_LINES+=("${DIM}User:${RESET} ${LIGHT_GREEN}${USER}${RESET}@${LIGHT_GREEN}${HOST_NAME}${RESET}")
INFO_LINES+=("${DIM}========================================${RESET}")
INFO_LINES+=("${CYAN}CPU Usage: ${CPU_COLOR}${CPU_BAR} ${CPU_USAGE}%${RESET}")
INFO_LINES+=("${CYAN}RAM Usage: ${RAM_COLOR}${RAM_BAR} ${RAM_PERCENT}% (${RAM_USED}/${RAM_TOTAL} MB)${RESET}")
INFO_LINES+=("${CYAN}Disk Usage: ${DISK_COLOR}${DISK_BAR} ${DISK_PERCENT}% (${DISK_USED}/${DISK_TOTAL} MB)${RESET}")
INFO_LINES+=("${CYAN}Memory Pressure: ${MEM_COLOR}${MEM_BAR} ${MEM_PRESSURE}%${RESET}")

if (( SWAP_TOTAL > 0 )); then
  SWAP_BAR="$(draw_bar "$SWAP_PERCENT")"
  SWAP_COLOR="$(get_color "$SWAP_PERCENT")"
  INFO_LINES+=("${CYAN}Swap Usage: ${SWAP_COLOR}${SWAP_BAR} ${SWAP_PERCENT}% (${SWAP_USED}/${SWAP_TOTAL} MB)${RESET}")
fi

GPU_LINES=("${(@f)$(get_gpu_lines)}")
if (( ${#GPU_LINES[@]} > 0 )); then
  INFO_LINES+=("${GPU_LINES[@]}")
fi

get_display_width() {
  local str="$1"
  local stripped="$(printf '%b' "$str" | sed 's/\x1b\[[0-9;]*m//g')"
  local width=0
  local i char byte_val

  for (( i = 0; i < ${#stripped}; i++ )); do
    char="${stripped:$i:1}"
    printf -v byte_val '%d' "'$char"

    if (( byte_val >= 0x1100 && byte_val <= 0x115F )) || \
       (( byte_val >= 0x2329 && byte_val <= 0x232A )) || \
       (( byte_val >= 0x2E80 && byte_val <= 0x303E )) || \
       (( byte_val >= 0x3040 && byte_val <= 0xA4CF )) || \
       (( byte_val >= 0xAC00 && byte_val <= 0xD7A3 )) || \
       (( byte_val >= 0xF900 && byte_val <= 0xFAFF )) || \
       (( byte_val >= 0xFE10 && byte_val <= 0xFE19 )) || \
       (( byte_val >= 0xFE30 && byte_val <= 0xFE6F )) || \
       (( byte_val >= 0xFF00 && byte_val <= 0xFF60 )) || \
       (( byte_val >= 0xFFE0 && byte_val <= 0xFFE6 )); then
      (( width += 2 ))
    else
      (( width += 1 ))
    fi
  done

  printf '%d' "$width"
}

integer row_index target_width=1
for (( row_index = 1; row_index <= ${#DEVICE_ART[@]}; row_index++ )); do
  local left="${DEVICE_ART[$row_index]}"
  local right="${INFO_LINES[$row_index]:-}"
  local display_width=$(get_display_width "$left")
  local padding=$(( target_width - display_width ))
  (( padding < 0 )) && padding=0

  printf '%b%*s %b\n' "$left" "$padding" "" "$right"
done

cecho ""
cecho "${DIM}============================================================${RESET}"
cecho ""

if command -v fastfetch >/dev/null 2>&1; then
  fastfetch 2>/dev/null
else
  cecho "${MAGENTA}fastfetch not installed${RESET}"
fi