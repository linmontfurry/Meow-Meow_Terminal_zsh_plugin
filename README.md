# Meow-Meow_Terminal_zsh_plugin
✨ 可爱，简洁的minifetch+终端开篇文本方案

# 使用方法

目前暂时只支持 Mac OS 系列版本，使用其他系统安装这个可能会出现兼容性问题

将仓库内 `zshrc.sh` 文件复制所有的内容

请确保你的系统安装了 `zsh` 并且设置为默认终端

使用 `vim ~/.zshrc` 粘贴仓库内的 `zshrc.sh` 文件，重启安装即可

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

*参考资料：[Oh My Zsh Customization - Overriding and adding plugins](https://github.com/ohmyzsh/ohmyzsh/wiki/Customization#overriding-and-adding-plugins)*

# TODO list

- 增加对 Linux 的兼容
- 让最小化实现的 minifetch 更强大
- 添加其他 Mac 机器类型的 ASCII 图标
- ......

# 开源协议

本仓库使用 MIT 开源，其他内容不再概述

如果有相关建议请发表 issues 提供建议
