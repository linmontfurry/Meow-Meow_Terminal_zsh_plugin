<#
.SYNOPSIS
    Meow-Meow Terminal - 跨平台猫咪风格系统信息展示脚本
.DESCRIPTION
    移植自linmontfurry的Meow-Meow_Terminal_zsh_plugin脚本，支持 Windows，显示主机名、IP、运行时间、电池、CPU/内存/磁盘使用率，
    并随机显示猫咪欢迎语和 ASCII 艺术。
.NOTES
    需要 PowerShell 7+ 以获得最佳 ANSI 颜色支持。
    在 Windows 上建议使用 Windows Terminal 或 VS Code 终端。
     Github@xiaohuangbo
#>

# ---------- 颜色定义 ----------
$RESET   = "`e[0m"
$PINK    = "`e[1;35m"
$CYAN    = "`e[38;5;51m"
$YELLOW  = "`e[38;5;226m"
$MAGENTA = "`e[38;5;201m"
$GREEN   = "`e[38;5;46m"
$ORANGE  = "`e[38;5;208m"
$WHITE   = "`e[38;5;15m"
$BLUE    = "`e[1;34m"
$RED     = "`e[1;31m"

# ---------- 辅助函数 ----------
function Is-Admin {
    # 检测当前是否具有管理员权限（Windows 上类似 root）
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal] $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Convert-DiskToMB {
    param([string]$val)
    if ($val -match '^(\d+(?:\.\d+)?)G$') {
        return [math]::Floor([double]$matches[1] * 1024)
    } elseif ($val -match '^(\d+(?:\.\d+)?)M$') {
        return [math]::Floor([double]$matches[1])
    } elseif ($val -match '^(\d+(?:\.\d+)?)K$') {
        return [math]::Floor([double]$matches[1] / 1024)
    } else {
        return 0
    }
}

function Draw-Bar {
    param([int]$percent)
    if ($percent -gt 100) { $percent = 100 }
    if ($percent -lt 0)   { $percent = 0 }
    $width = 40
    $fill = [math]::Floor($percent * $width / 100)
    $empty = $width - $fill
    $bar = ('█' * $fill) + ('░' * $empty)
    return $bar
}

# ---------- 获取系统信息（跨平台） ----------
$HOST_NAME = $env:COMPUTERNAME
if (-not $HOST_NAME) { $HOST_NAME = & hostname 2>$null }
if (-not $HOST_NAME) { $HOST_NAME = 'Unknown' }

# IP 地址（取第一个非回环 IPv4 地址）
$IP_ADDR = 'N/A'
if ($IsWindows) {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue |
          Where-Object { $_.InterfaceAlias -notlike '*Loopback*' } |
          Select-Object -First 1
    if ($ip) { $IP_ADDR = $ip.IPAddress }
} else {
    $IP_ADDR = & ipconfig getifaddr en0 2>$null
    if (-not $IP_ADDR) { $IP_ADDR = 'N/A' }
}

# 系统运行时间
if ($IsWindows) {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $bootTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $bootTime
    $UP_TIME = "$($uptime.Days)天 $($uptime.Hours)小时 $($uptime.Minutes)分钟"
} else {
    $uptimeRaw = & uptime
    if ($uptimeRaw -match 'up\s+(.+?)(?:,\s+\d+ users|$)') {
        $UP_TIME = $matches[1].Trim()
    } else {
        $UP_TIME = 'unknown'
    }
}

# 电池百分比
$BATTERY = 'N/A'
if ($IsWindows) {
    $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
    if ($battery -and $battery.EstimatedChargeRemaining) {
        $BATTERY = "$($battery.EstimatedChargeRemaining)%"
    }
} else {
    $BATTERY = & pmset -g batt 2>$null | Select-String -Pattern '\d+%' | ForEach-Object { $_.Matches.Value } | Select-Object -First 1
    if (-not $BATTERY) { $BATTERY = 'N/A' }
}

# CPU 使用率
$CPU_USAGE = 0
if ($IsWindows) {
    # 使用 Get-Counter 获取瞬时 CPU 使用率
    $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
    if ($cpuCounter) {
        $CPU_USAGE = [math]::Round($cpuCounter.CounterSamples.CookedValue)
    }
} else {
    $topOut = & top -l 1 2>$null
    if ($topOut -match 'CPU usage:\s+([\d\.]+)%\s+user,\s+([\d\.]+)%\s+sys') {
        $CPU_USAGE_RAW = [double]$matches[1] + [double]$matches[2]
        $CPU_USAGE = [math]::Floor($CPU_USAGE_RAW)
    }
}

# 内存信息
$RAM_USED = 0
$RAM_TOTAL = 0
$RAM_PERCENT = 0
if ($IsWindows) {
    $mem = Get-CimInstance Win32_OperatingSystem
    $RAM_TOTAL = [math]::Floor($mem.TotalVisibleMemorySize / 1024)   # MB
    $RAM_FREE  = [math]::Floor($mem.FreePhysicalMemory / 1024)
    $RAM_USED  = $RAM_TOTAL - $RAM_FREE
    if ($RAM_TOTAL -gt 0) {
        $RAM_PERCENT = [math]::Floor($RAM_USED * 100 / $RAM_TOTAL)
    }
} else {
    $vmstat = & vm_stat
    $pageSizeMatch = [regex]::Match($vmstat, 'page size of (\d+)')
    $pagesActiveMatch = [regex]::Match($vmstat, 'Pages active:\s+(\d+)')
    $pagesWiredMatch  = [regex]::Match($vmstat, 'Pages wired down:\s+(\d+)')
    if ($pageSizeMatch.Success -and $pagesActiveMatch.Success -and $pagesWiredMatch.Success) {
        $PAGE_SIZE = $pageSizeMatch.Groups[1].Value -as [int]
        $PAGES_ACTIVE = $pagesActiveMatch.Groups[1].Value -as [int]
        $PAGES_WIRED  = $pagesWiredMatch.Groups[1].Value -as [int]
        $RAM_USED = [math]::Floor(($PAGES_ACTIVE + $PAGES_WIRED) * $PAGE_SIZE / 1024 / 1024)
    }
    $RAM_TOTAL = [math]::Floor((& sysctl -n hw.memsize 2>$null) / 1024 / 1024)
    if ($RAM_TOTAL -gt 0) {
        $RAM_PERCENT = [math]::Floor($RAM_USED * 100 / $RAM_TOTAL)
    }
}

# 磁盘信息（系统盘）
$DISK_TOTAL = 0
$DISK_USED = 0
$DISK_PERCENT = 0
if ($IsWindows) {
    $drive = Get-PSDrive -Name 'C' -ErrorAction SilentlyContinue
    if ($drive) {
        $DISK_TOTAL = [math]::Floor($drive.Used + $drive.Free) / 1MB
        $DISK_USED  = [math]::Floor($drive.Used / 1MB)
        if ($DISK_TOTAL -gt 0) {
            $DISK_PERCENT = [math]::Floor($DISK_USED * 100 / $DISK_TOTAL)
        }
    }
} else {
    $dfOut = & df -H / 2>$null | Select-Object -Skip 1
    if ($dfOut) {
        $fields = $dfOut -split '\s+'
        $DISK_TOTAL_RAW = $fields[1]
        $DISK_USED_RAW  = $fields[2]
        $DISK_TOTAL = Convert-DiskToMB $DISK_TOTAL_RAW
        $DISK_USED  = Convert-DiskToMB $DISK_USED_RAW
        if ($DISK_TOTAL -eq 0) { $DISK_TOTAL = 1 }
        $DISK_PERCENT = [math]::Floor($DISK_USED * 100 / $DISK_TOTAL)
    }
}

# ---------- 欢迎语数组（与原脚本完全相同） ----------
$WELCOMES = @(
    "Welcome back!", "Hello human!", "Kawaii typing detected!", "Cat says great!",
    "Have a purrfect day!", "Meow meow!", "You look comfy!", "Let's code!",
    "Paws activated!", "Cuteness overload!", "Enjoy your terminal!", "Feline power!",
    "Stay cozy!", "Time to hack!", "Cat inspected!", "All systems purrfect!",
    "Hello world, meow!", "Cat mode on!", "Stay pawsitive!", "Kitty approves your change!",
    "Make meow changes!", "Git commit approved by cat!", "Deploying cuteness...",
    "Terminal purrformance optimal!", "Cat detected hacker energy!", "Linting your code with paws...",
    "Compiling meowdule...", "Debugging with whiskers...", "Running pawcess...",
    "Cat watching your commits.", "Code review by kitty complete!", "System check: purrfect!",
    "Whiskers calibrated.", "Claws ready for coding!", "Keyboard warmed by paws.",
    "Terminal smells like productivity.", "Coffee detected. Coding likely.",
    "Cat supervising development.", "Boot sequence approved by cat.", "Purrmission granted!",
    "Terminal ready. Meow!", "Cat scanned the system.", "No bugs detected (cat hopes lol).",
    "Whiskers sense good code.", "Purrcess initialized.", "Shell opened successfully.",
    "Cat guarding the terminal.", "Keep coding, human.", "Terminal looks cozy today.",
    "Meowgic detected!", "Your code smells interesting.", "Another day, another commit.",
    "Cat recommends more snacks.", "Human detected at keyboard.", "Stay focused, stay pawsitive.",
    "Whisker-driven development.", "Code like a feline.", "System uptime approved.",
    "Cat believes in your code.", "Meow is a good time to code.", "Paws on keyboard!"
)

# ---------- 输出欢迎头部 ----------
Write-Host ""
Write-Host "${BLUE}Welcome To Use Meow-Meow Terminal!${RESET}"
$IDX = Get-Random -Minimum 0 -Maximum $WELCOMES.Length
$WELCOME = $WELCOMES[$IDX]
Write-Host "${CYAN}As an cat Meowing:${RESET}${ORANGE}${WELCOME}${RESET}"
Write-Host ""

# ---------- 猫图案（根据管理员权限切换） ----------
$isAdmin = Is-Admin
if ($isAdmin) {
    $CAT_1 = @"
   /\_/\
  ( ⊙ʌ⊙ )
"@
    $CAT_2 = @"
  /\_/\
   ( ⊙ʌ⊙ )
"@
    $CAT_1_TAIL = " ʔ/ づ づ"
    $CAT_2_TAIL = "   づ づ  \ʃ"
    $CAT_1_TEXT = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
    $CAT_2_TEXT = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
} else {
    $CAT_1 = @"
    /\_/\
  ( ≧ω≦ )
"@
    $CAT_2 = @"
     /\_/\
   ( OωO )
"@
    $CAT_1_TAIL = " ʔ/ づ づ"
    $CAT_2_TAIL = "   づ づ  \ʃ"
    $CAT_1_TEXT = "${PINK} Kimochiii!${RESET}"
    $CAT_2_TEXT = "${BLUE}  Kawayiii!${RESET}"
}
# ---------- 猫图案对齐（保留右猫原始格式，固定起始列） ----------
# 拆分左猫和右猫为行数组（保留所有空格）
$leftBody = $CAT_1.TrimEnd() -split "`r?`n" | Where-Object { $_ -ne '' }
$rightBody = $CAT_2.TrimEnd() -split "`r?`n" | Where-Object { $_ -ne '' }

# 确保都有至少2行（耳朵和脸）
if ($leftBody.Count -ge 2 -and $rightBody.Count -ge 2) {
    # 构建完整的左右行数组（耳朵、脸、尾巴、文字）
    $leftLines = @($leftBody[0], $leftBody[1], $CAT_1_TAIL, $CAT_1_TEXT)
    $rightLines = @($rightBody[0], $rightBody[1], $CAT_2_TAIL, $CAT_2_TEXT)
    
    # 计算左列最大可视宽度（去除 ANSI 颜色码）
    $maxLeftLen = 0
    foreach ($line in $leftLines) {
        $visible = $line -replace "\e\[[\d;]+m", ""
        if ($visible.Length -gt $maxLeftLen) { $maxLeftLen = $visible.Length }
    }
    
    # 左右猫之间的间隔（请根据需要调整空格数量，例如 '    ' 或 '        '）
    $separator = '     '   # 当前为8个空格，让右猫更靠右
    
    for ($i = 0; $i -lt $leftLines.Count; $i++) {
        $left = $leftLines[$i]
        $right = $rightLines[$i]
        $leftVisible = $left -replace "\e\[[\d;]+m", ""
        $padding = ' ' * ($maxLeftLen - $leftVisible.Length)
        Write-Host ("{0}{1}{2}{3}" -f $left, $padding, $separator, $right)
    }
} else {
    # 备用方案：直接输出原始图案
    Write-Host $CAT_1
    Write-Host $CAT_1_TAIL
    Write-Host $CAT_1_TEXT
    Write-Host ""
    Write-Host $CAT_2
    Write-Host $CAT_2_TAIL
    Write-Host $CAT_2_TEXT
}
Write-Host ""
Write-Host ""

# ---------- 用户信息与警告 ----------
if ($isAdmin) {
    $USER_NAME = "${RED}💀powerful master${RESET}"
    Write-Host "${CYAN}Cat whispers: Your username is $USER_NAME... oh no!${RESET}"
    Write-Host "${RED}Cat is scared! ${RESET}"
    Write-Host "${YELLOW}⚠ Please don't delete the system, ${RED}powerful master${YELLOW}...${RESET}"
    Write-Host "${YELLOW}⚠ Remove-Item -Path C:\* -Recurse -Force is not a toy! That is Not Fun!${RESET}"
    Write-Host "${CYAN}Cat hides behind the keyboard...${RED}Please...Don't delete meow....${RESET}"
} else {
    $USER_NAME = "${YELLOW}$env:USERNAME${RESET}"
    Write-Host "${CYAN}Cat whispers: Your username is $USER_NAME, got it?${RESET}"
}

Write-Host "${CYAN}Cat sniffed the machine: Hostname ${YELLOW}$HOST_NAME${CYAN}${RESET}"
Write-Host "${CYAN}Cat looked around your IP: ${YELLOW}$IP_ADDR${RESET}"
Write-Host "${CYAN}Cat looked, Terminal uptime is: ${YELLOW}$UP_TIME${RESET}"
Write-Host "${CYAN}Battery level: ${YELLOW}$BATTERY${CYAN}, keep a nice storage!${RESET}"
Write-Host ""

# ---------- 资源使用率及进度条 ----------
$CPU_BAR  = Draw-Bar $CPU_USAGE
$RAM_BAR  = Draw-Bar $RAM_PERCENT
$DISK_BAR = Draw-Bar $DISK_PERCENT

Write-Host "${CYAN}CPU Usage: ${YELLOW}$CPU_BAR $CPU_USAGE%${RESET}"
Write-Host "${CYAN}RAM Usage: ${YELLOW}$RAM_BAR $RAM_PERCENT% ($RAM_USED/${RAM_TOTAL} MB)${RESET}"
Write-Host "${CYAN}Disk Usage: ${YELLOW}$DISK_BAR $DISK_PERCENT% ($DISK_USED/${DISK_TOTAL} MB)${RESET}"
Write-Host ""

Write-Host "`e[38;5;240m============================================================${RESET}"
Write-Host ""

# ---------- neofetch / flashfetch 兼容（可选） ----------
if (Get-Command neofetch -ErrorAction SilentlyContinue) {
    & neofetch
} elseif (Get-Command flashfetch -ErrorAction SilentlyContinue) {
    & flashfetch -c all.jsonc
} else {
    Write-Host "${MAGENTA}neofetch or flashfetch not installed${RESET}"
}