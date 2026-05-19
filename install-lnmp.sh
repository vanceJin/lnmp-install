#!/bin/bash

#===============================================================================
# LNMP 环境一键安装脚本
# 支持：Ubuntu 20.04/22.04/24.04, CentOS 7/8/9, Debian 10/11/12
# 功能：自动安装配置 Nginx + MySQL/MariaDB + PHP
#===============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 错误处理
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "脚本执行失败，退出码：$exit_code, 错误行号：$line_number"
    log_error "请检查上述错误信息"
    
    # 回滚选项
    echo ""
    read -p "$(echo -e ${YELLOW}是否要回滚已安装的组件？(y/n):${NC} )" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rollback
    fi
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# 全局变量
INSTALL_LOG="/tmp/lnmp_install_$(date +%Y%m%d_%H%M%S).log"
NGINX_VERSION=""
MYSQL_VERSION=""
PHP_VERSION=""
DB_TYPE="mysql"  # mysql 或 mariadb
WEB_ROOT="/var/www/html"
CONFIG_BACKUP_DIR="/tmp/lnmp_backup_$(date +%Y%m%d_%H%M%S)"

# 检测操作系统
detect_os() {
    log_info "检测操作系统..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        OS_LIKE=$ID_LIKE
        
        log_info "操作系统：$OS $VERSION"
        
        # 检查支持的操作系统
        case $OS in
            ubuntu)
                if [[ ! "$VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
                    log_error "不支持的 Ubuntu 版本：$VERSION"
                    log_info "支持的版本：20.04, 22.04, 24.04"
                    exit 1
                fi
                ;;
            centos|rhel)
                if [[ ! "$VERSION" =~ ^(7|8|9)$ ]]; then
                    log_error "不支持的 CentOS/RHEL 版本：$VERSION"
                    log_info "支持的版本：7, 8, 9"
                    exit 1
                fi
                ;;
            debian)
                if [[ ! "$VERSION" =~ ^(10|11|12)$ ]]; then
                    log_error "不支持的 Debian 版本：$VERSION"
                    log_info "支持的版本：10, 11, 12"
                    exit 1
                fi
                ;;
            *)
                log_warning "未明确支持的操作系统：$OS $VERSION，将尝试通用安装方法"
                ;;
        esac
    else
        log_error "无法检测操作系统版本"
        exit 1
    fi
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "使用方法：sudo $0"
        exit 1
    fi
}

# 创建备份目录
create_backup() {
    log_info "创建备份目录：$CONFIG_BACKUP_DIR"
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # 备份现有配置
    if [ -d "/etc/nginx" ]; then
        cp -r /etc/nginx "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "已备份 Nginx 配置"
    fi
    
    if [ -d "/etc/mysql" ]; then
        cp -r /etc/mysql "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "已备份 MySQL 配置"
    fi
    
    if [ -d "/etc/php" ]; then
        cp -r /etc/php "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "已备份 PHP 配置"
    fi
}

# 回滚函数
rollback() {
    log_info "开始回滚..."
    
    if [ -d "$CONFIG_BACKUP_DIR" ]; then
        # 恢复配置
        if [ -d "$CONFIG_BACKUP_DIR/nginx" ]; then
            rm -rf /etc/nginx
            cp -r "$CONFIG_BACKUP_DIR/nginx" /etc/nginx
            log_info "已恢复 Nginx 配置"
        fi
        
        if [ -d "$CONFIG_BACKUP_DIR/mysql" ]; then
            rm -rf /etc/mysql
            cp -r "$CONFIG_BACKUP_DIR/mysql" /etc/mysql
            log_info "已恢复 MySQL 配置"
        fi
        
        if [ -d "$CONFIG_BACKUP_DIR/php" ]; then
            rm -rf /etc/php
            cp -r "$CONFIG_BACKUP_DIR/php" /etc/php
            log_info "已恢复 PHP 配置"
        fi
    fi
    
    # 停止并卸载服务
    systemctl stop nginx 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop php*-fpm 2>/dev/null || true
    
    log_info "回滚完成"
}

# 选择软件版本
select_versions() {
    log_info "请选择软件版本"
    echo ""
    
    # 选择 Nginx 版本
    echo "=== 选择 Nginx 版本 ==="
    echo "1) Nginx 稳定版 (推荐)"
    echo "2) Nginx 最新版"
    read -p "请选择 [1-2, 默认:1]: " nginx_choice
    case $nginx_choice in
        2) NGINX_VERSION="latest" ;;
        *) NGINX_VERSION="stable" ;;
    esac
    
    # 选择数据库类型
    echo ""
    echo "=== 选择数据库类型 ==="
    echo "1) MySQL"
    echo "2) MariaDB"
    read -p "请选择 [1-2, 默认:1]: " db_choice
    case $db_choice in
        2) DB_TYPE="mariadb" ;;
        *) DB_TYPE="mysql" ;;
    esac
    
    # 选择数据库版本
    echo ""
    echo "=== 选择数据库版本 ==="
    if [ "$DB_TYPE" = "mysql" ]; then
        echo "1) MySQL 8.0 (推荐)"
        echo "2) MySQL 5.7"
        read -p "请选择 [1-2, 默认:1]: " mysql_choice
        case $mysql_choice in
            2) MYSQL_VERSION="5.7" ;;
            *) MYSQL_VERSION="8.0" ;;
        esac
    else
        echo "1) MariaDB 10.6 (推荐)"
        echo "2) MariaDB 10.11"
        read -p "请选择 [1-2, 默认:1]: " mariadb_choice
        case $mariadb_choice in
            2) MYSQL_VERSION="10.11" ;;
            *) MYSQL_VERSION="10.6" ;;
        esac
    fi
    
    # 选择 PHP 版本
    echo ""
    echo "=== 选择 PHP 版本 ==="
    echo "1) PHP 8.2 (推荐)"
    echo "2) PHP 8.1"
    echo "3) PHP 8.0"
    echo "4) PHP 7.4"
    read -p "请选择 [1-4, 默认:1]: " php_choice
    case $php_choice in
        2) PHP_VERSION="8.1" ;;
        3) PHP_VERSION="8.0" ;;
        4) PHP_VERSION="7.4" ;;
        *) PHP_VERSION="8.2" ;;
    esac
    
    echo ""
    log_info "选择的配置："
    log_info "  Nginx: $NGINX_VERSION"
    log_info "  数据库：$DB_TYPE $MYSQL_VERSION"
    log_info "  PHP: $PHP_VERSION"
    echo ""
    
    read -p "是否继续安装？[y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
}

# 更新系统包管理器
update_package_manager() {
    log_info "更新软件包列表..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            ;;
        centos|rhel)
            yum update -y
            ;;
        *)
            log_warning "未知操作系统，尝试通用更新方法"
            apt-get update -y 2>/dev/null || yum update -y 2>/dev/null || true
            ;;
    esac
}

# 安装 Nginx
install_nginx() {
    log_info "正在安装 Nginx..."
    
    case $OS in
        ubuntu|debian)
            # 添加 Nginx 官方源
            if [ "$NGINX_VERSION" = "latest" ]; then
                apt-get install -y gnupg2 ca-certificates lsb-release
                curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key add -
                echo "deb http://nginx.org/packages/mainline/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
                apt-get update
            fi
            
            apt-get install -y nginx
            ;;
            
        centos|rhel)
            # 添加 EPEL 源
            yum install -y epel-release
            
            if [ "$NGINX_VERSION" = "latest" ]; then
                # 添加 Nginx 官方源
                cat > /etc/yum.repos.d/nginx.repo << EOF
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
            fi
            
            yum install -y nginx
            ;;
    esac
    
    # 启动 Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx 安装完成"
}

# 安装 MySQL/MariaDB
install_mysql() {
    log_info "正在安装 $DB_TYPE $MYSQL_VERSION..."
    
    case $OS in
        ubuntu|debian)
            if [ "$DB_TYPE" = "mysql" ]; then
                # 下载 MySQL APT 仓库配置
                wget -c https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
                
                # 自动选择版本
                export DEBIAN_FRONTEND=noninteractive
                echo "mysql-apt-config mysql-apt-config/select-server select mysql-$MYSQL_VERSION" | debconf-set-selections
                dpkg -i mysql-apt-config_0.8.29-1_all.deb
                apt-get update
                
                # 安装 MySQL
                apt-get install -y mysql-server
            else
                # 安装 MariaDB
                apt-get install -y mariadb-server mariadb-client
            fi
            ;;
            
        centos|rhel)
            if [ "$DB_TYPE" = "mysql" ]; then
                # 安装 MySQL YUM 仓库
                yum install -y https://dev.mysql.com/get/mysql80-community-release-el${VERSION}-1.noarch.rpm
                
                # 禁用其他版本，启用指定版本
                if [ "$MYSQL_VERSION" = "5.7" ]; then
                    yum-config-manager --disable mysql80-community
                    yum-config-manager --enable mysql-5.7-community
                fi
                
                yum install -y mysql-community-server
            else
                # 安装 MariaDB
                yum install -y mariadb-server mariadb
            fi
            ;;
    esac
    
    # 启动数据库
    systemctl start ${DB_TYPE}
    systemctl enable ${DB_TYPE}
    
    # 安全初始化
    log_info "初始化数据库安全设置..."
    if [ "$DB_TYPE" = "mysql" ]; then
        mysql_secure_installation << EOF
y
n
y
y
y
y
EOF
    else
        mysql_secure_installation << EOF
y
y
y
y
y
EOF
    fi
    
    log_success "$DB_TYPE 安装完成"
}

# 安装 PHP
install_php() {
    log_info "正在安装 PHP $PHP_VERSION..."
    
    case $OS in
        ubuntu|debian)
            # 添加 Ondrej PHP 源
            apt-get install -y software-properties-common lsb-release apt-transport-https
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
            apt-get update
            
            # 安装 PHP 及常用扩展
            apt-get install -y php${PHP_VERSION} php${PHP_VERSION}-fpm
            apt-get install -y php${PHP_VERSION}-mysql php${PHP_VERSION}-curl php${PHP_VERSION}-gd \
                              php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
                              php${PHP_VERSION}-bcmath php${PHP_VERSION}-soap php${PHP_VERSION}-redis \
                              php${PHP_VERSION}-memcached php${PHP_VERSION}-imagick
            
            # 设置默认 PHP 版本
            update-alternatives --set php /usr/bin/php${PHP_VERSION} 2>/dev/null || true
            ;;
            
        centos|rhel)
            # 添加 Remi PHP 源
            yum install -y yum-utils
            yum install -y https://rpms.remirepo.net/enterprise/remi-release-${VERSION}.rpm
            
            # 启用 PHP 模块
            if command -v dnf &> /dev/null; then
                dnf module enable -y php:remi-${PHP_VERSION//./}
            else
                yum-config-manager --enable remi-php${PHP_VERSION//./}
            fi
            
            # 安装 PHP 及常用扩展
            yum install -y php php-fpm php-mysqlnd php-pdo php-gd php-mbstring \
                          php-xml php-zip php-bcmath php-soap php-process
            ;;
    esac
    
    # 启动 PHP-FPM
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        systemctl start php-fpm
        systemctl enable php-fpm
    else
        systemctl start php${PHP_VERSION}-fpm
        systemctl enable php${PHP_VERSION}-fpm
    fi
    
    log_success "PHP 安装完成"
}

# 配置 Nginx 支持 PHP
configure_nginx_php() {
    log_info "配置 Nginx 支持 PHP..."
    
    # 创建网站根目录
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || chown -R nginx:nginx "$WEB_ROOT" 2>/dev/null || true
    chmod -R 755 "$WEB_ROOT"
    
    # 备份原配置
    if [ -f "/etc/nginx/sites-available/default" ]; then
        cp "/etc/nginx/sites-available/default" "$CONFIG_BACKUP_DIR/nginx_default.conf"
    elif [ -f "/etc/nginx/conf.d/default.conf" ]; then
        cp "/etc/nginx/conf.d/default.conf" "$CONFIG_BACKUP_DIR/nginx_default.conf"
    fi
    
    # 创建 Nginx 配置
    cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    root $WEB_ROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~ /\.git {
        deny all;
    }

    # 日志配置
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF
    
    # 创建 PHP 配置片段
    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/fastcgi-php.conf << 'EOF'
fastcgi_split_path_info ^(.+\.php)(/.+)$;
fastcgi_pass unix:/run/php/php-fpm.sock;
fastcgi_index index.php;
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
fastcgi_param PATH_INFO $fastcgi_path_info;
fastcgi_param PATH_TRANSLATED $document_root$fastcgi_path_info;
EOF
    
    # 测试 Nginx 配置
    nginx -t
    
    # 重启 Nginx
    systemctl restart nginx
    
    log_success "Nginx 配置完成"
}

# 创建测试页面
create_test_page() {
    log_info "创建测试页面..."
    
    # PHP 测试页面
    cat > "$WEB_ROOT/info.php" << EOF
<?php
phpinfo();
?>
EOF

    # 简单测试页面
    cat > "$WEB_ROOT/index.php" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LNMP 环境测试</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #4CAF50;
            padding-bottom: 10px;
        }
        .status {
            padding: 10px;
            margin: 10px 0;
            border-radius: 4px;
        }
        .success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        .info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background: #4CAF50;
            color: white;
        }
        .button {
            display: inline-block;
            padding: 10px 20px;
            background: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 4px;
            margin-top: 20px;
        }
        .button:hover {
            background: #45a049;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 LNMP 环境安装成功！</h1>
        
        <div class="status success">
            <strong>✓</strong> Nginx 运行正常
        </div>
        
        <div class="status success">
            <strong>✓</strong> <?php echo $DB_TYPE; ?> 运行正常
        </div>
        
        <div class="status success">
            <strong>✓</strong> PHP <?php echo PHP_VERSION; ?> 运行正常
        </div>
        
        <div class="status info">
            <strong>服务器信息：</strong><br>
            服务器 IP: <?php echo \$_SERVER['SERVER_ADDR'] ?? 'N/A'; ?><br>
            PHP 版本：<?php echo phpversion(); ?><br>
            服务器时间：<?php echo date('Y-m-d H:i:s'); ?>
        </div>
        
        <h2>数据库连接测试</h2>
        <table>
            <tr>
                <th>测试项</th>
                <th>结果</th>
            </tr>
            <?php
            \$db_type = '$DB_TYPE';
            try {
                if (\$db_type === 'mysql') {
                    \$pdo = new PDO('mysql:host=localhost', 'root');
                    \$stmt = \$pdo->query('SELECT VERSION()');
                    \$version = \$stmt->fetchColumn();
                    echo "<tr><td>MySQL 版本</td><td>\$version</td></tr>";
                } else {
                    \$pdo = new PDO('mysql:host=localhost', 'root');
                    \$stmt = \$pdo->query('SELECT VERSION()');
                    \$version = \$stmt->fetchColumn();
                    echo "<tr><td>MariaDB 版本</td><td>\$version</td></tr>";
                }
                echo "<tr><td>连接状态</td><td style='color:green'>✓ 成功</td></tr>";
            } catch (PDOException \$e) {
                echo "<tr><td>数据库连接</td><td style='color:red'>✗ 失败：" . \$e->getMessage() . "</td></tr>";
            }
            ?>
        </table>
        
        <h2>PHP 扩展检查</h2>
        <table>
            <tr>
                <th>扩展</th>
                <th>状态</th>
            </tr>
            <?php
            \$extensions = ['mysqli', 'pdo_mysql', 'curl', 'gd', 'mbstring', 'xml', 'zip', 'bcmath'];
            foreach (\$extensions as \$ext) {
                \$status = extension_loaded(\$ext) ? '✓ 已加载' : '✗ 未加载';
                \$color = extension_loaded(\$ext) ? 'green' : 'red';
                echo "<tr><td>\$ext</td><td style='color:\$color'>\$status</td></tr>";
            }
            ?>
        </table>
        
        <a href="/info.php" class="button" target="_blank">查看 PHP 详细信息</a>
    </div>
</body>
</html>
EOF

    chown www-data:www-data "$WEB_ROOT"/*.php 2>/dev/null || chown nginx:nginx "$WEB_ROOT"/*.php 2>/dev/null || true
    
    log_success "测试页面创建完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                ufw allow 'Nginx Full' 2>/dev/null || true
                ufw allow 3306/tcp 2>/dev/null || true
                log_info "已配置 UFW 防火墙规则"
            fi
            ;;
        centos|rhel)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-service=http 2>/dev/null || true
                firewall-cmd --permanent --add-service=https 2>/dev/null || true
                firewall-cmd --permanent --add-port=3306/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                log_info "已配置 firewalld 防火墙规则"
            fi
            ;;
    esac
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    local errors=0
    
    # 检查 Nginx
    if systemctl is-active --quiet nginx; then
        log_success "✓ Nginx 服务运行正常"
    else
        log_error "✗ Nginx 服务未运行"
        ((errors++))
    fi
    
    # 检查数据库
    if systemctl is-active --quiet ${DB_TYPE}; then
        log_success "✓ $DB_TYPE 服务运行正常"
    else
        log_error "✗ $DB_TYPE 服务未运行"
        ((errors++))
    fi
    
    # 检查 PHP-FPM
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        if systemctl is-active --quiet php-fpm; then
            log_success "✓ PHP-FPM 服务运行正常"
        else
            log_error "✗ PHP-FPM 服务未运行"
            ((errors++))
        fi
    else
        if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
            log_success "✓ PHP${PHP_VERSION}-FPM 服务运行正常"
        else
            log_error "✗ PHP${PHP_VERSION}-FPM 服务未运行"
            ((errors++))
        fi
    fi
    
    # 测试 PHP
    if php -v &> /dev/null; then
        log_success "✓ PHP 命令行可用"
        php -v | head -n 1
    else
        log_error "✗ PHP 命令行不可用"
        ((errors++))
    fi
    
    # 测试数据库连接
    if [ "$DB_TYPE" = "mysql" ]; then
        if mysql -e "SELECT VERSION();" &> /dev/null; then
            log_success "✓ 数据库连接正常"
            mysql -e "SELECT VERSION();" | tail -n 1
        else
            log_error "✗ 数据库连接失败"
            ((errors++))
        fi
    else
        if mysql -e "SELECT VERSION();" &> /dev/null; then
            log_success "✓ 数据库连接正常"
            mysql -e "SELECT VERSION();" | tail -n 1
        else
            log_error "✗ 数据库连接失败"
            ((errors++))
        fi
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_success "所有服务验证通过！"
        return 0
    else
        log_error "发现 $errors 个问题，请检查上述错误"
        return 1
    fi
}

# 显示安装摘要
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}                    LNMP 环境安装完成！${NC}"
    echo "==============================================================================="
    echo ""
    echo "安装信息："
    echo "  - Nginx: $(nginx -v 2>&1 | cut -d'/' -f2 | cut -d' ' -f1)"
    echo "  - $DB_TYPE: $(mysql --version | awk '{print $5}' | cut -d',' -f1)"
    echo "  - PHP: $(php -v | head -n 1 | cut -d' ' -f2)"
    echo ""
    echo "重要信息："
    echo "  - 网站根目录：$WEB_ROOT"
    echo "  - Nginx 配置：/etc/nginx/sites-available/default"
    if [ "$DB_TYPE" = "mysql" ]; then
        echo "  - MySQL 密码：初始为空，请运行 mysql_secure_installation 设置"
    fi
    echo ""
    echo "访问地址："
    echo "  - http://你的服务器IP/"
    echo "  - http://你的服务器IP/info.php (PHP 详细信息)"
    echo ""
    echo "常用命令："
    echo "  - systemctl status nginx     # 查看 Nginx 状态"
    echo "  - systemctl status $DB_TYPE  # 查看数据库状态"
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        echo "  - systemctl status php-fpm     # 查看 PHP-FPM 状态"
    else
        echo "  - systemctl status php${PHP_VERSION}-fpm # 查看 PHP-FPM 状态"
    fi
    echo "  - nginx -t                     # 测试 Nginx 配置"
    echo ""
    echo "安全建议："
    echo "  1. 立即设置数据库 root 密码"
    echo "  2. 删除测试页面 info.php"
    echo "  3. 配置防火墙规则"
    echo "  4. 考虑安装 SSL 证书"
    echo ""
    echo "日志文件："
    echo "  - 安装日志：$INSTALL_LOG"
    echo "  - Nginx 日志：/var/log/nginx/"
    echo "  - $DB_TYPE 日志：$(if [ "$DB_TYPE" = "mysql" ]; then echo "/var/log/mysql/"; else echo "/var/log/mariadb/"; fi)"
    echo ""
    echo "==============================================================================="
}

# 主函数
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${BLUE}           LNMP 环境一键安装脚本 v1.0${NC}"
    echo "==============================================================================="
    echo ""
    
    # 记录开始时间
    start_time=$(date +%s)
    
    # 执行安装步骤
    check_root
    detect_os
    create_backup
    select_versions
    update_package_manager
    install_nginx
    install_mysql
    install_php
    configure_nginx_php
    configure_firewall
    create_test_page
    verify_installation
    
    # 记录结束时间
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "安装总耗时：${duration}秒"
    
    show_summary
    
    # 保存安装日志
    cp "$INSTALL_LOG" "$WEB_ROOT/lnmp_install_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true
    
    echo ""
    log_info "安装日志已保存到：$INSTALL_LOG"
    echo ""
}

# 执行主函数
main "$@"
