#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length <= 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

namespace {

bool g_kiosk_mode_enabled = false;
HHOOK g_kiosk_keyboard_hook = nullptr;
STICKYKEYS g_orig_sticky_keys = {sizeof(STICKYKEYS), 0};
TOGGLEKEYS g_orig_toggle_keys = {sizeof(TOGGLEKEYS), 0};
FILTERKEYS g_orig_filter_keys = {sizeof(FILTERKEYS), 0};
bool g_accessibility_shortcuts_disabled = false;

LRESULT CALLBACK KioskKeyboardHookProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_kiosk_mode_enabled) {
    auto* pkb = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    if (pkb != nullptr) {
      // 1. Windows Logo Keys (VK_LWIN 0x5B, VK_RWIN 0x5C)
      if (pkb->vkCode == VK_LWIN || pkb->vkCode == VK_RWIN) {
        return 1;
      }
      // 2. Alt+Tab, Alt+Esc, Alt+Space
      const bool is_alt_down = (pkb->flags & LLKHF_ALTDOWN) != 0;
      if (is_alt_down && (pkb->vkCode == VK_TAB || pkb->vkCode == VK_ESCAPE ||
                          pkb->vkCode == VK_SPACE)) {
        return 1;
      }
      // 3. Ctrl+Esc (Start Menu)
      const bool is_ctrl_down = (::GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
      if (is_ctrl_down && pkb->vkCode == VK_ESCAPE) {
        return 1;
      }
      // 4. Ctrl+Shift+Esc (Task Manager)
      const bool is_shift_down = (::GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
      if (is_ctrl_down && is_shift_down && pkb->vkCode == VK_ESCAPE) {
        return 1;
      }
    }
  }
  return ::CallNextHookEx(g_kiosk_keyboard_hook, code, wparam, lparam);
}

void DisableAccessibilityShortcuts() {
  ::SystemParametersInfoW(SPI_GETSTICKYKEYS, sizeof(STICKYKEYS),
                          &g_orig_sticky_keys, 0);
  STICKYKEYS sk = g_orig_sticky_keys;
  sk.dwFlags &= ~SKF_HOTKEYACTIVE;
  ::SystemParametersInfoW(SPI_SETSTICKYKEYS, sizeof(STICKYKEYS), &sk, 0);

  ::SystemParametersInfoW(SPI_GETTOGGLEKEYS, sizeof(TOGGLEKEYS),
                          &g_orig_toggle_keys, 0);
  TOGGLEKEYS tk = g_orig_toggle_keys;
  tk.dwFlags &= ~TKF_HOTKEYACTIVE;
  ::SystemParametersInfoW(SPI_SETTOGGLEKEYS, sizeof(TOGGLEKEYS), &tk, 0);

  ::SystemParametersInfoW(SPI_GETFILTERKEYS, sizeof(FILTERKEYS),
                          &g_orig_filter_keys, 0);
  FILTERKEYS fk = g_orig_filter_keys;
  fk.dwFlags &= ~FKF_HOTKEYACTIVE;
  ::SystemParametersInfoW(SPI_SETFILTERKEYS, sizeof(FILTERKEYS), &fk, 0);

  g_accessibility_shortcuts_disabled = true;
}

void RestoreAccessibilityShortcuts() {
  if (g_accessibility_shortcuts_disabled) {
    ::SystemParametersInfoW(SPI_SETSTICKYKEYS, sizeof(STICKYKEYS),
                            &g_orig_sticky_keys, 0);
    ::SystemParametersInfoW(SPI_SETTOGGLEKEYS, sizeof(TOGGLEKEYS),
                            &g_orig_toggle_keys, 0);
    ::SystemParametersInfoW(SPI_SETFILTERKEYS, sizeof(FILTERKEYS),
                            &g_orig_filter_keys, 0);
    g_accessibility_shortcuts_disabled = false;
  }
}

}  // namespace

void SetKioskMode(bool enabled) {
  g_kiosk_mode_enabled = enabled;
}

bool IsKioskModeEnabled() {
  return g_kiosk_mode_enabled;
}

void InstallKioskKeyboardHook() {
  if (g_kiosk_keyboard_hook == nullptr) {
    g_kiosk_keyboard_hook = ::SetWindowsHookExW(
        WH_KEYBOARD_LL, KioskKeyboardHookProc, ::GetModuleHandleW(nullptr), 0);
  }
  DisableAccessibilityShortcuts();
}

void UninstallKioskKeyboardHook() {
  if (g_kiosk_keyboard_hook != nullptr) {
    ::UnhookWindowsHookEx(g_kiosk_keyboard_hook);
    g_kiosk_keyboard_hook = nullptr;
  }
  RestoreAccessibilityShortcuts();
}

