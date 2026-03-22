#!/usr/bin/env python3
# Platform detection stuff - got tired of hardcoding paths everywhere

import platform
import os
import sys
import shutil
import subprocess
from pathlib import Path


class PlatformManager:
    # Handles OS differences so we don't have to check platform.system() everywhere

    def __init__(self):
        self.system  = platform.system().lower()
        self.machine = platform.machine().lower()
        self.is_windows = self.system == 'windows'
        self.is_linux   = self.system == 'linux'
        self.is_mac     = self.system == 'darwin'
        self.is_unix    = self.is_linux or self.is_mac
        self.is_docker  = self._check_docker_environment()
        self.has_display = self._check_display_available()
        self.is_admin   = self._check_admin_privileges()
        # Detect RHEL-family so callers can branch on it
        self.is_rhel_family = self._check_rhel_family()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _check_rhel_family(self):
        """Return True when running on RHEL, CentOS, Rocky, AlmaLinux, or Fedora."""
        try:
            with open('/etc/os-release') as f:
                content = f.read().lower()
            rhel_ids = ('rhel', 'centos', 'rocky', 'almalinux', 'fedora')
            return any(
                f'id={rid}' in content or f'id_like={rid}' in content
                for rid in rhel_ids
            )
        except OSError:
            return False

    def _check_display_available(self):
        if self.is_windows:
            return True  # windows always has display
        else:
            return os.environ.get('DISPLAY') is not None

    def _check_admin_privileges(self):
        try:
            if self.is_windows:
                import ctypes
                return ctypes.windll.shell32.IsUserAnAdmin() != 0
            else:
                return os.geteuid() == 0
        except (AttributeError, OSError):
            return False

    def _check_docker_environment(self):
        """Check if running inside Docker container"""
        docker_indicators = [
            os.path.exists('/.dockerenv'),
            self._check_cgroup_docker(),
            os.environ.get('DOCKER_CONTAINER') == '1',
            self._check_docker_networking()
        ]
        return any(docker_indicators)

    def _check_cgroup_docker(self):
        """Check if cgroup indicates Docker"""
        try:
            with open('/proc/1/cgroup', 'r') as f:
                content = f.read()
            return 'docker' in content.lower() or 'containerd' in content.lower()
        except (IOError, OSError):
            return False

    def _check_docker_networking(self):
        """Check for Docker-specific networking indicators"""
        try:
            hostname = os.environ.get('HOSTNAME', '')
            return len(hostname) == 12 and hostname.isalnum()
        except Exception:
            return False

    # ------------------------------------------------------------------
    # Public helpers
    # ------------------------------------------------------------------

    def clear_screen(self):
        os.system('cls' if self.is_windows else 'clear')

    def get_chromium_paths(self):
        """Return a list of candidate Chromium binary paths for this platform."""
        if self.is_windows:
            paths = [
                r'C:\Program Files\Google\Chrome\Application\chrome.exe',
                r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
            ]
            home = Path.home()
            paths.extend([
                str(home / 'AppData' / 'Local' / 'Google' / 'Chrome' / 'Application' / 'chrome.exe'),
                str(home / 'AppData' / 'Local' / 'Chromium' / 'Application' / 'chromium.exe')
            ])
            return paths

        elif self.is_linux:
            return [
                # Debian / Ubuntu / Kali
                '/usr/bin/chromium-browser',
                '/usr/bin/chromium',
                '/usr/bin/google-chrome',
                '/usr/bin/google-chrome-stable',
                '/snap/bin/chromium',
                '/usr/local/bin/chromium',
                # RHEL / CentOS / Rocky / AlmaLinux (EPEL package layout)
                '/usr/lib64/chromium-browser/chromium-browser',
                '/usr/libexec/chromium-browser/chromium-browser',
                # Generic fallback
                '/opt/google/chrome/chrome',
            ]

        elif self.is_mac:
            return [
                '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
                '/Applications/Chromium.app/Contents/MacOS/Chromium',
                str(Path.home() / 'Applications' / 'Google Chrome.app'
                    / 'Contents' / 'MacOS' / 'Google Chrome')
            ]
        return []

    def find_chromium_executable(self):
        """Locate a Chromium/Chrome binary, checking PATH then hardcoded paths."""
        for name in ['chromium-browser', 'chromium', 'google-chrome', 'google-chrome-stable']:
            path = shutil.which(name)
            if path:
                return path
        for path in self.get_chromium_paths():
            if Path(path).exists():
                return path
        return None

    def get_chromedriver_paths(self):
        """Return a list of candidate chromedriver binary paths for this platform.

        RHEL note: chromedriver is bundled inside the chromium RPM package and
        is NOT automatically placed on PATH.  setup.sh creates the symlink at
        /usr/local/bin/chromedriver, which is why that path appears near the top
        of the RHEL-specific section.  The raw package paths are also listed as
        fallbacks in case the symlink was not created.
        """
        if self.is_windows:
            return [
                r'C:\Program Files\ChromeDriver\chromedriver.exe',
                r'C:\Program Files (x86)\ChromeDriver\chromedriver.exe',
                str(Path.home() / 'AppData' / 'Local' / 'ChromeDriver' / 'chromedriver.exe')
            ]

        elif self.is_linux:
            return [
                # Standard / Debian / Ubuntu / Kali locations
                '/usr/bin/chromedriver',
                '/usr/local/bin/chromedriver',    # symlink created by setup.sh on RHEL
                '/snap/bin/chromium.chromedriver',
                '/usr/lib/chromium-browser/chromedriver',
                # RHEL / CentOS / Rocky / AlmaLinux:
                # These are the real locations inside the chromium RPM.
                # They will not be in PATH unless setup.sh was run.
                '/usr/lib64/chromium-browser/chromedriver',
                '/usr/libexec/chromium-browser/chromedriver',
            ]

        elif self.is_mac:
            return [
                '/usr/local/bin/chromedriver',
                '/opt/homebrew/bin/chromedriver',
                str(Path.home() / 'Applications' / 'chromedriver')
            ]
        return []

    def find_chromedriver(self):
        """Locate a chromedriver binary, checking PATH then hardcoded paths."""
        for name in ['chromedriver', 'chromium-chromedriver']:
            path = shutil.which(name)
            if path:
                return path
        for path in self.get_chromedriver_paths():
            if Path(path).exists():
                return path
        return None

    def needs_virtual_display(self):
        # windows has native headless, unix needs xvfb if no display
        return not self.is_windows and not self.has_display

    def can_use_virtual_display(self) -> bool:
        """Check if virtual display can be used on this platform"""
        if self.is_windows:
            return False
        try:
            import pyvirtualdisplay  # noqa: F401
            return shutil.which('Xvfb') is not None
        except ImportError:
            return False

    def get_system_install_commands(self) -> dict:
        """Get system package installation commands for current platform."""
        if self.is_windows:
            return {
                'chrome':  'choco install googlechrome -y',
                'python':  'choco install python -y',
                'git':     'choco install git -y',
            }

        elif self.is_linux:
            if shutil.which('apt-get'):
                # Debian / Ubuntu / Kali
                return {
                    'chromium': 'sudo apt-get install -y chromium-browser chromium-chromedriver',
                    'xvfb':     'sudo apt-get install -y xvfb',
                    'python':   'sudo apt-get install -y python3 python3-pip python3-dev',
                    'tools':    'sudo apt-get install -y wget curl jq cmake',
                }
            elif shutil.which('dnf') or shutil.which('yum'):
                # RHEL / CentOS / Rocky / AlmaLinux / Fedora
                # Key differences:
                #   - python3-venv is NOT a separate package on RHEL
                #   - chromedriver is bundled in chromium RPM, not in PATH
                #   - jq/cmake/chromium all require EPEL to be enabled first
                pkgmgr = 'dnf' if shutil.which('dnf') else 'yum'
                return {
                    'epel': f'sudo {pkgmgr} install -y epel-release',
                    'chromium': (
                        f'sudo {pkgmgr} install -y chromium && '
                        'sudo ln -sf /usr/lib64/chromium-browser/chromedriver '
                        '/usr/local/bin/chromedriver'
                    ),
                    'xvfb':   f'sudo {pkgmgr} install -y xorg-x11-server-Xvfb',
                    'python': f'sudo {pkgmgr} install -y python3 python3-pip python3-devel',
                    'tools':  f'sudo {pkgmgr} install -y wget curl jq cmake',
                }
            elif shutil.which('pacman'):
                # Arch
                return {
                    'chromium': 'sudo pacman -S chromium --noconfirm',
                    'xvfb':     'sudo pacman -S xorg-server-xvfb --noconfirm',
                    'python':   'sudo pacman -S python python-pip --noconfirm',
                    'tools':    'sudo pacman -S wget curl jq cmake --noconfirm',
                }

        elif self.is_mac:
            return {
                'chrome': 'brew install --cask google-chrome',
                'python': 'brew install python',
                'tools':  'brew install wget curl jq cmake',
            }
        return {}

    def get_requirements_file(self) -> str:
        """Get appropriate requirements file for current platform"""
        return 'requirements-windows.txt' if self.is_windows else 'requirements-unix.txt'

    def validate_environment(self) -> dict:
        """Validate the current environment and return status"""
        status = {
            'platform':                  self.system,
            'python_version':            sys.version,
            'chromium_found':            self.find_chromium_executable() is not None,
            'virtual_display_available': self.can_use_virtual_display(),
            'virtual_display_needed':    self.needs_virtual_display(),
            'admin_privileges':          self.is_admin,
            'is_rhel_family':            self.is_rhel_family,
            'issues': [],
        }

        if not status['chromium_found']:
            status['issues'].append('Chromium not found - install Chromium browser')
        if self.needs_virtual_display() and not self.can_use_virtual_display():
            status['issues'].append(
                'Virtual display needed but not available - install xvfb and pyvirtualdisplay'
            )
        if self.is_rhel_family and self.find_chromedriver() is None:
            status['issues'].append(
                'ChromeDriver not found. On RHEL/CentOS the driver is bundled in the chromium RPM '
                'but not in PATH. Run setup/setup.sh which creates a /usr/local/bin/chromedriver symlink.'
            )
        return status

    def print_environment_info(self) -> None:
        """Print detailed environment information"""
        print(f'Platform:                 {self.system.title()} ({self.machine})')
        print(f'Python:                   {sys.version}')
        print(f'Admin privileges:         {self.is_admin}')
        print(f'RHEL-family:              {self.is_rhel_family}')
        print(f'Display available:        {self.has_display}')
        print(f'Virtual display needed:   {self.needs_virtual_display()}')
        print(f'Virtual display available:{self.can_use_virtual_display()}')
        chromium = self.find_chromium_executable()
        print(f'Chromium:                 {chromium if chromium else "Not found"}')
        driver = self.find_chromedriver()
        print(f'ChromeDriver:             {driver if driver else "Not found"}')
        validation = self.validate_environment()
        if validation['issues']:
            print('\nIssues found:')
            for issue in validation['issues']:
                print(f'  - {issue}')


def setup_virtual_display(platform_mgr: PlatformManager, show_selenium: bool = False):
    """Setup virtual display with proper cross-platform and Docker handling"""
    if not platform_mgr.needs_virtual_display() or show_selenium:
        return None

    # Docker-specific: if DISPLAY is already set, assume Xvfb is running
    if platform_mgr.is_docker:
        display_env = os.environ.get('DISPLAY')
        if display_env:
            print(f'[*] Docker environment detected with DISPLAY={display_env}')
            print('[*] Using existing virtual display from Docker entrypoint')
            return None
        else:
            print('[*] Docker environment detected but no DISPLAY set')
            print('[*] Will attempt to start virtual display')

    if not platform_mgr.can_use_virtual_display():
        if platform_mgr.is_windows:
            return None
        print('[*] Warning: Virtual display needed but not available')
        if platform_mgr.is_rhel_family:
            print('[*] Install with: sudo dnf install xorg-x11-server-Xvfb')
        else:
            print('[*] Install with: sudo apt-get install xvfb  (Debian/Ubuntu)')
        print('[*] Or run with --show-selenium flag')
        return None

    try:
        from pyvirtualdisplay import Display
        display_num = ':1' if platform_mgr.is_docker else ':0'
        display = Display(visible=0, size=(1920, 1080), display=display_num)
        display.start()
        print(f'[*] Started virtual display on {display_num}')
        return display
    except ImportError:
        print('[*] Warning: pyvirtualdisplay package not found')
        print('[*] Install with: pip install pyvirtualdisplay')
        return None
    except Exception as e:
        print(f'[*] Warning: Could not start virtual display: {e}')
        if platform_mgr.is_docker:
            print('[*] Docker: Assuming existing Xvfb is available')
            print('[*] Continuing in headless mode...')
        return None


# Global platform manager instance
platform_mgr = PlatformManager()


if __name__ == '__main__':
    # Testing/diagnostic mode
    print('EyeWitness Platform Detection')
    print('=' * 40)
    platform_mgr.print_environment_info()
