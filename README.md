# Meow-Meow_Terminal_zsh_plugin
✨ 可爱，简洁的minifetch+终端开篇文本方案

# 使用方法

目前所有脚本支持大部分主流 Linux (特殊BusyBox或者Alpine Linux可能出现兼容问题) Mac OS 系列和 Microsoft Windows Powershell7以上的操作系统

使用其他非主流系统安装上去这个可能会出现兼容性问题

将仓库内对应系统的脚本文件下载复制

Linux或者MacOS系统，请确保你的系统安装了 `zsh` 并且设置为默认终端，这样即可获得更加完整的体验

对于Windows系统，请确保你安装了 `Chocolatey`

无论是任何系统，使用本项目前最好都要安装 fastfetch 来兼容相关参数工作

粘贴仓库内的对应系统的脚本文件内容，放入用户目录下的 `.zshrc` 文件，重启终端即可安装完成

## Oh My Zsh 用户安装方法

如果你已经安装了 Oh My Zsh，你可以按照以下步骤作为自定义插件安装：

1. 创建插件目录：
   ```bash
   mkdir -p "${ZSH_CUSTOM:-$ZSH/custom}"/plugins/meow-meow
   ```
2. 下载脚本到该插件目录：
   ```bash
   curl -L https://raw.githubusercontent.com/linmontfurry/Meow-Meow_Terminal_zsh_plugin/refs/heads/main/zshrc.sh -o "${ZSH_CUSTOM:-$ZSH/custom}"/plugins/meow-meow/meow-meow.plugin.zsh
   ```
3. 修改 `~/.zshrc`，在 `plugins` 列表中加上 `meow-meow`：
   ```bash
   plugins=(
       # ... 其他插件
       meow-meow
   )
   ```

4. 保存并重启终端, 或者:
   ```bash
   omz reload # or source ~/.zshrc
   ```

*参考资料：[Oh My Zsh Customization - Overriding and adding plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Customization#overriding-and-adding-plugins)*

## Windows 用户安装方法
1. 安装Powershell7

安装教程：https://learn.microsoft.com/zh-cn/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5

2. 打开powershell7并安装fastfetch
 ``` winget install fastfetch 
 ```

3. 下载本项目并解压
Code-Download ZIP

4. 将powershell7切换到解压目录并运行
 ``` cd [解压目录]
.\index2.ps1
 ```

# TODO list

- 让最小化实现的 minifetch 更强大
- 准备多系统类型的 ASCII 图标
- ......

# 开源协议

本仓库使用 MIT 开源，其他内容不再概述

如果有相关建议请发表 issues 提供建议
