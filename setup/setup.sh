#!/bin/bash
# EyeWitness Setup Script - Virtual Environment Edition
# Production-ready cross-platform installation using Python virtual environments

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color output functions
print_success() { echo -e "\033[32m[+] $1\033[0m"; }
print_error()   { echo -e "\033[31m[-] $1\033[0m"; }
print_warning() { echo -e "\033[33m[!] $1\033[0m"; }
print_info()    { echo -e "\033[36m[*] $1\033[0m"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_ROOT/eyewitness-venv"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

# Cleanup function for failed installations
cleanup_on_failure() {
    print_warning "Installation failed. Cleaning up..."
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        print_info "Removed incomplete virtual environment"
    fi
}

# Set trap for cleanup on failure
trap cleanup_on_failure ERR

# Header
echo
print_info "╔══════════════════════════════════════════════════════╗"
print_info "║        EyeWitness Setup (Virtual Environment)        ║"
print_info "║                                                      ║"
print_info "║  Production-ready installation using Python virtual  ║"
print_info "║  environments to avoid PEP 668 and system conflicts  ║"
print_info "╚══════════════════════════════════════════════════════╝"
echo

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    print_error "This script requires root privileges for system package installation"
    print_info "Please run: sudo $0"
    exit 1
fi

print_success "Running with root privileges"

# Detect system
print_info "Detecting system information..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-$(uname -r)}"
else
    print_error "Cannot detect OS. /etc/os-release not found"
    exit 1
fi

ARCH=$(uname -m)
print_info "Detected OS: $OS_ID $OS_VERSION"
print_info "Detected Architecture: $ARCH"

# Warn about SELinux on RHEL-family systems (enforcing mode can block Chrome/Xvfb)
check_selinux() {
    if command -v getenforce &>/dev/null; then
        local selinux_status
        selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
        if [ "$selinux_status" = "Enforcing" ]; then
            print_warning "SELinux is in Enforcing mode."
            print_warning "Headless Chrome and Xvfb may be blocked by SELinux policy."
            print_warning "If EyeWitness fails to start Chrome, consider one of:"
            print_warning "  sudo setsebool -P httpd_can_network_connect 1"
            print_warning "  sudo setenforce 0  (sets Permissive mode - less secure)"
        else
            print_info "SELinux status: $selinux_status"
        fi
    fi
}

# Check Python installation
print_info "Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 not found. Please install Python 3.7 or higher"
    case $OS_ID in
        ubuntu|debian|kali)
            print_info "Install with: apt update && apt install python3 python3-pip"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            print_info "Install with: dnf install python3 python3-pip"
            ;;
        arch|manjaro)
            print_info "Install with: pacman -S python python-pip"
            ;;
    esac
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
print_success "Python $PYTHON_VERSION found"

# Verify Python version compatibility
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 7 ]); then
    print_error "Python 3.7+ required. Current version: $PYTHON_VERSION"
    exit 1
fi

# Ensure the venv module is available.
# On Debian/Ubuntu it may be a separate split package (python3-venv).
# On RHEL/CentOS venv is built into python3 - no separate package needed.
if ! python3 -m venv --help &>/dev/null; then
    print_error "Python venv module not available."
    case $OS_ID in
        ubuntu|debian|kali|linuxmint)
            print_info "Install with: apt install python3-venv"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            print_info "venv is bundled with python3 on RHEL. Try: dnf install python3"
            ;;
    esac
    exit 1
fi

# =============================================================================
# RHEL / CentOS / Rocky / AlmaLinux helpers
# =============================================================================

# Enable EPEL if not already present.
# EPEL provides Chromium and jq on RHEL-family systems.
enable_epel() {
    if rpm -q epel-release &>/dev/null; then
        print_info "EPEL repository already enabled."
        return 0
    fi

    print_info "Enabling EPEL repository (required for Chromium/jq on RHEL/CentOS)..."

    local major_ver
    major_ver=$(echo "$OS_VERSION" | cut -d. -f1)

    case $OS_ID in
        rhel)
            dnf install -y \
                "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${major_ver}.noarch.rpm" || {
                print_error "Failed to install EPEL for RHEL ${major_ver}."
                print_info "Ensure the host has internet access or a subscription that includes EPEL."
                exit 1
            }
            # Enable CRB / PowerTools - needed for some Chromium build dependencies
            if [ "$major_ver" -ge 8 ]; then
                subscription-manager repos \
                    --enable "codeready-builder-for-rhel-${major_ver}-$(uname -m)-rpms" 2>/dev/null || \
                dnf config-manager --set-enabled crb 2>/dev/null || \
                dnf config-manager --set-enabled powertools 2>/dev/null || \
                print_warning "Could not enable CRB/PowerTools - some dependencies may be missing."
            fi
            ;;
        centos)
            dnf install -y epel-release || {
                print_error "Failed to install epel-release for CentOS."
                exit 1
            }
            if [ "$major_ver" -ge 8 ]; then
                dnf config-manager --set-enabled crb 2>/dev/null || \
                dnf config-manager --set-enabled powertools 2>/dev/null || \
                print_warning "Could not enable CRB/PowerTools."
            fi
            ;;
        rocky|almalinux)
            dnf install -y epel-release || {
                print_error "Failed to install epel-release."
                exit 1
            }
            dnf config-manager --set-enabled crb 2>/dev/null || \
            dnf config-manager --set-enabled powertools 2>/dev/null || \
            print_warning "Could not enable CRB/PowerTools."
            ;;
        fedora)
            print_info "Fedora detected - skipping EPEL (not needed)."
            ;;
    esac

    dnf makecache --quiet || true
    print_success "EPEL enabled."
}

# Install Chromium and ensure chromedriver is in PATH on RHEL-family systems.
# Key differences from Debian:
#   - chromedriver is NOT a separate package; it is bundled inside chromium
#   - the driver binary lives under /usr/lib64/chromium-browser/ and is NOT
#     symlinked into PATH by default
#   - jq and cmake require EPEL/CRB
install_chromium_rhel() {
    local PKG_MANAGER="$1"

    print_info "Installing Chromium on RHEL/CentOS/Rocky/AlmaLinux..."

    if $PKG_MANAGER install -y chromium 2>/dev/null; then
        print_success "Chromium installed via package manager."
    else
        print_warning "Chromium not found in configured repos - adding Google Chrome repo as fallback..."
        cat > /etc/yum.repos.d/google-chrome.repo <<'REPO'
[google-chrome]
name=google-chrome
baseurl=http://dl.google.com/linux/chrome/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
REPO
        $PKG_MANAGER install -y google-chrome-stable || {
            print_error "Could not install Chromium or Google Chrome."
            print_info "Please install a Chromium-compatible browser manually and re-run."
            exit 1
        }
        print_success "Google Chrome installed as Chromium alternative."
    fi

    # Locate chromedriver.
    # On RHEL with EPEL's chromium package the driver is at one of these paths
    # and is NOT automatically on PATH.
    local driver_path=""
    for candidate in \
        /usr/lib64/chromium-browser/chromedriver \
        /usr/lib/chromium-browser/chromedriver \
        /usr/libexec/chromium-browser/chromedriver \
        /usr/bin/chromedriver \
        /usr/local/bin/chromedriver; do
        if [ -x "$candidate" ]; then
            driver_path="$candidate"
            break
        fi
    done

    if [ -z "$driver_path" ]; then
        # For Google Chrome fallback, try the chromedriver companion package
        $PKG_MANAGER install -y chromedriver 2>/dev/null || true
        for candidate in /usr/bin/chromedriver /usr/local/bin/chromedriver; do
            if [ -x "$candidate" ]; then
                driver_path="$candidate"
                break
            fi
        done
    fi

    if [ -n "$driver_path" ] && [ "$driver_path" != "/usr/local/bin/chromedriver" ]; then
        print_info "Creating PATH symlink: /usr/local/bin/chromedriver -> $driver_path"
        ln -sf "$driver_path" /usr/local/bin/chromedriver
        print_success "chromedriver now available at /usr/local/bin/chromedriver"
    elif [ -n "$driver_path" ]; then
        print_success "chromedriver found at $driver_path"
    else
        print_warning "chromedriver binary not located after installation."
        print_warning "Selenium may still work via its built-in driver manager (selenium >= 4.6)."
    fi
}

# =============================================================================
# Install system dependencies
# =============================================================================
install_system_deps() {
    print_info "Installing system dependencies..."

    case $OS_ID in
        ubuntu|debian|kali|linuxmint)
            apt-get update
            # python3-venv is a Debian/Ubuntu split package - required on these distros
            apt-get install -y wget curl jq cmake xvfb python3-venv python3-dev

            print_info "Installing Chromium browser and ChromeDriver..."
            print_info "Note: if apt reports errors below, the installer tries multiple methods."
            apt-get install -y chromium-browser chromium-chromedriver || \
            apt-get install -y chromium chromium-driver || {
                print_warning "Package manager chromium installation failed, trying alternative names..."
                apt-get install -y chromium-browser || apt-get install -y chromium || {
                    print_error "Could not install Chromium via package manager"
                    print_info "Please install manually: sudo apt install chromium-browser"
                    exit 1
                }
            }
            ;;

        centos|rhel|rocky|almalinux|fedora)
            check_selinux

            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi

            # Enable EPEL first so that jq, cmake (and Chromium) are resolvable.
            # NOTE: python3-venv is NOT a valid RHEL package name - venv is
            # built into python3 on RHEL and does not need a separate install.
            enable_epel

            $PKG_MANAGER install -y wget curl jq cmake python3-devel xorg-x11-server-Xvfb

            install_chromium_rhel "$PKG_MANAGER"
            ;;

        arch|manjaro)
            pacman -Syu --noconfirm
            pacman -S --noconfirm wget curl jq cmake python xorg-server-xvfb chromium
            print_info "Note: Install chromedriver from AUR if needed: yay -S chromedriver"
            ;;

        alpine)
            apk update
            apk add wget curl jq cmake python3 xvfb py3-pip python3-dev chromium chromium-chromedriver
            ;;

        *)
            print_error "Unsupported operating system: $OS_ID"
            print_info "Supported: Ubuntu, Debian, Kali, CentOS, RHEL, Rocky, AlmaLinux, Fedora, Arch, Alpine"
            exit 1
            ;;
    esac

    print_success "System dependencies installed"
}

# =============================================================================
# Verify system dependencies
# =============================================================================
verify_system_deps() {
    print_info "Verifying system dependencies..."
    local missing=0

    # Check for browser
    local browser_found=false
    for browser in chromium-browser chromium google-chrome google-chrome-stable; do
        if command -v "$browser" &> /dev/null; then
            print_success "Browser found: $browser"
            browser_found=true
            break
        fi
    done
    if [ "$browser_found" = false ]; then
        print_error "No Chromium/Chrome browser found"
        missing=$((missing + 1))
    fi

    # Check for ChromeDriver - also probe RHEL non-PATH locations
    local driver_found=false
    for driver in chromedriver chromium-chromedriver; do
        if command -v "$driver" &> /dev/null; then
            print_success "ChromeDriver found: $driver"
            driver_found=true
            break
        fi
    done
    if [ "$driver_found" = false ]; then
        # RHEL-specific: driver may exist but not be in PATH
        for candidate in \
            /usr/lib64/chromium-browser/chromedriver \
            /usr/lib/chromium-browser/chromedriver \
            /usr/libexec/chromium-browser/chromedriver; do
            if [ -x "$candidate" ]; then
                print_success "ChromeDriver found (not in PATH): $candidate"
                print_info "Creating symlink at /usr/local/bin/chromedriver..."
                ln -sf "$candidate" /usr/local/bin/chromedriver
                driver_found=true
                break
            fi
        done
    fi
    if [ "$driver_found" = false ]; then
        print_warning "ChromeDriver not found in PATH or common locations."
        print_warning "Selenium >= 4.6 includes a built-in driver manager that may handle this."
        # Not a hard failure - selenium-manager can download drivers automatically
    fi

    # Check for Xvfb (virtual display)
    if ! command -v Xvfb &> /dev/null; then
        print_error "Xvfb not found (required for headless operation)"
        missing=$((missing + 1))
    else
        print_success "Xvfb found (virtual display support)"
    fi

    if [ $missing -gt 0 ]; then
        print_error "$missing critical system dependencies missing"
        return 1
    fi

    print_success "All system dependencies verified"
}

# =============================================================================
# Create virtual environment
# =============================================================================
create_virtual_env() {
    print_info "Creating Python virtual environment..."

    if [ -d "$VENV_DIR" ]; then
        print_warning "Existing virtual environment found. Removing..."
        rm -rf "$VENV_DIR"
    fi

    python3 -m venv "$VENV_DIR"
    print_success "Virtual environment created at: $VENV_DIR"

    source "$VENV_DIR/bin/activate"
    print_success "Virtual environment activated"

    pip install --upgrade pip
    print_success "pip upgraded in virtual environment"
}

# =============================================================================
# Install Python dependencies
# =============================================================================
install_python_deps() {
    print_info "Installing Python dependencies in virtual environment..."

    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        print_error "Requirements file not found: $REQUIREMENTS_FILE"
        exit 1
    fi

    pip install -r "$REQUIREMENTS_FILE"
    print_success "Python dependencies installed"

    print_info "Verifying Python package installations..."
    python -c "import selenium; print('\u2713 selenium')"    || { print_error "selenium import failed"; exit 1; }
    python -c "import netaddr; print('\u2713 netaddr')"     || { print_error "netaddr import failed";  exit 1; }
    python -c "import psutil; print('\u2713 psutil')"       || { print_error "psutil import failed";   exit 1; }

    if [ "$OS_ID" != "windows" ]; then
        python -c "import pyvirtualdisplay; print('\u2713 pyvirtualdisplay')" || {
            print_error "pyvirtualdisplay import failed"
            exit 1
        }
    fi

    print_success "All Python packages verified"
}

# =============================================================================
# Test installation
# =============================================================================
test_installation() {
    print_info "Testing EyeWitness installation..."

    cd "$PROJECT_ROOT"
    source "$VENV_DIR/bin/activate"

    python Python/EyeWitness.py --help &> /dev/null || {
        print_error "EyeWitness help command failed"
        return 1
    }

    print_success "EyeWitness installation test passed"
}

# =============================================================================
# Main
# =============================================================================
main() {
    print_info "Starting EyeWitness installation..."

    install_system_deps

    if ! verify_system_deps; then
        print_error "System dependency verification failed"
        exit 1
    fi

    create_virtual_env
    install_python_deps

    if ! test_installation; then
        print_error "Installation test failed"
        exit 1
    fi

    echo
    print_success "\u2713 EyeWitness installation completed successfully!"
    echo
    print_info "USAGE:"
    print_info "1. Activate virtual environment: source eyewitness-venv/bin/activate"
    print_info "2. Run EyeWitness: python Python/EyeWitness.py [options]"
    print_info "3. Deactivate when done: deactivate"
    echo
    print_info "TEST INSTALLATION:"
    print_info "source eyewitness-venv/bin/activate"
    print_info "python Python/EyeWitness.py --single https://example.com"
    echo
    print_info "Virtual environment located at: $VENV_DIR"
    print_info "Visit https://www.redsiege.com for more Red Siege tools"
    echo
}

# Disable trap for successful completion
trap - ERR

# Execute main function
main "$@"
