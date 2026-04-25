$ErrorActionPreference = 'SilentlyContinue'

$RESET = "$([char]27)[0m"
$PINK = "$([char]27)[1;35m"
$CYAN = "$([char]27)[38;5;51m"
$YELLOW = "$([char]27)[38;5;226m"
$MAGENTA = "$([char]27)[38;5;201m"
$GREEN = "$([char]27)[38;5;46m"
$ORANGE = "$([char]27)[38;5;208m"
$BLUE = "$([char]27)[1;34m"
$DIM = "$([char]27)[2m"
$LIGHT_GREEN = "$([char]27)[38;5;120m"
$RED = "$([char]27)[1;31m"

function Write-MeowLine {
    param([string]$Text = '')
    Write-Host $Text
}

function Get-Color {
    param([int]$Percent = 0)

    if ($Percent -ge 80) { return $RED }
    if ($Percent -ge 60) { return $ORANGE }
    if ($Percent -ge 30) { return $YELLOW }
    return $GREEN
}

function Draw-Bar {
    param([int]$Percent = 0)

    $width = 18
    if ($Percent -gt 100) { $Percent = 100 }
    if ($Percent -lt 0) { $Percent = 0 }

    $fill = [math]::Floor($Percent * $width / 100)
    $empty = $width - $fill

    return ('█' * $fill) + ('░' * $empty)
}

function Format-BytesToMB {
    param([double]$Bytes = 0)
    return [math]::Round($Bytes / 1MB)
}

function Format-Uptime {
    param([datetime]$BootTime)

    if (-not $BootTime) { return 'N/A' }

    $span = (Get-Date) - $BootTime
    $parts = @()

    if ($span.Days -gt 0) { $parts += "$($span.Days)d" }
    if ($span.Hours -gt 0) { $parts += "$($span.Hours)h" }
    if ($span.Minutes -gt 0) { $parts += "$($span.Minutes)m" }
    if ($parts.Count -eq 0) { $parts += 'less than a minute' }

    return ($parts -join ' ')
}

function Get-PrimaryIPv4 {
    $ip = $null

    try {
        $ip = Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object {
                $_.IPAddress -notmatch '^127\.' -and
                $_.IPAddress -notmatch '^169\.254\.' -and
                $_.PrefixOrigin -ne 'WellKnown'
            } |
            Sort-Object -Property InterfaceMetric, SkipAsSource |
            Select-Object -ExpandProperty IPAddress -First 1
    } catch {
    }

    if (-not $ip) {
        try {
            $ip = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                Where-Object { $_.OperationalStatus -eq 'Up' } |
                ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
                Where-Object {
                    $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
                    $_.Address.IPAddressToString -notmatch '^127\.' -and
                    $_.Address.IPAddressToString -notmatch '^169\.254\.'
                } |
                Select-Object -ExpandProperty Address -First 1 |
                ForEach-Object { $_.IPAddressToString }
        } catch {
        }
    }

    if (-not $ip) { $ip = 'N/A' }
    return $ip
}

function Get-BatteryPercentage {
    try {
        $battery = Get-CimInstance Win32_Battery | Select-Object -First 1
        if ($battery -and $null -ne $battery.EstimatedChargeRemaining) {
            return "$($battery.EstimatedChargeRemaining)%"
        }
    } catch {
    }

    return ''
}

function Get-CpuUsage {
    try {
        $counter = Get-Counter '\Processor(_Total)\% Processor Time'
        $value = [int][math]::Round($counter.CounterSamples[0].CookedValue)
        if ($value -lt 0) { $value = 0 }
        if ($value -gt 100) { $value = 100 }
        return $value
    } catch {
        return 0
    }
}

function Get-MemoryStats {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMB = [int][math]::Round([double]$os.TotalVisibleMemorySize / 1024)
        $freeMB = [int][math]::Round([double]$os.FreePhysicalMemory / 1024)
        $usedMB = [math]::Max(0, $totalMB - $freeMB)
        $percent = if ($totalMB -gt 0) { [int][math]::Round(($usedMB * 100) / $totalMB) } else { 0 }

        return [pscustomobject]@{
            UsedMB   = $usedMB
            TotalMB  = $totalMB
            Percent  = $percent
        }
    } catch {
        return [pscustomobject]@{
            UsedMB   = 0
            TotalMB  = 0
            Percent  = 0
        }
    }
}

function Get-SwapStats {
    try {
        $pageFiles = @(Get-CimInstance Win32_PageFileUsage)
        if ($pageFiles.Count -eq 0) {
            return [pscustomobject]@{
                UsedMB  = 0
                TotalMB = 0
                Percent = 0
            }
        }

        $usedMB = [int](($pageFiles | Measure-Object -Property CurrentUsage -Sum).Sum)
        $totalMB = [int](($pageFiles | Measure-Object -Property AllocatedBaseSize -Sum).Sum)
        $percent = if ($totalMB -gt 0) { [int][math]::Round(($usedMB * 100) / $totalMB) } else { 0 }

        return [pscustomobject]@{
            UsedMB  = $usedMB
            TotalMB = $totalMB
            Percent = $percent
        }
    } catch {
        return [pscustomobject]@{
            UsedMB  = 0
            TotalMB = 0
            Percent = 0
        }
    }
}

function Get-DiskStats {
    $results = @()

    try {
        $drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" |
            Sort-Object DeviceID

        foreach ($drive in $drives) {
            $sizeBytes = [double]$drive.Size
            $freeBytes = [double]$drive.FreeSpace
            $usedBytes = [math]::Max(0, $sizeBytes - $freeBytes)
            $totalMB = Format-BytesToMB $sizeBytes
            $usedMB = Format-BytesToMB $usedBytes
            $percent = if ($totalMB -gt 0) { [int][math]::Round(($usedMB * 100) / $totalMB) } else { 0 }

            $results += [pscustomobject]@{
                Name    = $drive.DeviceID
                UsedMB  = $usedMB
                TotalMB = $totalMB
                Percent = $percent
            }
        }
    } catch {
    }

    return $results
}

function Get-GpuStats {
    $gpuStats = @()
    $nameMap = @{}

    try {
        $controllers = Get-CimInstance Win32_VideoController |
            Where-Object { $_.Name -and $_.AdapterRAM -gt 0 }

        $index = 0
        foreach ($controller in $controllers) {
            $nameMap[$index] = $controller.Name
            $gpuStats += [pscustomobject]@{
                Index   = $index
                Name    = $controller.Name
                Usage   = $null
                Source  = 'adapter'
            }
            $index++
        }
    } catch {
    }

    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage').CounterSamples |
            Where-Object {
                $_.InstanceName -match 'engtype_' -and
                $_.CookedValue -ge 0
            }

        if ($samples.Count -gt 0) {
            $usageByGpu = @{}

            foreach ($sample in $samples) {
                if ($sample.InstanceName -match 'phys_([0-9]+)') {
                    $gpuIndex = [int]$matches[1]
                    if (-not $usageByGpu.ContainsKey($gpuIndex)) {
                        $usageByGpu[$gpuIndex] = 0.0
                    }
                    $usageByGpu[$gpuIndex] += [double]$sample.CookedValue
                }
            }

            foreach ($gpuIndex in $usageByGpu.Keys) {
                $usage = [int][math]::Round([math]::Min($usageByGpu[$gpuIndex], 100))
                $name = if ($nameMap.ContainsKey($gpuIndex)) { $nameMap[$gpuIndex] } else { "GPU $gpuIndex" }

                $existing = $gpuStats | Where-Object { $_.Index -eq $gpuIndex } | Select-Object -First 1
                if ($existing) {
                    $existing.Usage = $usage
                    $existing.Source = 'counter'
                } else {
                    $gpuStats += [pscustomobject]@{
                        Index   = $gpuIndex
                        Name    = $name
                        Usage   = $usage
                        Source  = 'counter'
                    }
                }
            }
        }
    } catch {
    }

    return $gpuStats | Sort-Object Index
}

function Color-Line {
    param(
        [string]$Line,
        [int]$Index
    )

    $rainbowColors = @(31, 33, 32, 36, 34, 35)
    $color = $rainbowColors[$Index % $rainbowColors.Count]
    return "$([char]27)[$color" + "m$Line$([char]27)[0m"
}

$computerSystem = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$hostName = $env:COMPUTERNAME
$arch = $env:PROCESSOR_ARCHITECTURE
$modelName = if ($computerSystem.Model) { $computerSystem.Model } else { 'Windows Machine' }
$chip = (Get-CimInstance Win32_Processor | Select-Object -ExpandProperty Name -First 1)
if (-not $chip) { $chip = 'Unknown CPU' }
$ipAddr = Get-PrimaryIPv4
$uptime = Format-Uptime $operatingSystem.LastBootUpTime
$battery = Get-BatteryPercentage
$cpuUsage = Get-CpuUsage
$memory = Get-MemoryStats
$swap = Get-SwapStats
$disks = @(Get-DiskStats)
$gpuStats = @(Get-GpuStats)

$welcomes = @(
    'Welcome back!',
    'Hello human!',
    'Kawaii typing detected!',
    'Cat says great!',
    'Have a purrfect day!',
    'Meow meow!',
    'You look comfy!',
    "Let's code!",
    'Paws activated!',
    'Cuteness overload!',
    'Enjoy your terminal!',
    'Feline power!',
    'Stay cozy!',
    'Time to hack!',
    'Cat inspected!',
    'All systems purrfect!',
    'Hello world, meow!',
    'Cat mode on!',
    'Stay pawsitive!',
    'Kitty approves your change!',
    'Make meow changes!',
    'Git commit approved by cat!',
    'Deploying cuteness...',
    'Terminal purrformance optimal!',
    'Cat detected hacker energy!',
    'Linting your code with paws...',
    'Compiling meowdule...',
    'Debugging with whiskers...',
    'Running pawcess...',
    'Cat watching your commits.',
    'Code review by kitty complete!',
    'System check: purrfect!',
    'Whiskers calibrated.',
    'Claws ready for coding!',
    'Keyboard warmed by paws.',
    'Terminal smells like productivity.',
    'Coffee detected. Coding likely.',
    'Cat supervising development.',
    'Boot sequence approved by cat.',
    'Purrmission granted!',
    'Terminal ready. Meow!',
    'Cat scanned the system.',
    'No bugs detected (cat hopes lol).',
    'Whiskers sense good code.',
    'Purrcess initialized.',
    'Shell opened successfully.',
    'Cat guarding the terminal.',
    'Keep coding, human.',
    'Terminal looks cozy today.',
    'Meowgic detected!',
    'Your code smells interesting.',
    'Another day, another commit.',
    'Cat recommends more snacks.',
    'Human detected at keyboard.',
    'Stay focused, stay pawsitive.',
    'Whisker-driven development.',
    'Code like a feline.',
    'System uptime approved.',
    'Cat believes in your code.',
    'Meow is a good time to code.',
    'Paws on keyboard!'
)

$welcome = Get-Random -InputObject $welcomes

Write-MeowLine ''
Write-MeowLine "${BLUE}Welcome to Meow-Meow Terminal!${RESET}"
Write-MeowLine "${CYAN}Cat says:${RESET} ${ORANGE}${welcome}${RESET}"
Write-MeowLine ''

if ($env:USERNAME -eq 'Administrator') {
    $cat1 = @"
   /\_/\
  ( ⊙ʌ⊙ )
"@
    $cat2 = @"
    /\_/\
   ( ⊙ʌ⊙ )
"@
    $cat1Tail = ' ʔ/ づ づ'
    $cat2Tail = '   づ づ  \ʃ'
    $cat1Text = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
    $cat2Text = "${RED}SCARY!!!!! NOT FUN!!!!!${RESET}"
} else {
    $cat1 = @"
   /\_/\
  ( ≧ω≦ )
"@
    $cat2 = @"
    /\_/\
   ( OωO )
"@
    $cat1Tail = ' ʔ/ づ づ'
    $cat2Tail = '   づ づ  \ʃ'
    $cat1Text = "${PINK} Kimochiii!${RESET}"
    $cat2Text = "${BLUE}  Kawayiii!${RESET}"
}

$leftBlock = ($cat1.TrimEnd() -split "`r?`n") + $cat1Tail + $cat1Text
$rightBlock = ($cat2.TrimEnd() -split "`r?`n") + $cat2Tail + $cat2Text

for ($i = 0; $i -lt [math]::Max($leftBlock.Count, $rightBlock.Count); $i++) {
    $left = if ($i -lt $leftBlock.Count) { $leftBlock[$i] } else { '' }
    $right = if ($i -lt $rightBlock.Count) { $rightBlock[$i] } else { '' }
    Write-Host ("{0}`t{1}" -f $left, $right)
}

Write-MeowLine ''

if ($env:USERNAME -eq 'Administrator') {
    $userName = "${RED}powerful master${RESET}"
    Write-MeowLine "${CYAN}Cat whispers: your username is ${userName}${CYAN}... oh no!${RESET}"
    Write-MeowLine "${RED}Cat is scared!${RESET}"
    Write-MeowLine "${YELLOW}Please do not delete the system, ${RED}powerful master${YELLOW}...${RESET}"
    Write-MeowLine "${YELLOW}Be gentle with the machine. That is more fun!${RESET}"
    Write-MeowLine "${CYAN}Cat hides behind the keyboard... ${RED}please do not delete meow.${RESET}"
} else {
    $userName = "${YELLOW}$($env:USERNAME)${RESET}"
    Write-MeowLine "${CYAN}Cat whispers: your username is ${userName}${CYAN}, noted!${RESET}"
}

$connectionType = $null
$loginIP = $null

if ($env:SSH_CONNECTION -or $env:SSH_CLIENT -or $env:SSH_TTY) {
    $connectionType = "SSH"
    $sshInfo = if ($env:SSH_CONNECTION) { $env:SSH_CONNECTION } else { $env:SSH_CLIENT }
    $loginIP = ($sshInfo -split '\s+')[0]
} elseif ($env:TERM -match 'screen|tmux' -and (Get-Process -Id $PID).Parent.ProcessName -match 'telnet|rlogin') {
    $connectionType = "telnet"
    try {
        $netstat = netstat -an | Select-String "ESTABLISHED" | Select-String ":23\s"
        if ($netstat) {
            $loginIP = ($netstat -split '\s+')[2] -replace ':.*$', ''
        }
    } catch {
    }
}

if ($connectionType) {
    if ($loginIP) {
        Write-MeowLine "${CYAN}Cat noticed: you connected via ${MAGENTA}${connectionType}${CYAN} from ${YELLOW}${loginIP}${CYAN}, is this you?${RESET}"
    } else {
        Write-MeowLine "${CYAN}Cat noticed: you connected via ${MAGENTA}${connectionType}${CYAN} from ${YELLOW}somewhere mysterious${CYAN}...${RESET}"
    }
} else {
    $ttyInfo = "Console"
    try {
        $sessionInfo = Get-CimInstance Win32_LogonSession -Filter "LogonId='$((Get-Process -Id $PID).SessionId)'" -ErrorAction SilentlyContinue
        if ($sessionInfo) {
            $ttyInfo = "Console (Session $($sessionInfo.LogonId))"
        }
    } catch {
    }
    Write-MeowLine "${CYAN}Cat noticed: you're on local terminal ${YELLOW}${ttyInfo}${RESET}"
}

Write-MeowLine "${CYAN}Cat sniffed the machine: hostname ${YELLOW}${hostName}${RESET}"
Write-MeowLine "${CYAN}Cat checked your primary IP: ${YELLOW}${ipAddr}${RESET}"
Write-MeowLine "${CYAN}Cat checked the uptime: ${YELLOW}${uptime}${RESET}"

if ($battery) {
    $batVal = [int]($battery.TrimEnd('%'))

    if ($batVal -lt 20) {
        $batColor = $RED
        $batText = 'Battery is low. Time to plug in soon.'
    } elseif ($batVal -lt 50) {
        $batColor = $ORANGE
        $batText = 'Battery is halfway there. Still okay for now.'
    } else {
        $batColor = $GREEN
        $batText = 'Battery looks healthy. Have a nice meowing day!'
    }

    Write-MeowLine "${CYAN}Battery level: ${batColor}${battery}${CYAN}, ${batText}${RESET}"
}

Write-MeowLine ''

$cpuBar = Draw-Bar $cpuUsage
$ramBar = Draw-Bar $memory.Percent
$cpuColor = Get-Color $cpuUsage
$ramColor = Get-Color $memory.Percent

$catArt1 = @(
"       I'm hungry!  ",
"              ノ    ",
"   ／l、 _․         ",
"  /  l._/. フ       ",
" ( ﾟ⩊ ｡  . ).       ",
"  l     ~ヽ         ",
"   l      -.\   /)  ",
"   じしf_  , .)ノ/  ",
"                    ",
"                    "
)

$catArt2 = @(
"       touch me!    ",
"              ノ    ",
"   ／l、 _․         ",
"  /  l._/. フ       ",
" (.˃ ᵕ ˂. ).        ",
"  l     ~ヽ         ",
"   l      -.\   /)  ",
"   じしf_  , .)ノ/  ",
"                    ",
"                    "
)

$allCatArts = @($catArt1, $catArt2)
$rawArt = Get-Random -InputObject $allCatArts

$deviceArt = @()
for ($i = 0; $i -lt $rawArt.Count; $i++) {
    $deviceArt += (Color-Line -Line $rawArt[$i] -Index $i)
}

$infoLines = @()
$infoLines += "${BLUE}${modelName}${RESET}"
$infoLines += "${DIM}CPU:${RESET} ${YELLOW}${chip}${RESET} ${DIM}(${arch})${RESET}"
$infoLines += "${DIM}User:${RESET} ${LIGHT_GREEN}$($env:USERNAME)${RESET}@${LIGHT_GREEN}${hostName}${RESET}"
$infoLines += "${DIM}========================================${RESET}"
$infoLines += "${CYAN}CPU Usage: ${cpuColor}${cpuBar} ${cpuUsage}%${RESET}"
$infoLines += "${CYAN}RAM Usage: $(Get-Color $memory.Percent)${ramBar} $($memory.Percent)% ($($memory.UsedMB)/$($memory.TotalMB) MB)${RESET}"

if ($swap.TotalMB -gt 0) {
    $swapBar = Draw-Bar $swap.Percent
    $swapColor = Get-Color $swap.Percent
    $infoLines += "${CYAN}Swap Usage: ${swapColor}${swapBar} $($swap.Percent)% ($($swap.UsedMB)/$($swap.TotalMB) MB)${RESET}"
}

if ($gpuStats.Count -eq 1) {
    $gpu = $gpuStats[0]
    if ($null -ne $gpu.Usage) {
        $gpuBar = Draw-Bar $gpu.Usage
        $gpuColor = Get-Color $gpu.Usage
        $infoLines += "${CYAN}GPU Usage: ${gpuColor}${gpuBar} $($gpu.Usage)%${RESET}"
    }
} elseif ($gpuStats.Count -gt 1) {
    foreach ($gpu in $gpuStats) {
        if ($null -ne $gpu.Usage) {
            $gpuBar = Draw-Bar $gpu.Usage
            $gpuColor = Get-Color $gpu.Usage
            $infoLines += "${CYAN}GPU$($gpu.Index): ${gpuColor}${gpuBar} $($gpu.Usage)%${RESET}"
        } else {
            $infoLines += "${CYAN}GPU$($gpu.Index): ${YELLOW}$($gpu.Name)${RESET}"
        }
    }
}

foreach ($disk in $disks) {
    $diskBar = Draw-Bar $disk.Percent
    $diskColor = Get-Color $disk.Percent
    $infoLines += "${CYAN}Disk $($disk.Name): ${diskColor}${diskBar} $($disk.Percent)% ($($disk.UsedMB)/$($disk.TotalMB) MB)${RESET}"
}

function Get-DisplayWidth {
    param([string]$Text)

    $stripped = $Text -replace '\x1b\[[0-9;]*m', ''
    $width = 6

    for ($i = 0; $i -lt $stripped.Length; $i++) {
        $char = $stripped[$i]
        $codePoint = [int][char]$char

        if (($codePoint -ge 0x1100 -and $codePoint -le 0x115F) -or
            ($codePoint -ge 0x2329 -and $codePoint -le 0x232A) -or
            ($codePoint -ge 0x2E80 -and $codePoint -le 0x303E) -or
            ($codePoint -ge 0x3040 -and $codePoint -le 0xA4CF) -or
            ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or
            ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or
            ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE19) -or
            ($codePoint -ge 0xFE30 -and $codePoint -le 0xFE6F) -or
            ($codePoint -ge 0xFF00 -and $codePoint -le 0xFF60) -or
            ($codePoint -ge 0xFFE0 -and $codePoint -le 0xFFE6)) {
            $width += 2
        } else {
            $width += 1
        }
    }

    return $width
}

$targetWidth = 1
for ($i = 0; $i -lt $deviceArt.Count; $i++) {
    $left = $deviceArt[$i]
    $right = if ($i -lt $infoLines.Count) { $infoLines[$i] } else { '' }
    $displayWidth = Get-DisplayWidth $left
    $padding = [math]::Max(0, $targetWidth - $displayWidth)
    Write-Host ("{0}{1} {2}" -f $left, (' ' * $padding), $right)
}

Write-MeowLine ''
Write-MeowLine "${DIM}============================================================${RESET}"
Write-MeowLine ''

if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch
} else {
    Write-MeowLine "${MAGENTA}fastfetch not installed${RESET}"
}