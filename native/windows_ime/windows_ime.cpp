#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <imm.h>
#include <commctrl.h>
#include <cstdint>
#include <string>
#include "generated/gdextension_interface.h"
#include "ime_commit_buffer.h"
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "comctl32.lib")

static GDExtensionClassLibraryPtr library_handle;
static GDExtensionInterfaceStringNameNewWithLatin1Chars name_new;
static GDExtensionInterfaceStringNewWithUtf16CharsAndLen string_new;
static GDExtensionInterfaceVariantGetPtrDestructor get_destructor;
static GDExtensionInterfaceGetVariantFromTypeConstructor from_type;
static GDExtensionInterfaceGetVariantToTypeConstructor to_type;
static GDExtensionInterfaceClassdbConstructObject3 construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbGetMethodBind get_bind;
static GDExtensionInterfaceObjectMethodBindPtrcall ptrcall;
static GDExtensionInterfaceVariantNewNil nil_new;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionMethodBindPtr notification_bind;

struct Opaque { alignas(8) uint8_t bytes[8] = {}; };
struct Name {
    Opaque data;
    explicit Name(const char *value) { name_new(&data, value, false); }
    ~Name() { get_destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&data); }
    operator void *() { return &data; }
};
static constexpr UINT_PTR subclass_id = 0x4750494D;
static std::u16string read_windows_result(HWND hwnd) {
    std::u16string result;
    HIMC context = ImmGetContext(hwnd);
    if (!context) return result;
    LONG bytes = ImmGetCompositionStringW(context, GCS_RESULTSTR, nullptr, 0);
    if (bytes > 0 && bytes <= 65536 && bytes % sizeof(wchar_t) == 0) {
        result.resize(static_cast<size_t>(bytes) / sizeof(wchar_t));
        if (ImmGetCompositionStringW(context, GCS_RESULTSTR, result.data(), bytes) != bytes) result.clear();
    }
    ImmReleaseContext(hwnd, context);
    return result;
}
static std::u16string (*result_reader)(HWND) = read_windows_result;
struct ImeBridge {
    GDExtensionObjectPtr owner = nullptr;
    HWND window = nullptr;
    bool enabled = false;
    DWORD last_error = 0;
    ImeCommitBuffer buffer;
    static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam, UINT_PTR id, DWORD_PTR data);
    bool attach(HWND target) {
        if (target == window && window) return true;
        detach();
        DWORD process_id = 0;
        DWORD thread_id = GetWindowThreadProcessId(target, &process_id);
        // Never install into another application or another thread.
        if (!IsWindow(target) || process_id != GetCurrentProcessId() || thread_id != GetCurrentThreadId()) {
            last_error = ERROR_INVALID_WINDOW_HANDLE;
            return false;
        }
        DWORD_PTR existing = 0;
        if (GetWindowSubclass(target, window_proc, subclass_id, &existing)) { last_error = ERROR_ALREADY_EXISTS; return false; }
        if (!SetWindowSubclass(target, window_proc, subclass_id, reinterpret_cast<DWORD_PTR>(this))) {
            last_error = GetLastError(); return false;
        }
        window = target;
        last_error = 0;
        return true;
    }
    void detach() {
        enabled = false;
        if (window && IsWindow(window)) {
            RemoveWindowSubclass(window, window_proc, subclass_id);
        }
        window = nullptr; buffer.clear();
    }
    bool control_composition(DWORD command) {
        if (!enabled || !window) return false;
        HIMC context = ImmGetContext(window);
        if (!context) return false;
        const BOOL ok = ImmNotifyIME(context, NI_COMPOSITIONSTR, command, 0);
        ImmReleaseContext(window, context);
        return ok != FALSE;
    }
    ~ImeBridge() { detach(); }
};
LRESULT CALLBACK ImeBridge::window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR data) {
    auto *self = reinterpret_cast<ImeBridge *>(data);
    if (!self) return DefSubclassProc(hwnd, msg, wparam, lparam);
    if (self->enabled) {
        if (msg == WM_IME_COMPOSITION && (lparam & GCS_RESULTSTR)) {
            const std::u16string result = result_reader(hwnd);
            if (!result.empty()) {
                self->buffer.capture(result);
                // Godot still updates preedit/caret, but DefWindowProc must not reinsert this result.
                lparam &= ~(GCS_RESULTSTR | GCS_RESULTCLAUSE | GCS_RESULTREADSTR | GCS_RESULTREADCLAUSE);
            }
        } else if ((msg == WM_CHAR || msg == WM_IME_CHAR) && wparam >= 32) {
            self->buffer.capture_character(static_cast<char16_t>(wparam), msg == WM_IME_CHAR);
            return 0;
        }
    }
    if (msg == WM_NCDESTROY) {
        RemoveWindowSubclass(hwnd, window_proc, subclass_id);
        self->window = nullptr; self->enabled = false;
    }
    return DefSubclassProc(hwnd, msg, wparam, lparam);
}

static GDExtensionObjectPtr create_instance(void *, GDExtensionBool notify) {
    auto *self = new ImeBridge;
    Name node("Node"), own("WindowsIMEBridge");
    self->owner = construct_object(node);
    set_instance(self->owner, own, self);
    if (notify) {
        int64_t what = 0; GDExtensionBool reversed = false;
        const void *arguments[] = { &what, &reversed };
        ptrcall(notification_bind, self->owner, arguments, nullptr);
    }
    return self->owner;
}
static void free_instance(void *, GDExtensionClassInstancePtr instance) { delete static_cast<ImeBridge *>(instance); }

enum Method { ATTACH, ENABLE, DRAIN, COMPLETE, DETACH, IS_ATTACHED, ERROR_CODE, CAPTURE_COUNT, SUPPRESSED_COUNT, CANCEL };
static void return_bool(GDExtensionVariantPtr output, bool value) {
    GDExtensionBool result = value;
    from_type(GDEXTENSION_VARIANT_TYPE_BOOL)(output, &result);
}
static void return_int(GDExtensionVariantPtr output, int64_t value) { from_type(GDEXTENSION_VARIANT_TYPE_INT)(output, &value); }
static void call_method(void *userdata, GDExtensionClassInstancePtr instance, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr output, GDExtensionCallError *error) {
    error->error = GDEXTENSION_CALL_OK;
    auto *self = static_cast<ImeBridge *>(instance);
    Method method = static_cast<Method>(reinterpret_cast<intptr_t>(userdata));
    if ((method == ATTACH || method == ENABLE) && count != 1) { error->error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS; nil_new(output); return; }
    if (method == ATTACH) {
        if (variant_type(args[0]) != GDEXTENSION_VARIANT_TYPE_INT) { error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; nil_new(output); return; }
        int64_t value = 0; to_type(GDEXTENSION_VARIANT_TYPE_INT)(&value, const_cast<void *>(args[0]));
        return_bool(output, self->attach(reinterpret_cast<HWND>(value)));
    } else if (method == ENABLE) {
        GDExtensionBool value = false;
        to_type(GDEXTENSION_VARIANT_TYPE_BOOL)(&value, const_cast<void *>(args[0]));
        self->enabled = value && self->window;
        if (!self->enabled) self->buffer.clear();
        nil_new(output);
    } else if (method == DRAIN) {
        std::u16string value = self->buffer.take();
        Opaque result;
        string_new(&result, value.data(), static_cast<GDExtensionInt>(value.size()));
        from_type(GDEXTENSION_VARIANT_TYPE_STRING)(output, &result);
        get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&result);
    } else if (method == COMPLETE) return_bool(output, self->control_composition(CPS_COMPLETE));
    else if (method == CANCEL) return_bool(output, self->control_composition(CPS_CANCEL));
    else if (method == DETACH) { self->detach(); nil_new(output); }
    else if (method == IS_ATTACHED) return_bool(output, self->window != nullptr);
    else if (method == ERROR_CODE) return_int(output, self->last_error);
    else if (method == CAPTURE_COUNT) return_int(output, self->buffer.result_count);
    else if (method == SUPPRESSED_COUNT) return_int(output, self->buffer.suppressed_count);
}
static void bind_method(const char *method, Method id, GDExtensionVariantType result_type, GDExtensionVariantType argument = GDEXTENSION_VARIANT_TYPE_NIL) {
    Name own("WindowsIMEBridge"), name(method), empty(""), argument_name("value");
    Opaque empty_string;
    string_new(&empty_string, u"", 0);
    GDExtensionPropertyInfo result = {};
    result.type = result_type; result.name = empty; result.class_name = empty;
    result.hint_string = &empty_string;
    GDExtensionPropertyInfo arg = {};
    arg.type = argument; arg.name = argument_name; arg.class_name = empty;
    arg.hint_string = &empty_string;
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo info = {};
    info.name = name; info.method_userdata = reinterpret_cast<void *>(static_cast<intptr_t>(id));
    info.call_func = call_method; info.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    info.has_return_value = result_type != GDEXTENSION_VARIANT_TYPE_NIL;
    info.return_value_info = &result;
    info.argument_count = argument == GDEXTENSION_VARIANT_TYPE_NIL ? 0 : 1;
    info.arguments_info = &arg; info.arguments_metadata = &metadata;
    register_method(library_handle, own, &info);
    get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&empty_string);
}
static void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    Name own("WindowsIMEBridge"), parent("Node"), object("Object"), notification("notification");
    notification_bind = get_bind(object, notification, 4023243586);
    GDExtensionClassCreationInfo6 info = {};
    Opaque empty_string;
    string_new(&empty_string, u"", 0);
    info.icon_path = &empty_string;
    info.is_exposed = true;
    info.create_instance_func = create_instance;
    info.free_instance_func = free_instance;
    register_class(library_handle, own, parent, &info);
    get_destructor(GDEXTENSION_VARIANT_TYPE_STRING)(&empty_string);
    bind_method("attach", ATTACH, GDEXTENSION_VARIANT_TYPE_BOOL, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("set_active", ENABLE, GDEXTENSION_VARIANT_TYPE_NIL, GDEXTENSION_VARIANT_TYPE_BOOL);
    bind_method("drain_commits", DRAIN, GDEXTENSION_VARIANT_TYPE_STRING);
    bind_method("complete_composition", COMPLETE, GDEXTENSION_VARIANT_TYPE_BOOL);
    bind_method("cancel_composition", CANCEL, GDEXTENSION_VARIANT_TYPE_BOOL);
    bind_method("detach", DETACH, GDEXTENSION_VARIANT_TYPE_NIL);
    bind_method("is_attached", IS_ATTACHED, GDEXTENSION_VARIANT_TYPE_BOOL);
    bind_method("get_last_error", ERROR_CODE, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("get_capture_count", CAPTURE_COUNT, GDEXTENSION_VARIANT_TYPE_INT);
    bind_method("get_suppressed_count", SUPPRESSED_COUNT, GDEXTENSION_VARIANT_TYPE_INT);
}
static void terminate(void *, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) { Name own("WindowsIMEBridge"); unregister_class(library_handle, own); }
}
extern "C" __declspec(dllexport) GDExtensionBool windows_ime_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
    library_handle = library;
#define LOAD(field, type, name) field = reinterpret_cast<type>(get_proc(name)); if (!field) return false
    LOAD(name_new, GDExtensionInterfaceStringNameNewWithLatin1Chars, "string_name_new_with_latin1_chars");
    LOAD(string_new, GDExtensionInterfaceStringNewWithUtf16CharsAndLen, "string_new_with_utf16_chars_and_len");
    LOAD(get_destructor, GDExtensionInterfaceVariantGetPtrDestructor, "variant_get_ptr_destructor");
    LOAD(from_type, GDExtensionInterfaceGetVariantFromTypeConstructor, "get_variant_from_type_constructor");
    LOAD(to_type, GDExtensionInterfaceGetVariantToTypeConstructor, "get_variant_to_type_constructor");
    LOAD(construct_object, GDExtensionInterfaceClassdbConstructObject3, "classdb_construct_object3");
    LOAD(set_instance, GDExtensionInterfaceObjectSetInstance, "object_set_instance");
    LOAD(register_class, GDExtensionInterfaceClassdbRegisterExtensionClass6, "classdb_register_extension_class6");
    LOAD(register_method, GDExtensionInterfaceClassdbRegisterExtensionClassMethod, "classdb_register_extension_class_method");
    LOAD(unregister_class, GDExtensionInterfaceClassdbUnregisterExtensionClass, "classdb_unregister_extension_class");
    LOAD(get_bind, GDExtensionInterfaceClassdbGetMethodBind, "classdb_get_method_bind");
    LOAD(ptrcall, GDExtensionInterfaceObjectMethodBindPtrcall, "object_method_bind_ptrcall");
    LOAD(nil_new, GDExtensionInterfaceVariantNewNil, "variant_new_nil");
    LOAD(variant_type, GDExtensionInterfaceVariantGetType, "variant_get_type");
#undef LOAD
    init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize = initialize;
    init->deinitialize = terminate;
    return true;
}
