#include "jump_list_manager.h"

#include <windows.h>

#include <objbase.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>
#include <thread>

namespace {

using Microsoft::WRL::ComPtr;

void RunAddUserTasks() {
  const HRESULT hr = ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(hr)) {
    jump_list::AddUserTasks();
    ::CoUninitialize();
  }
}

// PKEY_Title — מוגדר מקומית במקום להסתמך על <propkey.h>, שמספק רק הצהרה
// (לא הגדרה) ללא INITGUID, ועלול להיכלל מראש דרך shell headers ולשבור את
// הקישור. ה-GUID וה-pid הם הערכים הקבועים של PKEY_Title.
const PROPERTYKEY kPropertyKeyTitle = {
    {0xF29F85E0,
     0x4FF9,
     0x1068,
     {0xAB, 0x91, 0x08, 0x00, 0x2B, 0x27, 0xB3, 0xD9}},
    2};

// יוצר IShellLink למשימה: מריץ את ה-exe הנוכחי עם ה-URI הנתון, וכותרתו
// להצגה נקבעת דרך PKEY_Title.
HRESULT CreateTaskShellLink(const std::wstring& arguments,
                            const std::wstring& title, IShellLinkW** out_link) {
  *out_link = nullptr;

  ComPtr<IShellLinkW> link;
  HRESULT hr = ::CoCreateInstance(CLSID_ShellLink, nullptr,
                                  CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link));
  if (FAILED(hr)) {
    return hr;
  }

  wchar_t exe_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return HRESULT_FROM_WIN32(::GetLastError());
  }
  link->SetPath(exe_path);
  link->SetIconLocation(exe_path, 0);
  link->SetArguments(arguments.c_str());

  // הכותרת הנראית ב-Jump List נקבעת דרך PKEY_Title על ה-IPropertyStore של
  // הקיצור — IShellLink::SetDescription לבדו אינו מספיק.
  ComPtr<IPropertyStore> store;
  hr = link.As(&store);
  if (FAILED(hr)) {
    return hr;
  }

  PROPVARIANT title_value;
  hr = ::InitPropVariantFromString(title.c_str(), &title_value);
  if (FAILED(hr)) {
    return hr;
  }
  hr = store->SetValue(kPropertyKeyTitle, title_value);
  ::PropVariantClear(&title_value);
  if (FAILED(hr)) {
    return hr;
  }
  hr = store->Commit();
  if (FAILED(hr)) {
    return hr;
  }

  *out_link = link.Detach();
  return S_OK;
}

}  // namespace

bool jump_list::AddUserTasks() {
  ComPtr<ICustomDestinationList> destination_list;
  HRESULT hr =
      ::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&destination_list));
  if (FAILED(hr)) {
    return false;
  }

  UINT max_slots = 0;
  ComPtr<IObjectArray> removed;
  hr = destination_list->BeginList(&max_slots, IID_PPV_ARGS(&removed));
  if (FAILED(hr)) {
    return false;
  }

  ComPtr<IObjectCollection> collection;
  hr = ::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr,
                          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&collection));
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  ComPtr<IShellLinkW> new_window;
  hr = CreateTaskShellLink(L"otzaria://window/new", L"חלון חדש", &new_window);
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }
  collection->AddObject(new_window.Get());

  ComPtr<IObjectArray> items;
  hr = collection.As(&items);
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  hr = destination_list->AddUserTasks(items.Get());
  if (FAILED(hr)) {
    destination_list->AbortList();
    return false;
  }

  return SUCCEEDED(destination_list->CommitList());
}

namespace {
std::thread g_tasks_thread;
}  // namespace

void jump_list::AddUserTasksAsync() {
  try {
    g_tasks_thread = std::thread(RunAddUserTasks);
  } catch (const std::exception&) {
    // בלי thread ה-Jump List נשאר בלי המשימות; זה עדיף על עצירת ה-UI thread.
  }
}

void jump_list::WaitForPendingTasks(DWORD timeout_ms) {
  if (!g_tasks_thread.joinable()) return;
  // ExitProcess באמצע CommitList הורג את ה-thread בתוך קוד ה-Shell — מסלול
  // ידוע לתקיעה ביציאה. ממתינים מעט, ואם עדיין רץ — מנתקים.
  const HANDLE handle = g_tasks_thread.native_handle();
  if (::WaitForSingleObject(handle, timeout_ms) == WAIT_OBJECT_0) {
    g_tasks_thread.join();
  } else {
    g_tasks_thread.detach();
  }
}
