#!/bin/bash

#===============================================================================
# LNMP Environment One-Click Installation Script
# Supports: Ubuntu 20.04/22.04/24.04, CentOS 7/8/9, Debian 10/11/12
# Features: Automatic installation of Nginx + MySQL/MariaDB + PHP
#===============================================================================

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
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

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script execution failed, exit code: $exit_code, error line: $line_number"
    log_error "Please check the error messages above"
    
    # Rollback option
    echo ""
    echo -ne "${YELLOW}Rollback installed components? (y/n): ${NC}"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rollback
    fi
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Global variables
INSTALL_LOG="/tmp/lnmp_install_$(date +%Y%m%d_%H%M%S).log"
NGINX_VERSION=""
MYSQL_VERSION=""
PHP_VERSION=""
DB_TYPE="mariadb"  # Default to mariadb to avoid GPG key issues
WEB_ROOT="/var/www/html"
CONFIG_BACKUP_DIR="/tmp/lnmp_backup_$(date +%Y%m%d_%H%M%S)"

# Detect operating system
detect_os() {
    log_info "Detecting operating system..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        OS_LIKE=$ID_LIKE
        
        log_info "Operating system: $OS $VERSION"
        
        # Check supported OS
        case $OS in
            ubuntu)
                if [[ ! "$VERSION" =~ ^(20\.04|22\.04|24\.04)$ ]]; then
                    log_error "Unsupported Ubuntu version: $VERSION"
                    log_info "Supported versions: 20.04, 22.04, 24.04"
                    exit 1
                fi
                ;;
            centos|rhel)
                if [[ ! "$VERSION" =~ ^(7|8|9)$ ]]; then
                    log_error "Unsupported CentOS/RHEL version: $VERSION"
                    log_info "Supported versions: 7, 8, 9"
                    exit 1
                fi
                ;;
            debian)
                if [[ ! "$VERSION" =~ ^(10|11|12)$ ]]; then
                    log_error "Unsupported Debian version: $VERSION"
                    log_info "Supported versions: 10, 11, 12"
                    exit 1
                fi
                ;;
            *)
                log_warning "Unsupported OS: $OS $VERSION, will try generic installation"
                ;;
        esac
    else
        log_error "Cannot detect OS version"
        exit 1
    fi
}

# Check root privileges
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with root privileges"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

# Create backup directory
create_backup() {
    log_info "Creating backup directory: $CONFIG_BACKUP_DIR"
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # Backup existing configurations
    if [ -d "/etc/nginx" ]; then
        cp -r /etc/nginx "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "Backed up Nginx configuration"
    fi
    
    if [ -d "/etc/mysql" ]; then
        cp -r /etc/mysql "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "Backed up MySQL configuration"
    fi
    
    if [ -d "/etc/php" ]; then
        cp -r /etc/php "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
        log_info "Backed up PHP configuration"
    fi
}

# Rollback function
rollback() {
    log_info "Starting rollback..."
    
    if [ -d "$CONFIG_BACKUP_DIR" ]; then
        # Restore configurations
        if [ -d "$CONFIG_BACKUP_DIR/nginx" ]; then
            rm -rf /etc/nginx
            cp -r "$CONFIG_BACKUP_DIR/nginx" /etc/nginx
            log_info "Restored Nginx configuration"
        fi
        
        if [ -d "$CONFIG_BACKUP_DIR/mysql" ]; then
            rm -rf /etc/mysql
            cp -r "$CONFIG_BACKUP_DIR/mysql" /etc/mysql
            log_info "Restored MySQL configuration"
        fi
        
        if [ -d "$CONFIG_BACKUP_DIR/php" ]; then
            rm -rf /etc/php
            cp -r "$CONFIG_BACKUP_DIR/php" /etc/php
            log_info "Restored PHP configuration"
        fi
    fi
    
    # Stop and uninstall services
    systemctl stop nginx 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    systemctl stop mariadb 2>/dev/null || true
    systemctl stop php*-fpm 2>/dev/null || true
    
    log_info "Rollback completed"
}

# Select software versions
select_versions() {
    log_info "Please select software versions"
    echo ""
    
    # Select Nginx version
    echo "=== Select Nginx Version ==="
    echo "1) Nginx Stable (recommended)"
    echo "2) Nginx Latest"
    read -p "Select [1-2, default:1]: " nginx_choice
    case $nginx_choice in
        2) NGINX_VERSION="latest" ;;
        *) NGINX_VERSION="stable" ;;
    esac
    
    # Select database type
    echo ""
    echo "=== Select Database Type ==="
    echo "1) MariaDB (recommended - no GPG key issues)"
    echo "2) MySQL"
    read -p "Select [1-2, default:1]: " db_choice
    case $db_choice in
        2) DB_TYPE="mysql" ;;
        *) DB_TYPE="mariadb" ;;
    esac
    
    # Select database version
    echo ""
    echo "=== Select Database Version ==="
    if [ "$DB_TYPE" = "mysql" ]; then
        echo "1) MySQL 8.0 (recommended)"
        echo "2) MySQL 5.7"
        read -p "Select [1-2, default:1]: " mysql_choice
        case $mysql_choice in
            2) MYSQL_VERSION="5.7" ;;
            *) MYSQL_VERSION="8.0" ;;
        esac
    else
        echo "1) MariaDB 10.6 (recommended)"
        echo "2) MariaDB 10.11"
        read -p "Select [1-2, default:1]: " mariadb_choice
        case $mariadb_choice in
            2) MYSQL_VERSION="10.11" ;;
            *) MYSQL_VERSION="10.6" ;;
        esac
    fi
    
    # Select PHP version
    echo ""
    echo "=== Select PHP Version ==="
    echo "1) PHP 8.2 (recommended)"
    echo "2) PHP 8.1"
    echo "3) PHP 8.0"
    echo "4) PHP 7.4"
    read -p "Select [1-4, default:1]: " php_choice
    case $php_choice in
        2) PHP_VERSION="8.1" ;;
        3) PHP_VERSION="8.0" ;;
        4) PHP_VERSION="7.4" ;;
        *) PHP_VERSION="8.2" ;;
    esac
    
    echo ""
    log_info "Selected configuration:"
    log_info "  Nginx: $NGINX_VERSION"
    log_info "  Database: $DB_TYPE $MYSQL_VERSION"
    log_info "  PHP: $PHP_VERSION"
    echo ""
    
    read -p "Continue with installation? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# Update package manager
update_package_manager() {
    log_info "Updating package lists..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            ;;
        centos|rhel)
            yum update -y
            ;;
        *)
            log_warning "Unknown OS, trying generic update"
            apt-get update -y 2>/dev/null || yum update -y 2>/dev/null || true
            ;;
    esac
}

# Install Nginx
install_nginx() {
    log_info "Installing Nginx..."
    
    case $OS in
        ubuntu|debian)
            # Add Nginx official repository
            if [ "$NGINX_VERSION" = "latest" ]; then
                apt-get install -y gnupg2 ca-certificates lsb-release
                curl -fsSL https://nginx.org/keys/nginx_signing.key | apt-key add -
                echo "deb http://nginx.org/packages/mainline/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
                apt-get update
            fi
            
            apt-get install -y nginx
            ;;
            
        centos|rhel)
            # Add EPEL repository
            yum install -y epel-release
            
            if [ "$NGINX_VERSION" = "latest" ]; then
                # Add Nginx official repository
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
    
    # Start Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx installed successfully"
}

# Install MySQL/MariaDB
install_mysql() {
    log_info "Installing $DB_TYPE $MYSQL_VERSION..."
    
    case $OS in
        ubuntu|debian)
            if [ "$DB_TYPE" = "mysql" ]; then
                # Remove old MySQL repository and GPG keys
                rm -f /etc/apt/sources.list.d/mysql.list
                rm -f /etc/apt/trusted.gpg.d/mysql.gpg
                apt-key del B7B3B788A8D3785C 2>/dev/null || true
                apt-key del 3A79F24DD46DD3B1 2>/dev/null || true
                
                # Download and install MySQL APT repository
                wget -c https://dev.mysql.com/get/mysql-apt-config_0.8.32-1_all.deb
                
                # Auto-select version
                export DEBIAN_FRONTEND=noninteractive
                echo "mysql-apt-config mysql-apt-config/select-server select mysql-$MYSQL_VERSION" | debconf-set-selections
                dpkg -i mysql-apt-config_0.8.32-1_all.deb
                
                # Import MySQL GPG key
                apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C 2>/dev/null || \
                apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3A79F24DD46DD3B1 2>/dev/null || \
                curl -sSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 | apt-key add - 2>/dev/null || true
                
                # Update with error handling
                apt-get update || true
                
                # Install MySQL
                apt-get install -y mysql-server
            else
                # Install MariaDB - no repository needed, use official Ubuntu/Debian repo
                apt-get update
                apt-get install -y mariadb-server mariadb-client
            fi
            ;;
            
        centos|rhel)
            if [ "$DB_TYPE" = "mysql" ]; then
                # Install MySQL YUM repository
                yum install -y https://dev.mysql.com/get/mysql80-community-release-el${VERSION}-1.noarch.rpm
                
                # Import MySQL GPG key
                rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
                
                # Disable other versions, enable specified version
                if [ "$MYSQL_VERSION" = "5.7" ]; then
                    yum-config-manager --disable mysql80-community
                    yum-config-manager --enable mysql-5.7-community
                fi
                
                yum install -y mysql-community-server
            else
                # Install MariaDB - use official CentOS/RedHat repo
                yum install -y mariadb-server mariadb
            fi
            ;;
    esac
    
    # Start database
    systemctl start ${DB_TYPE}
    systemctl enable ${DB_TYPE}
    
    # Security initialization
    log_info "Initializing database security settings..."
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
    
    log_success "$DB_TYPE installed successfully"
}

# Install PHP
install_php() {
    log_info "Installing PHP $PHP_VERSION..."
    
    case $OS in
        ubuntu|debian)
            # Add Ondrej PHP repository
            apt-get install -y software-properties-common lsb-release apt-transport-https
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
            apt-get update
            
            # Install PHP and common extensions
            apt-get install -y php${PHP_VERSION} php${PHP_VERSION}-fpm
            apt-get install -y php${PHP_VERSION}-mysql php${PHP_VERSION}-curl php${PHP_VERSION}-gd \
                              php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-zip \
                              php${PHP_VERSION}-bcmath php${PHP_VERSION}-soap php${PHP_VERSION}-redis \
                              php${PHP_VERSION}-memcached php${PHP_VERSION}-imagick
            
            # Set default PHP version
            update-alternatives --set php /usr/bin/php${PHP_VERSION} 2>/dev/null || true
            ;;
            
        centos|rhel)
            # Add Remi PHP repository
            yum install -y yum-utils
            yum install -y https://rpms.remirepo.net/enterprise/remi-release-${VERSION}.rpm
            
            # Enable PHP module
            if command -v dnf &> /dev/null; then
                dnf module enable -y php:remi-${PHP_VERSION//./}
            else
                yum-config-manager --enable remi-php${PHP_VERSION//./}
            fi
            
            # Install PHP and common extensions
            yum install -y php php-fpm php-mysqlnd php-pdo php-gd php-mbstring \
                          php-xml php-zip php-bcmath php-soap php-process
            ;;
    esac
    
    # Start PHP-FPM
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        systemctl start php-fpm
        systemctl enable php-fpm
    else
        systemctl start php${PHP_VERSION}-fpm
        systemctl enable php${PHP_VERSION}-fpm
    fi
    
    log_success "PHP installed successfully"
}

# Configure Nginx to support PHP
configure_nginx_php() {
    log_info "Configuring Nginx to support PHP..."
    
    # Create web root directory
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || chown -R nginx:nginx "$WEB_ROOT" 2>/dev/null || true
    chmod -R 755 "$WEB_ROOT"
    
    # Backup original configuration
    if [ -f "/etc/nginx/sites-available/default" ]; then
        cp "/etc/nginx/sites-available/default" "$CONFIG_BACKUP_DIR/nginx_default.conf"
    elif [ -f "/etc/nginx/conf.d/default.conf" ]; then
        cp "/etc/nginx/conf.d/default.conf" "$CONFIG_BACKUP_DIR/nginx_default.conf"
    fi
    
    # Create Nginx configuration
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

    # Log configuration
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
}
EOF
    
    # Create PHP configuration snippet
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
    
    # Test Nginx configuration
    nginx -t
    
    # Restart Nginx
    systemctl restart nginx
    
    log_success "Nginx configured successfully"
}

# Create test page
create_test_page() {
    log_info "Creating test page..."
    
    # PHP info page
    cat > "$WEB_ROOT/info.php" << EOF
<?php
phpinfo();
?>
EOF

    # Simple test page
    cat > "$WEB_ROOT/index.php" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LNMP Environment Test</title>
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
        <h1>ðŸŽ‰ LNMP Environment Installed Successfully!</h1>
        
        <div class="status success">
            <strong>ï¿?/strong> Nginx is running
        </div>
        
        <div class="status success">
            <strong>ï¿?/strong> <?php echo $DB_TYPE; ?> is running
        </div>
        
        <div class="status success">
            <strong>ï¿?/strong> PHP <?php echo PHP_VERSION; ?> is running
        </div>
        
        <div class="status info">
            <strong>Server Information:</strong><br>
            Server IP: <?php echo $_SERVER['SERVER_ADDR'] ?? 'N/A'; ?><br>
            PHP Version: <?php echo phpversion(); ?><br>
            Server Time: <?php echo date('Y-m-d H:i:s'); ?>
        </div>
        
        <h2>Database Connection Test</h2>
        <table>
            <tr>
                <th>Test Item</th>
                <th>Result</th>
            </tr>
            <?php
            $db_type = '$DB_TYPE';
            try {
                if ($db_type === 'mysql') {
                    $pdo = new PDO('mysql:host=localhost', 'root');
                    $stmt = $pdo->query('SELECT VERSION()');
                    $version = $stmt->fetchColumn();
                    echo "<tr><td>MySQL Version</td><td>$version</td></tr>";
                } else {
                    $pdo = new PDO('mysql:host=localhost', 'root');
                    $stmt = $pdo->query('SELECT VERSION()');
                    $version = $stmt->fetchColumn();
                    echo "<tr><td>MariaDB Version</td><td>$version</td></tr>";
                }
                echo "<tr><td>Connection Status</td><td style='color:green'>ï¿?Success</td></tr>";
            } catch (PDOException $e) {
                echo "<tr><td>Database Connection</td><td style='color:red'>ï¿?Failed: " . $e->getMessage() . "</td></tr>";
            }
            ?>
        </table>
        
        <h2>PHP Extensions Check</h2>
        <table>
            <tr>
                <th>Extension</th>
                <th>Status</th>
            </tr>
            <?php
            $extensions = ['mysqli', 'pdo_mysql', 'curl', 'gd', 'mbstring', 'xml', 'zip', 'bcmath'];
            foreach ($extensions as $ext) {
                $status = extension_loaded($ext) ? 'ï¿?Loaded' : 'ï¿?Not Loaded';
                $color = extension_loaded($ext) ? 'green' : 'red';
                echo "<tr><td>$ext</td><td style='color:$color'>$status</td></tr>";
            }
            ?>
        </table>
        
        <a href="/info.php" class="button" target="_blank">View PHP Info Details</a>
    </div>
</body>
</html>
EOF

    chown www-data:www-data "$WEB_ROOT"/*.php 2>/dev/null || chown nginx:nginx "$WEB_ROOT"/*.php 2>/dev/null || true
    
    log_success "Test page created successfully"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                ufw allow 'Nginx Full' 2>/dev/null || true
                ufw allow 3306/tcp 2>/dev/null || true
                log_info "UFW firewall rules configured"
            fi
            ;;
        centos|rhel)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --add-service=http 2>/dev/null || true
                firewall-cmd --permanent --add-service=https 2>/dev/null || true
                firewall-cmd --permanent --add-port=3306/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                log_info "firewalld firewall rules configured"
            fi
            ;;
    esac
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check Nginx
    if systemctl is-active --quiet nginx; then
        log_success "ï¿?Nginx service is running"
    else
        log_error "ï¿?Nginx service is not running"
        ((errors++))
    fi
    
    # Check database
    if systemctl is-active --quiet ${DB_TYPE}; then
        log_success "ï¿?$DB_TYPE service is running"
    else
        log_error "ï¿?$DB_TYPE service is not running"
        ((errors++))
    fi
    
    # Check PHP-FPM
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        if systemctl is-active --quiet php-fpm; then
            log_success "ï¿?PHP-FPM service is running"
        else
            log_error "ï¿?PHP-FPM service is not running"
            ((errors++))
        fi
    else
        if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
            log_success "ï¿?PHP${PHP_VERSION}-FPM service is running"
        else
            log_error "ï¿?PHP${PHP_VERSION}-FPM service is not running"
            ((errors++))
        fi
    fi
    
    # Test PHP
    if php -v &> /dev/null; then
        log_success "ï¿?PHP CLI is available"
        php -v | head -n 1
    else
        log_error "ï¿?PHP CLI is not available"
        ((errors++))
    fi
    
    # Test database connection
    if [ "$DB_TYPE" = "mysql" ]; then
        if mysql -e "SELECT VERSION();" &> /dev/null; then
            log_success "ï¿?Database connection is working"
            mysql -e "SELECT VERSION();" | tail -n 1
        else
            log_error "ï¿?Database connection failed"
            ((errors++))
        fi
    else
        if mysql -e "SELECT VERSION();" &> /dev/null; then
            log_success "ï¿?Database connection is working"
            mysql -e "SELECT VERSION();" | tail -n 1
        else
            log_error "ï¿?Database connection failed"
            ((errors++))
        fi
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_success "All services verified successfully!"
        return 0
    else
        log_error "Found $errors issue(s), please check the errors above"
        return 1
    fi
}

# Show installation summary
show_summary() {
    echo ""
    echo "==============================================================================="
    echo -e "${GREEN}                    LNMP Environment Installation Completed!${NC}"
    echo "==============================================================================="
    echo ""
    echo "Installation Information:"
    echo "  - Nginx: $(nginx -v 2>&1 | cut -d'/' -f2 | cut -d' ' -f1)"
    echo "  - $DB_TYPE: $(mysql --version | awk '{print $5}' | cut -d',' -f1)"
    echo "  - PHP: $(php -v | head -n 1 | cut -d' ' -f2)"
    echo ""
    echo "Important Information:"
    echo "  - Web Root: $WEB_ROOT"
    echo "  - Nginx Config: /etc/nginx/sites-available/default"
    if [ "$DB_TYPE" = "mysql" ]; then
        echo "  - MySQL Password: Initially empty, please run mysql_secure_installation"
    fi
    echo ""
    echo "Access URLs:"
    echo "  - http://YOUR_SERVER_IP/"
    echo "  - http://YOUR_SERVER_IP/info.php (PHP Info)"
    echo ""
    echo "Common Commands:"
    echo "  - systemctl status nginx     # Check Nginx status"
    echo "  - systemctl status $DB_TYPE  # Check database status"
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        echo "  - systemctl status php-fpm     # Check PHP-FPM status"
    else
        echo "  - systemctl status php${PHP_VERSION}-fpm # Check PHP-FPM status"
    fi
    echo "  - nginx -t                     # Test Nginx configuration"
    echo ""
    echo "Security Recommendations:"
    echo "  1. Set database root password immediately"
    echo "  2. Delete test page info.php"
    echo "  3. Configure firewall rules"
    echo "  4. Consider installing SSL certificate"
    echo ""
    echo "Log Files:"
    echo "  - Installation Log: $INSTALL_LOG"
    echo "  - Nginx Logs: /var/log/nginx/"
    echo "  - $DB_TYPE Logs: $(if [ "$DB_TYPE" = "mysql" ]; then echo "/var/log/mysql/"; else echo "/var/log/mariadb/"; fi)"
    echo ""
    echo "==============================================================================="
}

# Main function
main() {
    echo ""
    echo "==============================================================================="
    echo -e "${BLUE}           LNMP Environment One-Click Installation Script v1.0${NC}"
    echo "==============================================================================="
    echo ""
    
    # Record start time
    start_time=$(date +%s)
    
    # Execute installation steps
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
    
    # Record end time
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Total installation time: ${duration} seconds"
    
    show_summary
    
    # Save installation log
    cp "$INSTALL_LOG" "$WEB_ROOT/lnmp_install_$(date +%Y%m%d_%H%M%S).log" 2>/dev/null || true
    
    echo ""
    log_info "Installation log saved to: $INSTALL_LOG"
    echo ""
}

# Execute main function
main "$@"
