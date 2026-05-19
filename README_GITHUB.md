# LNMP 一键安装脚本

功能完善的 LNMP（Linux + Nginx + MySQL/MariaDB + PHP）环境一键安装脚本。

## 特性

- ✅ 支持 Ubuntu 20.04/22.04/24.04
- ✅ 支持 CentOS 7/8/9
- ✅ 支持 Debian 10/11/12
- ✅ 自动版本选择（Nginx、MySQL/MariaDB、PHP）
- ✅ 自动依赖检查与安装
- ✅ 自动配置 Nginx 支持 PHP
- ✅ 自动设置开机自启动
- ✅ 自动配置防火墙
- ✅ 错误处理和回滚机制
- ✅ 安装验证测试
- ✅ 美观的中文测试页面

## 快速开始

### 1. 上传脚本到服务器

```bash
# 使用 scp 上传
scp install-lnmp.sh root@你的服务器IP:~/

# 或使用 WinSCP 等工具上传
```

### 2. 运行安装

```bash
# SSH 登录服务器
ssh root@你的服务器IP

# 设置执行权限
chmod +x install-lnmp.sh

# 运行安装脚本
./install-lnmp.sh
```

### 3. 按照提示选择版本

- Nginx：稳定版或最新版
- 数据库：MySQL 或 MariaDB
- PHP：8.2/8.1/8.0/7.4

### 4. 访问测试页面

安装完成后，浏览器访问：
```
http://你的服务器IP/
http://你的服务器IP/info.php
```

## 文件说明

- `install-lnmp.sh` - 主安装脚本
- `README.md` - 详细使用文档
- `快速部署指南.md` - 快速部署方法

## 系统要求

- 最低配置：1 核 CPU, 512MB 内存，5GB 磁盘
- 推荐配置：2 核 CPU, 1GB 内存，10GB 磁盘

## 许可证

MIT License
