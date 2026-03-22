#!/bin/bash
echo "=== EyeWitness Dependency Check (Chromium Only) ==="
echo

# Check Chromium
echo -n "Chromium: "
chromium_found=false
for browser in chromium-browser chromium google-chrome google-chrome-stable; do
    if command -v $browser &> /dev/null; then
        echo "\u2713 Installed ($browser $(timeout 2 $browser --version 2>&1 | head -1 | cut -d' ' -f2 2>/dev/null || echo 'version unknown'))"
        chromium_found=true
        break
    fi
done
if [ "$chromium_found" = false ]; then
    echo "\u2717 NOT FOUND"
fi

# Check chromedriver
# On RHEL/CentOS, chromedriver is bundled inside the chromium package and may
# NOT be on PATH. We probe the standard RHEL locations as well.
echo -n "ChromeDriver: "
chromedriver_found=false
for driver in chromedriver chromium-chromedriver; do
    if command -v $driver &> /dev/null; then
        echo "\u2713 Installed ($driver $($driver --version 2>&1 | head -1 | cut -d' ' -f2 2>/dev/null || echo 'version unknown'))"
        chromedriver_found=true
        break
    fi
done
if [ "$chromedriver_found" = false ]; then
    # RHEL-specific: probe non-PATH locations
    for candidate in \
        /usr/lib64/chromium-browser/chromedriver \
        /usr/lib/chromium-browser/chromedriver \
        /usr/libexec/chromium-browser/chromedriver; do
        if [ -x "$candidate" ]; then
            echo "\u2713 Installed (non-PATH: $candidate)"
            echo "  Tip: run 'sudo ln -sf $candidate /usr/local/bin/chromedriver' to add to PATH"
            chromedriver_found=true
            break
        fi
    done
fi
if [ "$chromedriver_found" = false ]; then
    echo "\u2717 NOT FOUND"
fi

# Check Xvfb
echo -n "Xvfb: "
if command -v Xvfb &> /dev/null; then
    echo "\u2713 Installed"
else
    echo "\u2717 NOT FOUND"
fi

# Check Python packages (inside virtualenv if active, system otherwise)
echo
echo "Python packages:"
echo -n " - pyvirtualdisplay: "
python3 -c "import pyvirtualdisplay; print('\u2713 Installed')" 2>/dev/null || echo "\u2717 NOT FOUND"
echo -n " - selenium: "
python3 -c "import selenium; print('\u2713 Installed')" 2>/dev/null || echo "\u2717 NOT FOUND"
echo -n " - argcomplete: "
python3 -c "import argcomplete; print('\u2713 Installed')" 2>/dev/null || echo "\u2717 NOT FOUND"

# Check SELinux status (relevant on RHEL/CentOS)
if command -v getenforce &>/dev/null; then
    selinux_status=$(getenforce 2>/dev/null || echo 'Unknown')
    echo
    echo -n "SELinux: "
    if [ "$selinux_status" = "Enforcing" ]; then
        echo "Enforcing - may block headless Chrome/Xvfb. Consider: sudo setenforce 0"
    else
        echo "$selinux_status"
    fi
fi

# Check display
echo
echo -n "DISPLAY variable: "
if [ -n "$DISPLAY" ]; then
    echo "Set to '$DISPLAY'"
else
    echo "NOT SET (expected for headless)"
fi

echo
echo "=== System Status ==="
echo

if [ "$chromium_found" = true ] && [ "$chromedriver_found" = true ]; then
    echo "\u2713 EyeWitness is ready to run!"
    echo
    echo "Test with:"
    echo "  source eyewitness-venv/bin/activate"
    echo "  python Python/EyeWitness.py --single https://example.com"
else
    echo "\u2717 Missing dependencies detected"
    echo
    echo "=== Quick Fix Commands ==="
    echo
    if [ "$chromium_found" = false ]; then
        echo "Install Chromium:"
        echo "  Ubuntu/Debian/Kali:     sudo apt install chromium-browser"
        echo "  CentOS/RHEL/Rocky:      sudo dnf install epel-release && sudo dnf install chromium"
        echo "  RHEL (no EPEL access):  see setup/setup.sh for Google Chrome fallback"
        echo "  Arch:                   sudo pacman -S chromium"
    fi
    if [ "$chromedriver_found" = false ]; then
        echo
        echo "Install/locate ChromeDriver:"
        echo "  Ubuntu/Debian:          sudo apt install chromium-chromedriver"
        echo "  CentOS/RHEL/Rocky:      bundled in chromium package; run setup.sh to symlink"
        echo "  Or run:                 sudo ./setup.sh"
    fi
    echo
    echo "Complete setup:"
    echo "  sudo ./setup.sh"
fi
