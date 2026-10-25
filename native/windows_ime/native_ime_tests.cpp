// Message-only windows below are never shown or focused. No desktop input is generated.
#include "windows_ime.cpp"
#include <cstdio>
#include <vector>
#include <utility>
static std::u16string fake_result;
static std::u16string forwarded;
static LPARAM last_composition_flags = 0;
static std::u16string fake_reader(HWND) { return fake_result; }
static LRESULT CALLBACK test_window_proc(HWND hwnd, UINT msg, WPARAM value, LPARAM flags) {
    if (msg == WM_CHAR || msg == WM_IME_CHAR) { forwarded += static_cast<char16_t>(value); return 0; }
    if (msg == WM_IME_COMPOSITION) { last_composition_flags = flags; return 0; }
    return DefWindowProcW(hwnd, msg, value, flags);
}
static std::vector<std::pair<const char *, bool>> checks;
static void check(const char *name, bool result) { checks.emplace_back(name, result); }
int main() {
    static_assert(sizeof(void *) == 8 && sizeof(wchar_t) == 2, "Windows x64 required");
    ImeCommitBuffer buffer;
    buffer.capture(u"안");
    buffer.capture(u"녕");
    check("buffer_preserves_adjacent_results", buffer.take() == u"안녕");
    check("buffer_drains_once", buffer.take().empty());
    buffer.capture(u"가나 까까 값이 읽어");
    check("no_hangul_reconstruction", buffer.take() == u"가나 까까 값이 읽어");
    buffer.capture(u"日本語 中文 🙂");
    check("utf16_surrogates_preserved", buffer.take() == u"日本語 中文 🙂");
    buffer.capture(u"안");
    check("duplicate_commit_consumed", buffer.consume_duplicate(u'안'));
    check("unrelated_latin_not_consumed", !buffer.consume_duplicate(u'a'));
    buffer.clear();
    check("cancel_clears_pending", buffer.take().empty());
    WNDCLASSEXW type = {};
    type.cbSize = sizeof(type);
    type.hInstance = GetModuleHandleW(nullptr);
    type.lpfnWndProc = test_window_proc;
    type.lpszClassName = L"GraduateProjectImeMessageOnlyTest";
    check("register_message_only_class", RegisterClassExW(&type) != 0);
    HWND hwnd = CreateWindowExW(0, type.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, type.hInstance, nullptr);
    check("message_only_window_created", hwnd != nullptr && FindWindowExW(HWND_MESSAGE, nullptr, type.lpszClassName, L"") == hwnd);
    check("no_visible_window", !IsWindowVisible(hwnd));
    ImeBridge bridge, second;
    check("invalid_handle_rejected", !bridge.attach(nullptr));
    check("own_thread_attach", bridge.attach(hwnd));
    check("duplicate_attach_rejected", !second.attach(hwnd));
    result_reader = fake_reader;
    bridge.enabled = true;
    std::u16string phrase = u"안녕하세요";
    for (char16_t unit : phrase) {
        fake_result.assign(1, unit);
        SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR | GCS_COMPSTR | GCS_CURSORPOS);
        SendMessageW(hwnd, WM_CHAR, unit, 0); // Duplicate path must never reach the original handler.
        SendMessageW(hwnd, WM_IME_STARTCOMPOSITION, 0, 0); // Next syllable cannot erase the queued result.
    }
    check("windows_message_results_accumulate", bridge.buffer.take() == phrase);
    check("duplicate_native_chars_blocked", forwarded.empty());
    check("preedit_flags_preserved", (last_composition_flags & GCS_COMPSTR) && (last_composition_flags & GCS_CURSORPOS));
    check("default_result_reinsertion_disabled", !(last_composition_flags & GCS_RESULTSTR));
    check("capture_counter", bridge.buffer.result_count == 5);
    check("duplicate_counter", bridge.buffer.suppressed_count == 5);
    SendMessageW(hwnd, WM_CHAR, L'x', 0);
    check("ordinary_text_uses_same_ordered_buffer", bridge.buffer.take() == u"x" && forwarded.empty());
    SendMessageW(hwnd, WM_CHAR, L'A', 0);
    fake_result = u"한";
    SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR);
    SendMessageW(hwnd, WM_CHAR, L'1', 0);
    check("mixed_latin_and_hangul_keep_order", bridge.buffer.take() == u"A한1");
    SendMessageW(hwnd, WM_IME_CHAR, L'안', 0);
    SendMessageW(hwnd, WM_IME_CHAR, L'녕', 0);
    check("ime_char_only_driver_supported", bridge.buffer.take() == u"안녕");
    SendMessageW(hwnd, WM_CHAR, L'안', 0);
    SendMessageW(hwnd, WM_CHAR, L'녕', 0);
    check("char_only_driver_supported", bridge.buffer.take() == u"안녕");
    fake_result = u"요";
    SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR);
    SendMessageW(hwnd, WM_IME_CHAR, L'요', 0);
    SendMessageW(hwnd, WM_CHAR, L'요', 0);
    check("both_duplicate_delivery_paths_suppressed", bridge.buffer.take() == u"요");
    SendMessageW(hwnd, WM_IME_CHAR, L'하', 0);
    SendMessageW(hwnd, WM_IME_CHAR, L'하', 0);
    check("repeated_syllable_not_deduplicated", bridge.buffer.take() == u"하하");
    fake_result.clear();
    SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR);
    check("empty_result_forwarded_without_guessing", last_composition_flags == GCS_RESULTSTR);
    fake_result = u"가나 까까 🙂";
    SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR);
    check("multi_character_native_result", bridge.buffer.take() == fake_result);
    bridge.enabled = false;
    fake_result = u"무시";
    SendMessageW(hwnd, WM_IME_COMPOSITION, 0, GCS_RESULTSTR);
    check("inactive_does_not_capture", bridge.buffer.take().empty());
    bridge.detach();
    DWORD_PTR reference = 0;
    check("detach_removes_only_our_subclass", !GetWindowSubclass(hwnd, ImeBridge::window_proc, subclass_id, &reference));
    check("can_reattach", bridge.attach(hwnd));
    DestroyWindow(hwnd);
    check("window_destruction_clears_handle", bridge.window == nullptr);
    bridge.detach();
    UnregisterClassW(type.lpszClassName, type.hInstance);
    bool all = true;
    printf("{\"suite\":\"native_ime_messages\",\"check_count\":%zu,\"checks\":{", checks.size());
    for (size_t i = 0; i < checks.size(); ++i) {
        if (i) printf(",");
        printf("\"%s\":%s", checks[i].first, checks[i].second ? "true" : "false");
        all = all && checks[i].second;
    }
    printf("},\"passed\":%s,\"visible_ui_created\":false,\"keyboard_or_mouse_input_generated\":false,\"actual_microsoft_ime_driver_tested\":false}\n", all ? "true" : "false");
    return all ? 0 : 1;
}
