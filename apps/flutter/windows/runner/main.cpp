#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single-instance guard.
  //
  // Closing the main window only hides it to the system tray (see
  // setPreventClose/onWindowClose in platform/desktop.dart), so the process
  // keeps running. Without this guard, launching the exe again silently starts
  // a second instance, which adds a second tray icon. The previous Electron
  // implementation handled the same problem with
  // app.requestSingleInstanceLock(); the migration to Flutter dropped it.
  //
  // The handle is intentionally left open for the lifetime of the process so
  // the named mutex stays alive; closing it here would release the name.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, L"Local\\ZjuCampusAgent_SingleInstance");
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance already owns the mutex: surface its window (it may be
    // hidden in the tray) and let this process exit.
    if (HWND existing =
            ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr)) {
      ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"zju_campus_agent", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
