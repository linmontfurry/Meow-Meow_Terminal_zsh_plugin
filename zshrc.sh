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

convert_to_mb() {
  local val=$1
  if [[ "$val" == *G ]]; then
    awk "BEGIN {printf \"%d\", ${val%G}*1024}"
  elif [[ "$val" == *M ]]; then
    echo ${val%M}
  else
    echo 0
  fi
}

get_color() {
  local percent=$1

  if (( percent >= 80 )); then
    printf "%s" "$RED"
  elif (( percent >= 60 )); then
    printf "%s" "$ORANGE"
  elif (( percent >= 30 )); then
    printf "%s" "$YELLOW"
  else
    printf "%s" "$GREEN"
  fi
}

HOST_NAME="$(hostname)"
ARCH=$(uname -m)
MODEL_NAME=$(system_profiler SPHardwareDataType | awk -F": " '/Model Name/{print $2}')
CHIP=$(system_profiler SPHardwareDataType | awk -F": " '/Chip:/{print $2}' )
[[ -z "$CHIP" ]] && CHIP=$(system_profiler SPHardwareDataType | awk -F": " '/Processor Name:/{print $2}')
IP_ADDR=$(ipconfig getifaddr en0 2>/dev/null)
[[ -z "$IP_ADDR" ]] && IP_ADDR=$(ipconfig getifaddr en1 2>/dev/null)
[[ -z "$IP_ADDR" ]] && IP_ADDR="N/A"
UP_TIME="$(uptime | awk -F', ' '{print $1}' | sed 's/up //')"
BATTERY_RAW="$(pmset -g batt 2>/dev/null)"
BATTERY=""
CPU_USAGE=$(top -l 1 | awk '/CPU usage/ {print int($3 + $5)}')
CACHE_FILE="/tmp/meow_stats_cache"

if [[ -f "$CACHE_FILE" && $(($(date +%s) - $(stat -f %m "$CACHE_FILE"))) -lt 3 ]]; then
  source "$CACHE_FILE"
else
  CPU_USAGE=$(top -l 1 | awk '/CPU usage/ {print int($3+$5)}')
  echo "CPU_USAGE=$CPU_USAGE" > "$CACHE_FILE"
fi

if echo "$BATTERY_RAW" | grep -q "[0-9]\+%"; then
  BATTERY=$(echo "$BATTERY_RAW" | grep -Eo '[0-9]+%' | head -n1)
fi

VM_STAT=$(vm_stat)
PAGE_SIZE=$(echo "$VM_STAT" | awk '/page size of/ {print $8}' | sed 's/\.//')
PAGES_ACTIVE=$(echo "$VM_STAT" | awk '/Pages active/ {print $3}' | sed 's/\.//')
PAGES_WIRED=$(echo "$VM_STAT" | awk '/Pages wired down/ {print $4}' | sed 's/\.//')
PAGES_COMPRESSED=$(echo "$VM_STAT" | awk '/Pages occupied by compressor/ {print $5}' | sed 's/\.//')
RAM_USED=$(( (PAGES_ACTIVE + PAGES_WIRED + PAGES_COMPRESSED) * PAGE_SIZE / 1024 / 1024 ))
RAM_TOTAL=$(sysctl -n hw.memsize)
RAM_TOTAL=$((RAM_TOTAL / 1024 / 1024))
RAM_PERCENT=$(( RAM_USED * 100 / RAM_TOTAL ))
DF_ROOT_STATS=$(df -m /)
DISK_TOTAL_RAW=$(echo "$DF_ROOT_STATS" | awk 'NR==2{print $2}')
DISK_ROOT_USED_RAW=$(echo "$DF_ROOT_STATS" | awk 'NR==2{print $3}')
DISK_DATA_USED_RAW=$(df -m /System/Volumes/Data | awk 'NR==2{print $3}')

if command -v memory_pressure >/dev/null 2>&1; then
  MEM_FREE_PERCENT=$(memory_pressure | awk '/System-wide memory free percentage/ {gsub("%",""); print $5}')
else
  MEM_FREE_PERCENT=0
fi

MEM_FREE_PERCENT=${MEM_FREE_PERCENT:-0}
MEM_PRESSURE=$((100 - MEM_FREE_PERCENT))
SWAP_USED_RAW=$(sysctl vm.swapusage | sed -E 's/.*used = ([0-9.]+[MG]).*/\1/')
SWAP_TOTAL_RAW=$(sysctl vm.swapusage | sed -E 's/.*total = ([0-9.]+[MG]).*/\1/')
SWAP_USED=$(convert_to_mb $SWAP_USED_RAW)
SWAP_TOTAL=$(convert_to_mb $SWAP_TOTAL_RAW)

if (( SWAP_TOTAL == 0 )); then
  SWAP_PERCENT=0
else
  SWAP_PERCENT=$(awk "BEGIN {printf \"%.0f\", $SWAP_USED*100/$SWAP_TOTAL}")
fi

DISK_TOTAL=$DISK_TOTAL_RAW
DISK_USED=$(( DISK_ROOT_USED_RAW + DISK_DATA_USED_RAW ))
[[ $DISK_TOTAL -eq 0 ]] && DISK_TOTAL=1
DISK_PERCENT=$(( DISK_USED * 100 / DISK_TOTAL ))

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

echo ""
echo -e "${BLUE}Welcome To Use Meow-Meow Terminal!${RESET}"
IDX=$(( 1 + RANDOM % ${#WELCOMES[@]} ))
WELCOME=${WELCOMES[IDX]}
echo -e "${CYAN}As an cat Meowing:${RESET}${ORANGE}${WELCOME}${RESET}"
echo ""

if [ "$USER" = "root" ]; then
    CAT_1="   /\\_/\\
  ( ⊙ʌ⊙ )"
    CAT_2="    /\\_/\\
   ( ⊙ʌ⊙ )"

    CAT_1_TAIL=" ʔ/ づ づ"
    CAT_2_TAIL="   づ づ  \\ʃ"

    CAT_1_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
    CAT_2_TEXT="${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"

else
    CAT_1="   /\\_/\\
  ( ≧ω≦ )"
    CAT_2="    /\\_/\\
   ( OωO )"

    CAT_1_TAIL=" ʔ/ づ づ"
    CAT_2_TAIL="   づ づ  \\ʃ"
    CAT_1_TEXT="${PINK} Kimochiii!${RESET}"
    CAT_2_TEXT="${BLUE}  Kawayiii!${RESET}"
fi

paste <(echo "$CAT_1"; echo "$CAT_1_TAIL"; echo "$CAT_1_TEXT") \
      <(echo "$CAT_2"; echo "$CAT_2_TAIL"; echo "$CAT_2_TEXT") |
while IFS=$'\t' read -r left right; do
    printf "%s\t%s\n" "$left" "$right"
done

echo ""

if [ "$USER" = "root" ]; then
    USER_NAME="${RED}💀powerful master${RESET}"

    echo -e "${CYAN}Cat whispers: Your username is $USER_NAME... oh no!${RESET}"
    echo -e "${RED}Cat is scared! ${RESET}"
    echo -e "${YELLOW}⚠ Please don't delete the system, ${RED}powerful master${YELLOW}...${RESET}"
    echo -e "${YELLOW}⚠ rm -rf / is not a toy! That is Not Fun!${RESET}"
    echo -e "${CYAN}Cat hides behind the keyboard...${RED}Please...Don't delete meow....${RESET}"
else
    USER_NAME="${YELLOW}$USER${RESET}"
    echo -e "${CYAN}Cat whispers: Your username is $USER_NAME, got it?${RESET}"
fi

echo -e "${CYAN}Cat sniffed the machine: Hostname ${YELLOW}$HOST_NAME${CYAN}${RESET}"
echo -e "${CYAN}Cat looked around your IP: ${YELLOW}$IP_ADDR${RESET}"
echo -e "${CYAN}Cat looked, Terminal uptime is: ${YELLOW}$UP_TIME${RESET}"

if [ -n "$BATTERY" ]; then
  BAT_VAL=${BATTERY%\%}

  if (( BAT_VAL < 20 )); then
    BAT_COLOR=$RED
    BAT_TEXT="Cat wants to remind you to charge your Mac!"
  elif (( BAT_VAL < 50 )); then
    BAT_COLOR=$ORANGE
    BAT_TEXT="Keep a nice storage!"
  else
    BAT_COLOR=$GREEN
    BAT_TEXT="Have a nice meowing day！"
  fi

  echo -e "${CYAN}Battery level: ${BAT_COLOR}$BATTERY${CYAN}, ${BAT_TEXT}${RESET}"
fi

echo ""

draw_bar() {
  local percent=$1
  local width=20
  ((percent>100)) && percent=100
  ((percent<0)) && percent=0

  local fill=$(( percent * width / 100 ))
  local empty=$(( width - fill ))

  local bar=""

  for ((i=0; i<fill; i++)); do
    bar+="█"
  done

  for ((i=0; i<empty; i++)); do
    bar+="░"
  done

  printf "%s" "$bar"
}

CPU_BAR=$(draw_bar $CPU_USAGE)
RAM_BAR=$(draw_bar $RAM_PERCENT)
DISK_BAR=$(draw_bar $DISK_PERCENT)
MEM_BAR=$(draw_bar $MEM_PRESSURE)

CPU_COLOR=$(get_color $CPU_USAGE)
RAM_COLOR=$(get_color $RAM_PERCENT)
DISK_COLOR=$(get_color $DISK_PERCENT)
MEM_COLOR=$(get_color $MEM_PRESSURE)

RAINBOW_COLORS=(31 33 32 36 34 35)

color_line() {
  local line="$1"
  local index="$2"
  local color=${RAINBOW_COLORS[$((index % ${#RAINBOW_COLORS[@]}))]}
  echo -e "\033[${color}m${line}\033[0m"
}


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

MAC_ART_BOOK=()
i=0
for line in "${RAW_ART[@]}"; do
  MAC_ART_BOOK+=("$(color_line "$line" $i)")
  ((i++))
done

ART=("${MAC_ART_BOOK[@]}")

INFO_LINES=()
INFO_LINES+=("$(echo -e "${BLUE}${MODEL_NAME} (${CHIP}/${ARCH})${RESET} ${DIM}-${RESET} ${LIGHT_GREEN}${USER}${RESET}@${LIGHT_GREEN}${HOST_NAME}${RESET}")")
INFO_LINES+=("$(echo -e "${DIM}========================================${RESET}")")
INFO_LINES+=("$(echo -e "${CYAN}CPU Usage: ${CPU_COLOR}$CPU_BAR $CPU_USAGE%${RESET}")")
INFO_LINES+=("$(echo -e "${CYAN}RAM Usage: ${RAM_COLOR}$RAM_BAR $RAM_PERCENT% ($RAM_USED/${RAM_TOTAL} MB)${RESET}")")
INFO_LINES+=("$(echo -e "${CYAN}Disk Usage: ${DISK_COLOR}$DISK_BAR $DISK_PERCENT% ($DISK_USED/${DISK_TOTAL} MB)${RESET}")")
INFO_LINES+=("$(echo -e "${CYAN}Memory Pressure: ${MEM_COLOR}${MEM_BAR} ${MEM_PRESSURE}%${RESET}")")

if (( SWAP_TOTAL > 0 && SWAP_USED > 0 )); then
  SWAP_BAR=$(draw_bar $SWAP_PERCENT)
  SWAP_COLOR=$(get_color $SWAP_PERCENT)

  INFO_LINES+=("$(echo -e "${CYAN}Swap Usage: ${SWAP_COLOR}${SWAP_BAR} ${SWAP_PERCENT}% (${SWAP_USED}/${SWAP_TOTAL} MB)${RESET}")")
fi

for ((i=0; i<${#ART[@]}; i++)); do
  LEFT="${ART[$i]}"
  RIGHT="${INFO_LINES[$i]:-}"
  printf "%-35s %s\n" "$LEFT" "$RIGHT"
done

echo ""

echo -e "${DIM}============================================================${RESET}"
echo ""

if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
else
  echo -e "${MAGENTA}fastfetch not installed${RESET}"
fi
