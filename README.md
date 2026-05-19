# LNMP 环境一键安装脚本使用指南

## 📋 功能特性

- ✅ **多系统支持**：Ubuntu 20.04/22.04/24.04, CentOS 7/8/9, Debian 10/11/12
- ✅ **版本可选**：支持选择 Nginx、MySQL/MariaDB、PHP 版本
- ✅ **自动配置**：自动安装依赖、配置服务参数、设置开机自启
- ✅ **错误处理**：完善的错误检测和回滚机制
- ✅ **安装验证**：自动测试所有服务是否正常运行
- ✅ **测试页面**：创建美观的测试页面验证环境

## 🚀 快速开始

### 1. 上传脚本到服务器

```bash
# 方法 1：使用 scp 上传（在本地 PowerShell 中执行）
scp install-lnmp.sh user@你的服务器IP:~/

# 方法 2：直接在服务器上创建
ssh user@你的服务器IP
```

### 2. 赋予执行权限

```bash
chmod +x install-lnmp.sh
```

### 3. 运行安装脚本

```bash
sudo ./install-lnmp.sh
```

## 📝 安装过程

运行脚本后，会提示你选择软件版本：

### 步骤 1：选择 Nginx 版本
```
=== 选择 Nginx 版本 ===
1) Nginx 稳定版 (推荐)
2) Nginx 最新版
请选择 [1-2, 默认:1]:
```
**建议**：选择 1（稳定版）

### 步骤 2：选择数据库类型
```
=== 选择数据库类型 ===
1) MySQL
2) MariaDB
请选择 [1-2, 默认:1]:
```
**说明**：
- MySQL：Oracle 官方版本，功能最全
- MariaDB：MySQL 分支，完全兼容，性能优秀

### 步骤 3：选择数据库版本
```
=== 选择数据库版本 ===
1) MySQL 8.0 (推荐)
2) MySQL 5.7
请选择 [1-2, 默认:1]:
```
**建议**：选择 1（MySQL 8.0 或 MariaDB 10.6）

### 步骤 4：选择 PHP 版本
```
=== 选择 PHP 版本 ===
1) PHP 8.2 (推荐)
2) PHP 8.1
3) PHP 8.0
4) PHP 7.4
请选择 [1-4, 默认:1]:
```
**建议**：选择 1（PHP 8.2），除非项目有特殊要求

### 步骤 5：确认安装
```
是否继续安装？[y/N]:
```
输入 `y` 开始安装

## ⏱️ 安装时间

根据服务器性能和网络状况，安装通常需要 **5-20 分钟**。

## ✅ 安装完成后的验证

### 1. 访问测试页面

浏览器打开：`http://你的服务器IP/`

应该看到绿色的成功提示页面，显示：
- ✓ Nginx 运行正常
- ✓ MySQL/MariaDB 运行正常
- ✓ PHP 运行正常
- 数据库连接测试结果
- PHP 扩展检查列表

### 2. 查看 PHP 详细信息

浏览器打开：`http://你的服务器IP/info.php`

### 3. 命令行验证

```bash
# 查看 Nginx 状态
systemctl status nginx

# 查看数据库状态
systemctl status mysql    # 或 systemctl status mariadb

# 查看 PHP-FPM 状态
systemctl status php8.2-fpm  # 版本号根据选择而定

# 测试 PHP
php -v

# 测试数据库连接
mysql -u root -p -e "SELECT VERSION();"
```

##  常用管理命令

### Nginx 管理
```bash
systemctl start nginx      # 启动
systemctl stop nginx       # 停止
systemctl restart nginx    # 重启
systemctl reload nginx     # 重载配置
systemctl status nginx     # 查看状态
nginx -t                   # 测试配置
```

### MySQL/MariaDB 管理
```bash
systemctl start mysql      # 启动
systemctl stop mysql       # 停止
systemctl restart mysql    # 重启
systemctl status mysql     # 查看状态

# 登录 MySQL
mysql -u root -p

# 安全初始化（如果安装时跳过）
mysql_secure_installation
```

### PHP-FPM 管理
```bash
# Ubuntu/Debian
systemctl start php8.2-fpm
systemctl stop php8.2-fpm
systemctl restart php8.2-fpm
systemctl status php8.2-fpm

# CentOS/RHEL
systemctl start php-fpm
systemctl stop php-fpm
systemctl restart php-fpm
systemctl status php-fpm
```

## 🔒 安全建议

### 1. 立即设置数据库密码

```bash
mysql_secure_installation
```

按照提示操作：
- 设置 root 密码
- 删除匿名用户
- 禁止 root 远程登录
- 删除测试数据库
- 刷新权限表

### 2. 删除测试页面

```bash
# 删除 PHP 信息页面（包含敏感信息）
rm /var/www/html/info.php

# 或者限制访问（在 Nginx 配置中添加）
location ~ /info\.php$ {
    deny all;
}
```

### 3. 配置防火墙

脚本已自动配置基本防火墙规则。如需手动配置：

**Ubuntu (UFW)**:
```bash
ufw allow 'Nginx Full'
ufw allow 3306/tcp  # 仅允许可信 IP 访问数据库
ufw enable
```

**CentOS (firewalld)**:
```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload
```

### 4. 安装 SSL 证书（推荐）

使用 Let's Encrypt 免费证书：

```bash
# 安装 Certbot
apt-get install certbot python3-certbot-nginx  # Ubuntu/Debian
# 或
yum install certbot python3-certbot-nginx      # CentOS

# 获取证书
certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

## 📂 重要文件位置

### 配置文件
```
/etc/nginx/nginx.conf              # Nginx 主配置
/etc/nginx/sites-available/default # 默认虚拟主机配置
/etc/mysql/my.cnf                  # MySQL 配置
/etc/php/8.2/fpm/php.ini           # PHP 配置（版本号根据安装而定）
```

### 网站目录
```
/var/www/html/                     # 网站根目录
```

### 日志文件
```
/var/log/nginx/access.log          # Nginx 访问日志
/var/log/nginx/error.log           # Nginx 错误日志
/var/log/mysql/error.log           # MySQL 错误日志
/var/log/php8.2-fpm.log            # PHP-FPM 日志
```

##  故障排查

### 问题 1：Nginx 无法启动

```bash
# 检查配置
nginx -t

# 查看错误日志
tail -f /var/log/nginx/error.log

# 检查端口占用
netstat -tlnp | grep :80
```

### 问题 2：PHP 无法解析

检查 Nginx 配置中的 PHP 处理部分：
```nginx
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
}
```

确保 PHP-FPM socket 文件存在：
```bash
ls -la /run/php/php8.2-fpm.sock
```

### 问题 3：数据库连接失败

```bash
# 检查数据库服务
systemctl status mysql

# 测试本地连接
mysql -u root -p

# 检查监听端口
netstat -tlnp | grep :3306
```

### 问题 4：502 Bad Gateway

通常是 PHP-FPM 未启动：
```bash
# 重启 PHP-FPM
systemctl restart php8.2-fpm

# 检查 PHP-FPM 状态
systemctl status php8.2-fpm

# 查看 PHP-FPM 日志
tail -f /var/log/php8.2-fpm.log
```

## 🔄 回滚操作

如果安装过程中出现问题，脚本会自动提示是否回滚。

手动回滚：
```bash
# 停止所有服务
systemctl stop nginx
systemctl stop mysql
systemctl stop php8.2-fpm

# 恢复配置（如果创建了备份）
cp -r /tmp/lnmp_backup_*/nginx /etc/
cp -r /tmp/lnmp_backup_*/mysql /etc/
cp -r /tmp/lnmp_backup_*/php /etc/
```

## 📊 系统要求

### 最低配置
- CPU: 1 核
- 内存：512MB
- 磁盘：5GB 可用空间

### 推荐配置
- CPU: 2 核
- 内存：1GB
- 磁盘：10GB 可用空间

### 支持的操作系统
- Ubuntu: 20.04, 22.04, 24.04
- CentOS: 7, 8, 9
- Debian: 10, 11, 12
- RHEL: 7, 8, 9

## 📞 技术支持

如遇到问题：
1. 查看安装日志：`/tmp/lnmp_install_YYYYMMDD_HHMMSS.log`
2. 检查各服务日志文件
3. 确保服务器网络连接正常
4. 确认系统已更新到最新补丁

##  更新历史

### v1.0
- 初始版本发布
- 支持 Ubuntu/CentOS/Debian
- 自动版本选择
- 完善的错误处理
- 自动回滚机制
- 美观的测试页面

---

**提示**：建议在生产环境使用前，先在测试环境完整测试一遍安装流程。
